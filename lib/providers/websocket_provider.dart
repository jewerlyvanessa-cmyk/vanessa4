import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/agent_ndjson.dart';
import 'package:http/http.dart' as http;

// WebSocket provider untuk real-time updates
final webSocketProvider =
    StateNotifierProvider<WebSocketNotifier, WebSocketChannel?>((ref) {
      return WebSocketNotifier();
    });

// Provider untuk notification stream
final notificationProvider = StreamProvider<String>((ref) {
  final webSocketNotifier = ref.watch(webSocketProvider.notifier);
  return webSocketNotifier.notificationStream;
});

/// Dipanggil saat server mengirim `force_logout` (mis. superadmin memutus sesi).
typedef AdminForceLogoutCallback = void Function(String? reason);

class WebSocketNotifier extends StateNotifier<WebSocketChannel?> {
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _presenceRetryTimer;
  Timer? _heartbeatTimer;
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;

  /// Terakhir kali server merespons lewat WebSocket (upgrade, pong, dll.).
  /// Dipakai saat HTTP /health timeout tapi saluran WS masih hidup (sering di mobile).
  static DateTime? _lastWsBackendAliveAt;

  /// Usia bukti WS; setelah ini [isBackendReachable] mengandalkan HTTP lagi.
  static const Duration wsBackendProofTtl = Duration(seconds: 90);

  static void markWsBackendAlive() {
    _lastWsBackendAliveAt = DateTime.now();
  }

  static void clearWsBackendAliveProof() {
    _lastWsBackendAliveAt = null;
  }

  static bool wsBackendAliveWithin(Duration maxAge) {
    final t = _lastWsBackendAliveAt;
    if (t == null) return false;
    return DateTime.now().difference(t) <= maxAge;
  }

  /// Jaringan mobile sering putus sesaat; batas terlalu rendah membuat WS berhenti reconnect.
  static const int maxReconnectAttempts = 25;
  static const Duration reconnectDelay = Duration(seconds: 3);
  static const Duration _heartbeatInterval = Duration(seconds: 20);
  static const int _maxPresenceAttempts = 12;
  bool _isLoggedIn = false;
  /// Setelah admin kick: jangan auto-reconnect sampai login lagi.
  bool _suppressReconnect = false;

  /// Di-set dari [VanessaApp] agar token & navigasi ke login bisa dibersihkan.
  static AdminForceLogoutCallback? onAdminForceLogout;
  final StreamController<String> _notificationController =
      StreamController<String>.broadcast();
  final StreamController<dynamic> _rawMessageController =
      StreamController<dynamic>.broadcast();

  Stream<String> get notificationStream => _notificationController.stream;
  Stream<dynamic> get rawMessageStream => _rawMessageController.stream;

  WebSocketNotifier() : super(null) {
    // Don't connect immediately - wait for login
  }

  /// Pastikan WebSocket terhubung dan server mencatat presence (JWT).
  /// [authToken] jika diisi, diset ke [NetworkConfig] sebelum connect/handshake.
  void ensureConnected({String? authToken}) {
    if (authToken != null && authToken.isNotEmpty) {
      NetworkConfig.setAuthToken(authToken);
    }
    _suppressReconnect = false;
    if (!_isLoggedIn) {
      _isLoggedIn = true;
    }
    if (_channel == null && !_isReconnecting) {
      connect();
    } else {
      _schedulePresenceHandshake();
    }
  }

  // Call this after successful login
  void initializeAfterLogin() {
    ensureConnected();
  }

