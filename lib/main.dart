import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:io' show Platform;
import 'core/state/user_state.dart' as core_state;
import 'core/theme/app_theme.dart';
import 'routes/app_routes.dart';
import 'providers/customer_provider.dart';
import 'providers/network_provider.dart';
import 'utils/network_config.dart';
import 'utils/network_connectivity.dart';

final userStateProvider =
    StateNotifierProvider<core_state.UserStateNotifier, core_state.UserState>((
      ref,
    ) {
      return core_state.UserStateNotifier();
    });

final customerProvider = StateNotifierProvider<CustomerNotifier, CustomerState>(
  (ref) {
    return CustomerNotifier(NetworkConfig.baseUrl);
  },
);

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize date formatting for Indonesian locale
  await initializeDateFormatting('id_ID', null);

  // Configure network mode for development
  // Set to true for wireless development (no USB cable) - physical devices
  // Set to false for USB development (ADB reverse) - emulators/simulators
  // Auto-detect: use local network for physical devices, emulator mode for emulators
  NetworkConfig.useLocalNetwork = false; // Default to USB mode for development
  // Override for Android emulators (detected by checking if running on Android but not physical device)
  if (Platform.isAndroid) {
    // For Android emulator with ADB port forwarding, use localhost
    // Port forwarding allows emulator to access host's localhost:3000
    NetworkConfig.useLocalNetwork =
        false; // Use localhost with ADB port forwarding for Android emulator
  }

  // Debug: Print network configuration
  debugPrint('Network Config - Base URL: ${NetworkConfig.baseUrl}');
  debugPrint('Network Config - WebSocket URL: ${NetworkConfig.wsUrl}');
  debugPrint(
    'Network Config - Use Local Network: ${NetworkConfig.useLocalNetwork}',
  );

  runApp(ProviderScope(child: const VanessaApp()));
}

class VanessaApp extends ConsumerWidget {
  const VanessaApp({super.key});

  String _getMainModuleRoute(String role) {
    switch (role) {
      case 'cs':
        return AppRoutes.cs;
      case 'kasir':
        return AppRoutes.kasir;
      case 'superadmin':
        return AppRoutes.superadmin;
      case 'admin_toko':
        return AppRoutes.adminToko;
      case 'admin_workshop':
        return AppRoutes.adminWorkshop;
      case 'tukang':
        return AppRoutes.tukang;
      case 'manajer':
        return AppRoutes.manajer;
      default:
        return AppRoutes.dashboard;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Check user state for auto-login
    final userState = ref.watch(userStateProvider);
    NetworkConfig.setAuthToken(
      userState.authToken.isEmpty ? null : userState.authToken,
    );

    // Determine initial route based on user state
    final initialRoute = (userState.userId != null && userState.role.isNotEmpty)
        ? _getMainModuleRoute(userState.role)
        : AppRoutes.login;

    // Watch network status for global awareness
    final networkState = ref.watch(networkStatusProvider);

    return MaterialApp(
      title: 'Vanessa App',
      theme: AppTheme.lightTheme,
      initialRoute: initialRoute,
      routes: AppRoutes.routes,
      builder: (context, child) {
        // Add network status indicator overlay
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            if (!networkState.isOnline || !networkState.isBackendReachable)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () async {
                    // Manual refresh when tapped
                    final networkNotifier = ref.read(
                      networkStatusProvider.notifier,
                    );
                    await networkNotifier.refresh();

                    // Show snackbar with current status
                    final statusMessage =
                        await NetworkConnectivity.getDetailedNetworkStatus(
                          NetworkConfig.baseUrl,
                        );
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(statusMessage),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    });
                  },
                  child: Container(
                    color: !networkState.isOnline ? Colors.red : Colors.orange,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            !networkState.isOnline
                                ? 'Offline - Tap to retry'
                                : 'Backend Unreachable - Tap to retry',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.refresh,
                          color: Colors.white,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
