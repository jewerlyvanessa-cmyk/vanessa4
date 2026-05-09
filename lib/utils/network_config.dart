import 'package:flutter/foundation.dart';

class NetworkConfig {
  static String? _authToken;

  /// Di web (dart2js / DDC), [String.fromEnvironment] hanya valid sebagai **const**.
  /// Jangan panggil dari getter biasa — akan crash sebelum UI tampil.
  static const String _apiHostRaw = String.fromEnvironment(
    'API_HOST',
    defaultValue: '',
  );

  // Local dev server (backend lokal) — **pilihan kedua**, hanya jika USE_LOCAL_API=true
  static const int _localPort = 3000;
  static const String _localHostAndroidEmulator = '10.0.2.2';
  static const String _localHostDefault = 'localhost';

  // Production server (default untuk semua mode build)
  static const String _prodHost = 'kumpulandoa.my.id';

  // Default: **false** → `https://kumpulandoa.my.id`.
  /// Untuk backend lokal (`http://localhost:3000` / `http://10.0.2.2:3000` di emulator):
  /// `flutter run --dart-define=USE_LOCAL_API=true`
  static bool get _useLocal =>
      const bool.fromEnvironment('USE_LOCAL_API', defaultValue: false);

  /// `API_PORT` / `API_SCHEME` hanya dipakai jika backend target jelas (host override
  /// atau `USE_LOCAL_API`). Tanpa ini, `API_PORT=3000` saja membuat URL seperti
  /// `http://kumpulandoa.my.id:3000` yang tidak ada — timeout & login gagal.
  static bool get _apiOverridesApply {
    if (_useLocal) return true;
    return _apiHostRaw.trim().isNotEmpty;
  }

  // Timeout configurations for different platforms
  static Duration get connectionTimeout {
    return Duration(seconds: 30);
  }

  static const Duration receiveTimeout = Duration(seconds: 30);

  static String get _host {
    var overrideHost = _apiHostRaw.trim();
    if (overrideHost.isNotEmpty) {
      // Emulator Android: 127.0.0.1 / localhost = loopback di dalam VM, bukan PC dev.
      // Pakai alias host → 10.0.2.2:3000. (HP fisik: set API_HOST=IP_LAN_PC, mis. 192.168.1.10)
      if (defaultTargetPlatform == TargetPlatform.android &&
          (overrideHost == '127.0.0.1' || overrideHost == 'localhost')) {
        overrideHost = _localHostAndroidEmulator;
      }
      return overrideHost;
    }
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
    if (overridePort != null && _apiOverridesApply) return overridePort;
    if (!_useLocal) return null; // prod assumes default 443/https
    return _localPort;
  }

  static String _httpScheme() {
    // Web:
    // - For production host (default), always prefer HTTPS even when the app is
    //   served from http://localhost during dev (`flutter run -d chrome`).
    //   Using http:// in that case often fails (redirect/CORS/mixed rules) and
    //   manifests as "ClientException: Failed to fetch".
    // - For local backend (`USE_LOCAL_API=true`) keep following the page scheme.
    if (kIsWeb) {
      if (!_useLocal && _apiHostRaw.trim().isEmpty) return 'https';
      return Uri.base.scheme == 'https' ? 'https' : 'http';
    }
    const overrideScheme = String.fromEnvironment(
      'API_SCHEME',
      defaultValue: '',
    );
    if (_apiOverridesApply &&
        (overrideScheme == 'http' || overrideScheme == 'https')) {
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

  /// Dipanggil dari ApiClient pada HTTP 401 setelah token dihapus.
  /// Di-set dari root app agar state sesi pengguna ikut di-logout.
  static void Function()? onUnauthorized;

  static void notifyUnauthorized() {
    try {
      onUnauthorized?.call();
    } catch (_) {
      // Jangan biarkan callback mengganggu penanganan error HTTP.
    }
  }

  static String? get authToken => _authToken;

  static Map<String, String> get defaultHeaders => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (_authToken != null && _authToken!.isNotEmpty)
      'Authorization': 'Bearer $_authToken',
  };
}
