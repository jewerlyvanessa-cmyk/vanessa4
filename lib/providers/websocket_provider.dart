import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:vanessa3/utils/network_config.dart';
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
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  static const Duration reconnectDelay = Duration(seconds: 3);
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

  void connect() {
    if (_isReconnecting) return;

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
          debugPrint('🔌 WebSocket: Received message: $message');
          // Fan-out raw messages so multiple consumers can listen safely.
          _rawMessageController.add(message);
          try {
            final data = jsonDecode(message);
            if (data is Map && data['type'] == 'force_logout') {
              final reason = data['reason']?.toString();
              debugPrint('🔌 WebSocket: force_logout — $reason');
              disconnectAfterKick();
              onAdminForceLogout?.call(reason);
              return;
            }
            if (data is Map && data['type'] == 'notification') {
              _notificationController.add(data['message'] as String? ?? '');
            }
          } catch (e) {
            debugPrint('🔌 WebSocket: Failed to parse message: $e');
          }
          // Reset reconnect attempts on successful message
          _reconnectAttempts = 0;
        },
        onError: (error) {
          debugPrint('🔌 WebSocket: Error on $wsEndpoint: $error');
          _handleConnectionError('WebSocket error on $wsEndpoint: $error');
        },
        onDone: () {
          debugPrint('🔌 WebSocket: Connection closed for $wsEndpoint');
          _handleConnectionClosed();
        },
      );

      _isReconnecting = false;
      debugPrint('🔌 WebSocket: Successfully connected to $wsEndpoint');
      _schedulePresenceHandshake();
      return;
    } catch (e) {
      debugPrint('🔌 WebSocket: Failed to connect to $wsEndpoint: $e');
      _handleConnectionError('Failed to connect to WebSocket $wsEndpoint: $e');
    }
  }

  void _handleConnectionError(String error) {
    _isReconnecting = true;
    state = null;

    if (_suppressReconnect || !_isLoggedIn) {
      _isReconnecting = false;
      return;
    }

    if (_reconnectAttempts < maxReconnectAttempts) {
      _reconnectAttempts++;
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(reconnectDelay, () {
        connect();
      });
    } else {
      // Max retries reached, start mock updates for development
      _startMockUpdates();
    }
  }

  void _handleConnectionClosed() {
    state = null;
    if (_suppressReconnect || !_isLoggedIn) {
      return;
    }
    if (!_isReconnecting && _reconnectAttempts < maxReconnectAttempts) {
      // Attempt to reconnect if not already reconnecting
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(reconnectDelay, () {
        connect();
      });
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
  static const Duration healthCheckInterval = Duration(seconds: 30);

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

      if (state != isHealthy) {
        state = isHealthy;
        debugPrint(
          '🔍 Health check: ${isHealthy ? 'Server is healthy' : 'Server is unhealthy'}',
        );
      }
    } catch (e) {
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