  void _schedulePresenceHandshake() {
    _presenceRetryTimer?.cancel();
    var attempt = 0;
    void tick() {
      attempt++;
      final t = NetworkConfig.authToken;
      if (t != null && t.isNotEmpty && _channel != null) {
        try {
          _channel!.sink.add(
            jsonEncode(<String, dynamic>{'type': 'presence', 'token': t}),
          );
          debugPrint('🔌 WebSocket: presence handshake sent');
        } catch (e) {
          debugPrint('🔌 WebSocket: presence send failed: $e');
        }
        return;
      }
      if (attempt < _maxPresenceAttempts) {
        _presenceRetryTimer = Timer(
          Duration(milliseconds: 60 * attempt),
          tick,
        );
      }
    }

    _presenceRetryTimer = Timer(Duration.zero, tick);
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      final ch = _channel;
      if (ch == null) return;
      try {
        ch.sink.add(
          jsonEncode(<String, dynamic>{
            'type': 'ping',
            't': DateTime.now().millisecondsSinceEpoch,
          }),
        );
      } catch (e) {
        _handleConnectionError('Heartbeat send failed: $e');
      }
    });
  }

  void connect() {
    // #region agent log
    agentDebugNdjson(
      hypothesisId: 'H1',
      location: 'websocket_provider.dart:connect:entry',
      message: 'connect() entered',
      data: <String, Object?>{
        '_isReconnecting': _isReconnecting,
        '_reconnectAttempts': _reconnectAttempts,
        '_isLoggedIn': _isLoggedIn,
        '_suppressReconnect': _suppressReconnect,
        'hasChannel': _channel != null,
      },
    );
    // #endregion
    if (_isReconnecting) {
      // #region agent log
      agentDebugNdjson(
        hypothesisId: 'H1',
        location: 'websocket_provider.dart:connect:early_return',
        message: 'connect() aborted: _isReconnecting is true',
        data: <String, Object?>{
          '_reconnectAttempts': _reconnectAttempts,
        },
      );
      // #endregion
      return;
    }

    _stopHeartbeat();
    final previous = _channel;
    _channel = null;
    if (previous != null) {
      try {
        previous.sink.close(status.goingAway);
      } catch (_) {}
    }

    var wsUri = Uri.parse(NetworkConfig.wsUrl);
    final token = NetworkConfig.authToken;
    if (token != null && token.isNotEmpty) {
      final q = Map<String, String>.from(wsUri.queryParameters);
      q['token'] = token;
      wsUri = wsUri.replace(queryParameters: q);
    }

    final wsEndpoint =
        '${wsUri.scheme}://${wsUri.host}${wsUri.hasPort ? ':${wsUri.port}' : ''}${wsUri.path}';
    debugPrint(
      '🔌 WebSocket: connect $wsEndpoint auth=${token != null && token.isNotEmpty}',
    );

    try {
      _channel = WebSocketChannel.connect(wsUri);
      state = _channel;
      debugPrint('🔌 WebSocket: Connection initiated to $wsEndpoint');

      // Listen for messages
      _channel!.stream.listen(
        (message) {
          markWsBackendAlive();
          debugPrint('🔌 WebSocket: Received message: $message');
          // Fan-out raw messages so multiple consumers can listen safely.
          _rawMessageController.add(message);
          try {
            final data = jsonDecode(message);
            if (data is Map && data['type'] == 'force_logout') {
              final reason = data['reason']?.toString();
              debugPrint('🔌 WebSocket: force_logout — $reason');
              // #region agent log
              agentDebugNdjson(
                hypothesisId: 'H3',
                location: 'websocket_provider.dart:listen:force_logout',
                message: 'Server sent force_logout',
                data: <String, Object?>{
                  'reason': reason ?? '',
                },
              );
              // #endregion
              disconnectAfterKick();
              onAdminForceLogout?.call(reason);
              return;
            }
            if (data is Map && data['type'] == 'notification') {
              _notificationController.add(data['message'] as String? ?? '');
              return;
            }
            if (data is Map && data['type'] == 'pong') {
              _reconnectAttempts = 0;
              return;
            }
          } catch (e) {
            debugPrint('🔌 WebSocket: Failed to parse message: $e');
          }
          // Reset reconnect attempts on successful message
          _reconnectAttempts = 0;
        },
        onError: (error) {
          debugPrint('🔌 WebSocket: Error on $wsEndpoint: $error');
          // #region agent log
          agentDebugNdjson(
            hypothesisId: 'H2',
            location: 'websocket_provider.dart:listen:onError',
            message: 'stream onError',
            data: <String, Object?>{
              'error': error.toString(),
            },
          );
          // #endregion
          _handleConnectionError('WebSocket error on $wsEndpoint: $error');
        },
        onDone: () {
          debugPrint('🔌 WebSocket: Connection closed for $wsEndpoint');
          // #region agent log
          agentDebugNdjson(
            hypothesisId: 'H2',
            location: 'websocket_provider.dart:listen:onDone',
            message: 'stream onDone (remote or local close)',
            data: <String, Object?>{
              '_reconnectAttempts': _reconnectAttempts,
            },
          );
          // #endregion
          _handleConnectionClosed();
        },
      );

      _isReconnecting = false;
      debugPrint('🔌 WebSocket: Successfully connected to $wsEndpoint');
      markWsBackendAlive();
      _schedulePresenceHandshake();
      _startHeartbeat();
      return;
    } catch (e) {
      debugPrint('🔌 WebSocket: Failed to connect to $wsEndpoint: $e');
      _handleConnectionError('Failed to connect to WebSocket $wsEndpoint: $e');
    }
  }

  void _handleConnectionError(String error) {
    _stopHeartbeat();
    clearWsBackendAliveProof();
    try {
      _channel?.sink.close(status.goingAway);
    } catch (_) {}
    _channel = null;
    _isReconnecting = true;
    state = null;

    if (_suppressReconnect || !_isLoggedIn) {
      _isReconnecting = false;
      // #region agent log
      agentDebugNdjson(
        hypothesisId: 'H1',
        location: 'websocket_provider.dart:_handleConnectionError:suppress',
        message: 'error path: reconnect suppressed or not logged in',
        data: <String, Object?>{
          '_suppressReconnect': _suppressReconnect,
          '_isLoggedIn': _isLoggedIn,
          'errorSnippet': error.length > 120 ? error.substring(0, 120) : error,
        },
      );
      // #endregion
      return;
    }

    if (_reconnectAttempts < maxReconnectAttempts) {
      _reconnectAttempts++;
      _reconnectTimer?.cancel();
      // #region agent log
      agentDebugNdjson(
        hypothesisId: 'H1',
        location: 'websocket_provider.dart:_handleConnectionError:schedule',
        message: 'scheduled reconnect after error',
        data: <String, Object?>{
          '_reconnectAttempts': _reconnectAttempts,
          '_isReconnecting': _isReconnecting,
        },
      );
      // #endregion
      _reconnectTimer = Timer(reconnectDelay, () {
        // Allow connect() to run: it would otherwise no-op because
        // _handleConnectionError sets _isReconnecting true before scheduling.
        _isReconnecting = false;
        // #region agent log
        agentDebugNdjson(
          hypothesisId: 'H1',
          location: 'websocket_provider.dart:_handleConnectionError:timer_fire',
          message: 'reconnect timer fired, cleared _isReconnecting',
          runId: 'post-fix',
          data: <String, Object?>{
            '_reconnectAttempts': _reconnectAttempts,
          },
        );
        // #endregion
        connect();
      });
    } else {
      // #region agent log
      agentDebugNdjson(
        hypothesisId: 'H5',
        location: 'websocket_provider.dart:_handleConnectionError:max',
        message: 'max reconnect attempts after error',
        data: <String, Object?>{},
      );
      // #endregion
      _isReconnecting = false;
      // Max retries reached, start mock updates for development
      _startMockUpdates();
    }
  }

  void _handleConnectionClosed() {
    _stopHeartbeat();
    clearWsBackendAliveProof();
    _channel = null;
    state = null;
    if (_suppressReconnect || !_isLoggedIn) {
      // #region agent log
      agentDebugNdjson(
        hypothesisId: 'H4',
        location: 'websocket_provider.dart:_handleConnectionClosed:noop',
        message: 'onDone: no reconnect (logged out or suppress)',
        data: <String, Object?>{
          '_suppressReconnect': _suppressReconnect,
          '_isLoggedIn': _isLoggedIn,
        },
      );
      // #endregion
      return;
    }
    if (!_isReconnecting && _reconnectAttempts < maxReconnectAttempts) {
      // Attempt to reconnect if not already reconnecting
      _reconnectTimer?.cancel();
      // #region agent log
      agentDebugNdjson(
        hypothesisId: 'H2',
        location: 'websocket_provider.dart:_handleConnectionClosed:schedule',
        message: 'scheduled reconnect after onDone',
        data: <String, Object?>{
          '_reconnectAttempts': _reconnectAttempts,
          '_isReconnecting': _isReconnecting,
        },
      );
      // #endregion
      _reconnectTimer = Timer(reconnectDelay, () {
        _isReconnecting = false;
        connect();
      });
    } else {
      // #region agent log
      agentDebugNdjson(
        hypothesisId: 'H5',
        location: 'websocket_provider.dart:_handleConnectionClosed:skipped',
        message: 'onDone: reconnect skipped',
        data: <String, Object?>{
          '_isReconnecting': _isReconnecting,
          '_reconnectAttempts': _reconnectAttempts,
        },
      );
      // #endregion
    }
  }

  void _startMockUpdates() {
    // Mock real-time updates untuk development when WebSocket fails
    // Dalam production, ini akan digantikan dengan WebSocket messages
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      // Simulate order updates every 30 seconds (placeholder)
    });
  }

  void sendMessage(String message) {
    if (_channel != null) {
      try {
        _channel!.sink.add(message);
      } catch (e) {
        // Handle send error
        _handleConnectionError('Failed to send message: $e');
      }
    }
  }

  /// Tutup WebSocket setelah server memutus sesi; tidak reconnect.
  void disconnectAfterKick() {
    _stopHeartbeat();
    clearWsBackendAliveProof();
    // #region agent log
    agentDebugNdjson(
      hypothesisId: 'H3',
      location: 'websocket_provider.dart:disconnectAfterKick',
      message: 'disconnectAfterKick()',
      data: <String, Object?>{},
    );
    // #endregion
    _suppressReconnect = true;
    _isLoggedIn = false;
    _presenceRetryTimer?.cancel();
    _presenceRetryTimer = null;
    _reconnectTimer?.cancel();
    _reconnectAttempts = maxReconnectAttempts;
    try {
      _channel?.sink.close(status.goingAway);
    } catch (_) {}
    _channel = null;
    state = null;
  }

  void disconnect() {
    _stopHeartbeat();
    clearWsBackendAliveProof();
    // #region agent log
    agentDebugNdjson(
      hypothesisId: 'H4',
      location: 'websocket_provider.dart:disconnect',
      message: 'disconnect() (logout/local close)',
      data: <String, Object?>{},
    );
    // #endregion
    _suppressReconnect = false;
    _presenceRetryTimer?.cancel();
    _presenceRetryTimer = null;
    _reconnectTimer?.cancel();
    _channel?.sink.close(status.goingAway);
    _channel = null;
    state = null;
    _isLoggedIn = false;
    _reconnectAttempts = 0;
  }

  @override
  void dispose() {
    disconnect();
    _notificationController.close();
    _rawMessageController.close();
    super.dispose();
  }

  bool get isConnected => state != null;
  int get reconnectAttempts => _reconnectAttempts;
}

