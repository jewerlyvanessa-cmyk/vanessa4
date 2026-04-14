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

class WebSocketNotifier extends StateNotifier<WebSocketChannel?> {
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  static const Duration reconnectDelay = Duration(seconds: 3);
  bool _isLoggedIn = false;
  final StreamController<String> _notificationController =
      StreamController<String>.broadcast();

  Stream<String> get notificationStream => _notificationController.stream;

  WebSocketNotifier() : super(null) {
    // Don't connect immediately - wait for login
  }

  // Call this after successful login
  void initializeAfterLogin() {
    if (!_isLoggedIn) {
      _isLoggedIn = true;
      connect();
    }
  }

  void connect() {
    if (_isReconnecting) return;

    final wsUrlsToTry = [
      NetworkConfig.wsUrl,
      ...NetworkConfig.getAlternativeWsUrls(),
    ];

    debugPrint(
      '🔌 WebSocket: Attempting to connect. URLs to try: $wsUrlsToTry',
    );

    for (final wsUrl in wsUrlsToTry) {
      try {
        debugPrint('🔌 WebSocket: Trying to connect to $wsUrl');
        _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
        state = _channel;
        debugPrint('🔌 WebSocket: Connection initiated to $wsUrl');

        // Listen for messages
        _channel!.stream.listen(
          (message) {
            debugPrint('🔌 WebSocket: Received message: $message');
            try {
              final data = jsonDecode(message);
              if (data['type'] == 'notification') {
                _notificationController.add(data['message']);
              }
            } catch (e) {
              debugPrint('🔌 WebSocket: Failed to parse message: $e');
            }
            // Handle incoming messages
            // Parse message and update providers accordingly
            _reconnectAttempts =
                0; // Reset reconnect attempts on successful message
          },
          onError: (error) {
            debugPrint('🔌 WebSocket: Error on $wsUrl: $error');
            _handleConnectionError('WebSocket error on $wsUrl: $error');
          },
          onDone: () {
            debugPrint('🔌 WebSocket: Connection closed for $wsUrl');
            _handleConnectionClosed();
          },
        );

        _isReconnecting = false;
        debugPrint('🔌 WebSocket: Successfully connected to $wsUrl');
        // Successfully connected, break out of loop
        return;
      } catch (e) {
        debugPrint('🔌 WebSocket: Failed to connect to $wsUrl: $e');
        _handleConnectionError('Failed to connect to WebSocket $wsUrl: $e');
        // Continue to next URL
      }
    }

    // If all URLs failed
    debugPrint('🔌 WebSocket: All URLs failed');
    _handleConnectionError('Failed to connect to any WebSocket URL');
  }

  void _handleConnectionError(String error) {
    _isReconnecting = true;
    state = null;

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
      // Simulate order updates every 30 seconds
      if (mounted) {
        // Mock update logic here
      }
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

  void disconnect() {
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

  if (webSocketChannel != null) {
    return webSocketChannel.stream.map((message) {
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
      final urlsToTry = [
        NetworkConfig.baseUrl,
        ...NetworkConfig.getAlternativeBaseUrls(),
      ];

      for (final base in urlsToTry) {
        // Try /health first
        try {
          final healthUrl = base.endsWith('/')
              ? '${base}health'
              : '$base/health';
          final response = await http
              .get(Uri.parse(healthUrl))
              .timeout(const Duration(seconds: 10));
          if (response.statusCode == 200) {
            isHealthy = true;
            break;
          }
        } catch (e) {
          // If /health fails, try /orders?limit=1 as fallback
          try {
            final ordersUrl = base.endsWith('/')
                ? '${base}orders?limit=1'
                : '$base/orders?limit=1';
            final response = await http
                .get(Uri.parse(ordersUrl))
                .timeout(const Duration(seconds: 10));
            if (response.statusCode == 200) {
              isHealthy = true;
              break;
            }
          } catch (e2) {
            // try next base URL
            continue;
          }
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
