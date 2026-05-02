import 'package:flutter/foundation.dart';

class NetworkConfig {
  static String? _authToken;

  // Local dev server (backend lokal) — **pilihan kedua**, hanya jika USE_LOCAL_API=true
  static const int _localPort = 3000;
  static const String _localHostAndroidEmulator = '10.0.2.2';
  static const String _localHostDefault = 'localhost';

  // Production server (default untuk semua mode build)
  static const String _prodHost = 'kumpulandoa.my.id';

  /// Default: **false** → `https://kumpulandoa.my.id`.
  /// Untuk backend lokal (`http://localhost:3000` / `http://10.0.2.2:3000` di emulator):
  /// `flutter run --dart-define=USE_LOCAL_API=true`
  static bool get _useLocal =>
      const bool.fromEnvironment('USE_LOCAL_API', defaultValue: false);

  // Timeout configurations for different platforms
  static Duration get connectionTimeout {
    return Duration(seconds: 30);
  }

  static const Duration receiveTimeout = Duration(seconds: 30);

  static String get _host {
    const overrideHost = String.fromEnvironment('API_HOST', defaultValue: '');
    if (overrideHost.isNotEmpty) return overrideHost;
    if (!_useLocal) return _prodHost;
    // Android emulator cannot reach host machine via "localhost".
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _localHostAndroidEmulator;
    }
    return _localHostDefault;
  }

  static int? get _port {
    const overridePortStr = String.fromEnvironment(
      'API_PORT',
      defaultValue: '',
    );
    final overridePort = int.tryParse(overridePortStr);
    if (overridePort != null) return overridePort;
    if (!_useLocal) return null; // prod assumes default 443/https
    return _localPort;
  }

  static String _httpScheme() {
    if (kIsWeb) return Uri.base.scheme == 'https' ? 'https' : 'http';
    const overrideScheme = String.fromEnvironment(
      'API_SCHEME',
      defaultValue: '',
    );
    if (overrideScheme == 'http' || overrideScheme == 'https') {
      return overrideScheme;
    }
    return _useLocal ? 'http' : 'https';
  }

  static String _wsScheme() {
    final httpScheme = _httpScheme();
    return httpScheme == 'https' ? 'wss' : 'ws';
  }

  static String get baseUrl {
    final scheme = _httpScheme();
    final port = _port;
    return port == null ? '$scheme://$_host' : '$scheme://$_host:$port';
  }

  static String get wsUrl {
    final scheme = _wsScheme();
    final port = _port;
    return port == null ? '$scheme://$_host' : '$scheme://$_host:$port';
  }

  /// True jika app memakai backend lokal (bukan sekadar debug build).
  static bool get isDevelopment => _useLocal;

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