// Provider untuk real-time order updates
final realTimeOrderUpdatesProvider = StreamProvider<Map<String, dynamic>>((
  ref,
) {
  final webSocketChannel = ref.watch(webSocketProvider);
  final webSocketNotifier = ref.watch(webSocketProvider.notifier);

  if (webSocketChannel != null) {
    return webSocketNotifier.rawMessageStream.map((message) {
      try {
        if (message is String) {
          final data = jsonDecode(message) as Map<String, dynamic>;
          return data;
        } else if (message is Map<String, dynamic>) {
          return message;
        }
      } catch (e) {
        debugPrint('🔌 WebSocket: Message parse error: $e');
      }
      return {'type': 'unknown'};
    });
  } else {
    // Fallback untuk development - periodic mock updates
    return Stream.periodic(const Duration(seconds: 30), (count) {
      return {
        'type': 'mock_update',
        'timestamp': DateTime.now().toIso8601String(),
      };
    });
  }
});

// Provider untuk health check HTTP sebagai fallback untuk indikator Live
final healthCheckProvider = StateNotifierProvider<HealthCheckNotifier, bool>((
  ref,
) {
  return HealthCheckNotifier();
});

class HealthCheckNotifier extends StateNotifier<bool> {
  Timer? _healthCheckTimer;
  static const Duration healthCheckInterval = Duration(seconds: 60);

