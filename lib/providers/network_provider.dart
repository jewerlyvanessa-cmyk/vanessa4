import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/network_config.dart';
import '../utils/network_connectivity.dart';

// Network status state
class NetworkState {
  final bool isOnline;
  final bool isBackendReachable;
  final String statusMessage;
  final Duration? latency;

  const NetworkState({
    required this.isOnline,
    required this.isBackendReachable,
    required this.statusMessage,
    this.latency,
  });

  NetworkState copyWith({
    bool? isOnline,
    bool? isBackendReachable,
    String? statusMessage,
    Duration? latency,
  }) {
    return NetworkState(
      isOnline: isOnline ?? this.isOnline,
      isBackendReachable: isBackendReachable ?? this.isBackendReachable,
      statusMessage: statusMessage ?? this.statusMessage,
      latency: latency ?? this.latency,
    );
  }
}

// Network status notifier
class NetworkStatusNotifier extends StateNotifier<NetworkState> {
  Timer? _statusCheckTimer;
  static const Duration checkInterval = Duration(seconds: 30);

  NetworkStatusNotifier()
      : super(const NetworkState(
          isOnline: true,
          isBackendReachable: true,
          statusMessage: 'Checking connection...',
        )) {
    _startPeriodicChecks();
  }

  void _startPeriodicChecks() {
    // Initial check
    checkNetworkStatus();

    // Periodic checks
    _statusCheckTimer = Timer.periodic(checkInterval, (_) {
      checkNetworkStatus();
    });
  }

  Future<void> checkNetworkStatus() async {
    try {
      final isOnline = await NetworkConnectivity.isOnline();
      final isBackendReachable = isOnline
          ? await NetworkConnectivity.isBackendReachable(NetworkConfig.baseUrl)
          : false;

      final latency = isBackendReachable
          ? await NetworkConnectivity.getNetworkLatency(NetworkConfig.baseUrl)
          : null;

      String statusMessage;
      if (!isOnline) {
        statusMessage = 'Offline - No internet connection';
      } else if (!isBackendReachable) {
        statusMessage = 'Backend server unreachable';
      } else if (latency != null) {
        if (latency.inMilliseconds < 100) {
          statusMessage = 'Excellent connection (${latency.inMilliseconds}ms)';
        } else if (latency.inMilliseconds < 500) {
          statusMessage = 'Good connection (${latency.inMilliseconds}ms)';
        } else if (latency.inMilliseconds < 1000) {
          statusMessage = 'Slow connection (${latency.inMilliseconds}ms)';
        } else {
          statusMessage = 'Poor connection (${latency.inMilliseconds}ms)';
        }
      } else {
        statusMessage = 'Connected';
      }

      state = NetworkState(
        isOnline: isOnline,
        isBackendReachable: isBackendReachable,
        statusMessage: statusMessage,
        latency: latency,
      );
    } catch (e) {
      state = const NetworkState(
        isOnline: false,
        isBackendReachable: false,
        statusMessage: 'Connection check failed',
      );
    }
  }

  // Manual refresh
  Future<void> refresh() async {
    await checkNetworkStatus();
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    super.dispose();
  }
}

// Network status provider
final networkStatusProvider = StateNotifierProvider<NetworkStatusNotifier, NetworkState>((ref) {
  return NetworkStatusNotifier();
});

// Convenience providers
final isOnlineProvider = Provider<bool>((ref) {
  return ref.watch(networkStatusProvider).isOnline;
});

final isBackendReachableProvider = Provider<bool>((ref) {
  return ref.watch(networkStatusProvider).isBackendReachable;
});

final networkStatusMessageProvider = Provider<String>((ref) {
  return ref.watch(networkStatusProvider).statusMessage;
});
