import 'package:flutter/foundation.dart';

class NetworkConfig {
  static String? _authToken;

  // Timeout configurations for different platforms
  static Duration get connectionTimeout {
    return Duration(seconds: 30);
  }

  static const Duration receiveTimeout = Duration(seconds: 30);

  static const String host = 'kumpulandoa.my.id';
  static const int port = 4000;

  static String _httpScheme() {
    if (kIsWeb) return Uri.base.scheme == 'https' ? 'https' : 'http';
    return 'https';
  }

  static String _wsScheme() {
    final httpScheme = _httpScheme();
    return httpScheme == 'https' ? 'wss' : 'ws';
  }

  static String get baseUrl {
    final scheme = _httpScheme();
    //return '$scheme://$host:$port';
    return '$scheme://$host';
  }

  static String get wsUrl {
    final scheme = _wsScheme();
    //return '$scheme://$host:$port';
    return '$scheme://$host';
  }

  // Check if we're running in development mode
  static bool get isDevelopment => kDebugMode;

  // Storage service URL (separate service for file uploads)
  static String get storageUrl {
    return baseUrl;
  }

  // Get appropriate headers for cross-platform requests
  static void setAuthToken(String? token) {
    _authToken = token;
  }

  static String? get authToken => _authToken;

  static Map<String, String> get defaultHeaders => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (_authToken != null && _authToken!.isNotEmpty)
      'Authorization': 'Bearer $_authToken',
  };
}