  HealthCheckNotifier() : super(false) {
    startHealthCheck();
  }

  void startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(
      healthCheckInterval,
      (_) => _performHealthCheck(),
    );
    // Perform initial check
    _performHealthCheck();
  }

  Future<void> _performHealthCheck() async {
    try {
      if (WebSocketNotifier.wsBackendAliveWithin(
        WebSocketNotifier.wsBackendProofTtl,
      )) {
        if (state != true) {
          state = true;
          debugPrint('🔍 Health check: Server is healthy (WebSocket)');
        }
        return;
      }

      bool isHealthy = false;
      final base = NetworkConfig.baseUrl;

      // Try /health first
      try {
        final healthUrl = base.endsWith('/') ? '${base}health' : '$base/health';
        final response = await http
            .get(Uri.parse(healthUrl))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          isHealthy = true;
        }
      } catch (e) {
        // If /health fails, try /orders?limit=1 as fallback
        final ordersUrl =
            base.endsWith('/') ? '${base}orders?limit=1' : '$base/orders?limit=1';
        final response = await http
            .get(Uri.parse(ordersUrl))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          isHealthy = true;
        }
      }

      if (!isHealthy &&
          WebSocketNotifier.wsBackendAliveWithin(
            WebSocketNotifier.wsBackendProofTtl,
          )) {
        isHealthy = true;
      }

      if (state != isHealthy) {
        state = isHealthy;
        debugPrint(
          '🔍 Health check: ${isHealthy ? 'Server is healthy' : 'Server is unhealthy'}',
        );
      }
    } catch (e) {
      final fallbackWs = WebSocketNotifier.wsBackendAliveWithin(
        WebSocketNotifier.wsBackendProofTtl,
      );
      if (fallbackWs) {
        if (state != true) {
          state = true;
          debugPrint('🔍 Health check: Server is healthy (WebSocket after HTTP error)');
        }
        return;
      }
      if (state != false) {
        state = false;
        debugPrint('🔍 Health check failed: $e');
      }
    }
  }

  void stopHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  @override
  void dispose() {
    stopHealthCheck();
    super.dispose();
  }
}
