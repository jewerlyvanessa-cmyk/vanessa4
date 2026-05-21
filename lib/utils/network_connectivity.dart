import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class NetworkConnectivity {
  /// Satu probe HTTP pada satu waktu — hindari tabrakan timer (network + health).
  static Future<bool>? _backendReachableInFlight;

  // Cek apakah device online (dengan ping ke backend)
  static Future<bool> isOnline() async {
    // Web: browser blocks cross-origin "ping" to arbitrary hosts (CORS),
    // so treat "online" as true and rely on backend reachability checks.
    if (kIsWeb) return true;
    try {
      // Ping ke Google untuk memastikan koneksi internet (non-web only).
      // Use a lightweight endpoint commonly returning 204.
      // Jangan kirim header non-simple (mis. Cache-Control) — di web memicu
      // preflight CORS yang ditolak browser meski server hidup.
      final response = await http
          .get(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      debugPrint('Connectivity check failed: $e');
      return false;
    }
  }

  // Cek apakah backend dapat diakses
  static Future<bool> isBackendReachable(String baseUrl) {
    return _backendReachableInFlight ??= _probeBackendReachable(baseUrl)
        .whenComplete(() => _backendReachableInFlight = null);
  }

  static Future<bool> _probeBackendReachable(String baseUrl) async {
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    // Timeout lebih longgar: jaringan lemot / server sibuk sering gagal di 5–10s
    // padahal WebSocket masih hidup.
    const liveTimeout = Duration(seconds: 15);
    const healthTimeout = Duration(seconds: 20);

    // 1) /health/live — tidak menyentuh DB; cegah timeout palsu saat Postgres belum siap.
    try {
      final liveUrl = '$root/health/live';
      final live = await http
          .get(Uri.parse(liveUrl))
          .timeout(liveTimeout);
      if (live.statusCode == 200) return true;
    } catch (e) {
      debugPrint('Backend /health/live: $e');
    }

    // 2) /health — termasuk cek database
    try {
      final healthUrl = '$root/health';
      final response = await http
          .get(Uri.parse(healthUrl))
          .timeout(healthTimeout);

      return response.statusCode == 200;
    } catch (e) {
      // Try base URL as fallback
      try {
        final response = await http
            .get(Uri.parse(baseUrl))
            .timeout(healthTimeout);

        return response.statusCode >= 200 && response.statusCode < 400;
      } catch (e2) {
        debugPrint('Backend unreachable: $e2');
        return false;
      }
    }
  }

  // Test network latency to backend
  static Future<Duration?> getNetworkLatency(String baseUrl) async {
    try {
      final startTime = DateTime.now();
      final response = await http
          .get(Uri.parse(baseUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 400) {
        final endTime = DateTime.now();
        return endTime.difference(startTime);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Get network status message
  static Future<String> getNetworkStatus(String baseUrl) async {
    final isOnline = await NetworkConnectivity.isOnline();
    if (!isOnline) {
      return 'No internet connection';
    }

    final isBackendReachable = await NetworkConnectivity.isBackendReachable(
      baseUrl,
    );
    if (!isBackendReachable) {
      return 'Backend server unreachable';
    }

    final latency = await NetworkConnectivity.getNetworkLatency(baseUrl);
    if (latency != null) {
      if (latency.inMilliseconds < 100) {
        return 'Excellent connection (${latency.inMilliseconds}ms)';
      } else if (latency.inMilliseconds < 500) {
        return 'Good connection (${latency.inMilliseconds}ms)';
      } else if (latency.inMilliseconds < 1000) {
        return 'Slow connection (${latency.inMilliseconds}ms)';
      } else {
        return 'Poor connection (${latency.inMilliseconds}ms)';
      }
    }

    return 'Connected';
  }

  // Test manual connectivity to backend
  static Future<Map<String, dynamic>> testBackendConnection(
    String baseUrl,
  ) async {
    final result = <String, dynamic>{
      'isOnline': false,
      'isBackendReachable': false,
      'latency': null,
      'error': null,
    };

    try {
      result['isOnline'] = await isOnline();

      if (result['isOnline']) {
        result['isBackendReachable'] = await isBackendReachable(baseUrl);
        if (result['isBackendReachable']) {
          result['latency'] = await getNetworkLatency(baseUrl);
        }
      }
    } catch (e) {
      result['error'] = e.toString();
    }

    return result;
  }

  // Get detailed network status
  static Future<String> getDetailedNetworkStatus(String baseUrl) async {
    final testResult = await testBackendConnection(baseUrl);

    if (!testResult['isOnline']) {
      return 'No internet connection';
    }

    if (!testResult['isBackendReachable']) {
      return 'Backend server unreachable at $baseUrl';
    }

    final latency = testResult['latency'] as Duration?;
    if (latency != null) {
      return 'Connected to $baseUrl (${latency.inMilliseconds}ms latency)';
    }

    return 'Connected to $baseUrl';
  }
}
