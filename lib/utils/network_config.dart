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
    '127.0.0.1', // Localhost IP (try this first to avoid proxy issues)
    'localhost', // Localhost
    '10.0.2.2', // Android emulator default
    '192.168.1.101', // Local network IP (host machine)
    '172.20.10.1', // Common iOS hotspot IP
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
      // For Android emulator, always use 10.0.2.2 to reach host machine
      return 'http://10.0.2.2:3000';
    } else if (Platform.isIOS) {
      // For iOS, try localhost first
      return 'http://localhost:3000'; // iOS simulator
      // Fallbacks handled by getAlternativeBaseUrls()
    } else {
      // For macOS desktop and other platforms
      return 'http://127.0.0.1:3000'; // Use 127.0.0.1 to avoid proxy issues
    }
  }

  static String get wsUrl {
    if (kIsWeb) {
      // For web, use the current host for WebSocket
      final scheme = Uri.base.scheme == 'https' ? 'wss' : 'ws';
      return '$scheme://${Uri.base.host}:3000';
    } else if (Platform.isAndroid) {
      // For Android emulator, always use 10.0.2.2 to reach host machine
      return 'ws://10.0.2.2:3000';
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
      if (useLocalNetwork) {
        // When useLocalNetwork is true, use 10.0.2.2 for Android emulator
        return 'http://10.0.2.2:4000';
      } else {
        // For Android emulator with ADB port forwarding
        return 'http://localhost:4000'; // Use localhost with port forwarding
      }
    } else if (Platform.isIOS) {
      // For iOS, try localhost first
      return 'http://localhost:4000'; // iOS simulator
    } else {
      // For macOS desktop and other platforms
      return 'http://localhost:4000';
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
