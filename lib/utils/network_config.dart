import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

class NetworkConfig {
  // Set this to true when developing with physical device wirelessly (no USB cable)
  // Set this to false when developing with emulator/simulator or USB-connected devices
  static bool useLocalNetwork =
      false; // Changed to false to use localhost with ADB port forwarding
  static String? _authToken;

  // Timeout configurations for different platforms
  static Duration get connectionTimeout {
    if (Platform.isAndroid) {
      return Duration(seconds: 15); // Shorter timeout for Android devices
    }
    return Duration(seconds: 30);
  }

  static const Duration receiveTimeout = Duration(seconds: 30);

  // Alternative IP addresses to try for different platforms
  static const List<String> _alternativeIPs = [
    '10.0.2.2', // Android emulator host loopback
    '127.0.0.1', // Localhost (useful with ADB reverse on physical device)
    'localhost', // Localhost hostname
    '192.168.1.101', // Local network IP (host machine)
    '172.20.10.1', // Common iOS hotspot IP
    '103.184.181.79', // online server
  ];

  /// Get alternative base URLs for fallback connectivity
  static List<String> getAlternativeBaseUrls() {
    return _alternativeIPs.map((ip) => 'http://$ip:3000').toList();
  }

  /// Get alternative WebSocket URLs for fallback connectivity
  static List<String> getAlternativeWsUrls() {
    return _alternativeIPs.map((ip) => 'ws://$ip:3000').toList();
  }

  static String get baseUrl {
    if (kIsWeb) {
      // For web, use the current host to avoid CORS issues
      return 'http://${Uri.base.host}:3000';
    } else if (Platform.isAndroid) {
      // Android:
      // - Emulator: use host loopback via 10.0.2.2 -> http://10.0.2.2:3000
      // - Physical device via USB: use ADB reverse -> http://127.0.0.1:3000
      // - WiFi/LAN: set useLocalNetwork=true and configure host LAN IP below
      if (!useLocalNetwork) {
        // Default to emulator-friendly host mapping.
        return 'http://10.0.2.2:3000';
      }
      // When developing over WiFi/LAN, point to the machine running backend
      // (replace with your host IP if needed).
      return 'http://192.168.1.101:3000';
    } else if (Platform.isIOS) {
      // For iOS, try localhost first
      return 'http://localhost:3000'; // iOS simulator
      // Fallbacks handled by getAlternativeBaseUrls()
    } else {
      // For macOS desktop and other platforms
      return useLocalNetwork
          ? 'http://103.184.181.79:3000' // online server
          : 'http://127.0.0.1:3000'; // Use 127.0.0.1 to avoid proxy issues
    }
  }

  static String get wsUrl {
    if (kIsWeb) {
      // For web, use the current host for WebSocket
      final scheme = Uri.base.scheme == 'https' ? 'wss' : 'ws';
      return '$scheme://${Uri.base.host}:3000';
    } else if (Platform.isAndroid) {
      if (!useLocalNetwork) {
        return 'ws://10.0.2.2:3000';
      }
      return 'ws://192.168.1.101:3000';
    } else if (Platform.isIOS) {
      // For iOS, try localhost first
      return 'ws://localhost:3000'; // iOS simulator
      // Fallbacks handled by getAlternativeWsUrls()
    } else {
      // For macOS desktop and other platforms
      return 'ws://127.0.0.1:3000'; // Use 127.0.0.1 to avoid proxy issues
    }
  }

  // Helper method to switch between emulator and wireless device modes
  static void setWirelessMode(bool wireless) {
    useLocalNetwork = wireless;
  }

  // Check if we're running in development mode
  static bool get isDevelopment => kDebugMode;

  // Storage service URL (separate service for file uploads)
  static String get storageUrl {
    if (kIsWeb) {
      // For web, use the current host to avoid CORS issues
      return 'http://${Uri.base.host}:4000';
    } else if (Platform.isAndroid) {
      if (!useLocalNetwork) {
        // Emulator-friendly host mapping.
        return 'http://10.0.2.2:4000';
      }
      // WiFi/LAN mode: point to machine running storage service (update if needed)
      return 'http://192.168.1.101:4000';
    } else if (Platform.isIOS) {
      // For iOS, try localhost first
      return 'http://localhost:4000'; // iOS simulator
    } else {
      // For macOS desktop and other platforms
      return useLocalNetwork
          ? 'http://103.184.181.79:4000' // online server
          : 'http://localhost:4000';
    }
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
