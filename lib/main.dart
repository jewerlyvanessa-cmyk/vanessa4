import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/state/user_state.dart';
import 'core/theme/app_theme.dart';
import 'routes/app_routes.dart';
import 'providers/network_provider.dart';
import 'providers/offline_queue_provider.dart';
import 'providers/user_state_provider.dart';
import 'utils/auth_session_end.dart';
import 'utils/network_config.dart';
import 'utils/network_connectivity.dart';
import 'utils/responsive_layout.dart';
import 'providers/websocket_provider.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize date formatting for Indonesian locale
  await initializeDateFormatting('id_ID', null);

  // Debug: Print network configuration (dart-define harus dari `flutter run`, bukan hot restart saja)
  if (kDebugMode) {
    debugPrint(
      'Network Config - USE_LOCAL_API=${const bool.fromEnvironment('USE_LOCAL_API', defaultValue: false)} '
      'API_HOST="${const String.fromEnvironment('API_HOST', defaultValue: '')}" '
      'API_PORT="${const String.fromEnvironment('API_PORT', defaultValue: '')}" '
      'API_SCHEME="${const String.fromEnvironment('API_SCHEME', defaultValue: '')}"',
    );
  }
  debugPrint('Network Config - Base URL: ${NetworkConfig.baseUrl}');
  debugPrint('Network Config - WebSocket URL: ${NetworkConfig.wsUrl}');

  runApp(ProviderScope(child: const VanessaApp()));
}

class VanessaApp extends ConsumerStatefulWidget {
  const VanessaApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  ConsumerState<VanessaApp> createState() => _VanessaAppState();
}

class _VanessaAppState extends ConsumerState<VanessaApp> {
  @override
  void initState() {
    super.initState();
    ref.read(offlineQueueCountProvider.notifier).refresh();
    WebSocketNotifier.onAdminForceLogout = _onAdminForceLogout;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      NetworkConfig.onUnauthorized = _onSessionEndedUnauthorized;
    });
  }

  @override
  void dispose() {
    NetworkConfig.onUnauthorized = null;
    WebSocketNotifier.onAdminForceLogout = null;
    super.dispose();
  }

  void _onSessionEndedUnauthorized() {
    _endSessionAndRedirectToLogin(
      message: 'Sesi telah berakhir. Silakan login kembali.',
    );
  }

  void _onAdminForceLogout(String? reason) {
    _endSessionAndRedirectToLogin(
      message: (reason != null && reason.trim().isNotEmpty)
          ? reason.trim()
          : 'Anda dilogoutkan oleh administrator.',
    );
  }

  void _endSessionAndRedirectToLogin({String? message}) {
    ref.read(webSocketProvider.notifier).disconnect();
    ref.read(userStateProvider.notifier).logout();
    navigateToLoginClearingStack(VanessaApp.navigatorKey, message: message);
  }

  @override
  Widget build(BuildContext context) {
    // Check user state for auto-login
    final userState = ref.watch(userStateProvider);
    NetworkConfig.setAuthToken(
      userState.authToken.isEmpty ? null : userState.authToken,
    );

    // Watch network status for global awareness
    final networkState = ref.watch(networkStatusProvider);

    return MaterialApp(
      navigatorKey: VanessaApp.navigatorKey,
      title: 'Vanessa',
      scrollBehavior: const VanessaScrollBehavior(),
      theme: AppTheme.lightTheme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('id', 'ID'),
        Locale('en', 'US'),
      ],
      locale: const Locale('id', 'ID'),
      // Web: hash di URL (#/dashboard) tidak boleh melewati gate login.
      initialRoute: '/',
      routes: <String, WidgetBuilder>{
        '/': (context) => const _AppHomeGate(),
        ...AppRoutes.routes,
      },
      onGenerateRoute: AppRoutes.onGenerateRoute,
      builder: (context, child) {
        final mq = ResponsiveLayout.clampMediaQuery(MediaQuery.of(context));
        Widget navigatorChild = MediaQuery(
          data: mq,
          child: child ?? const SizedBox.shrink(),
        );
        navigatorChild = ResponsiveLayout.webMobileChrome(navigatorChild);

        // Status koneksi: di dalam alur layout (bukan Stack di atas), agar AppBar/web
        // tidak tertutup banner merah/oranye.
        final showConnectionBanner =
            !networkState.isOnline || !networkState.isBackendReachable;

        if (!showConnectionBanner) return navigatorChild;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: !networkState.isOnline ? Colors.red : Colors.orange,
              child: InkWell(
                onTap: () async {
                  final networkNotifier = ref.read(
                    networkStatusProvider.notifier,
                  );
                  await networkNotifier.refresh();

                  final statusMessage =
                      await NetworkConnectivity.getDetailedNetworkStatus(
                        NetworkConfig.baseUrl,
                      );
                  if (!context.mounted) return;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(statusMessage),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          !networkState.isOnline
                              ? 'Offline - Tap to retry'
                              : 'Backend Unreachable - Tap to retry',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                              ) ??
                              const TextStyle(color: Colors.white),
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
            Expanded(child: navigatorChild),
          ],
        );
      },
    );
  }
}


class _AppHomeGate extends ConsumerStatefulWidget {
  const _AppHomeGate();

  @override
  ConsumerState<_AppHomeGate> createState() => _AppHomeGateState();
}

class _AppHomeGateState extends ConsumerState<_AppHomeGate> {
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    ref.read(userStateProvider.notifier).ensureLoaded().then((_) {
      if (mounted) setState(() => _hydrated = true);
    });
  }

  bool _hasValidSession(UserState userState) {
    return userState.userId != null &&
        userState.role.trim().isNotEmpty &&
        userState.authToken.trim().isNotEmpty;
  }

  String _homeRouteForRole(String role) {
    return switch (role.trim().toLowerCase()) {
      'cs' => AppRoutes.cs,
      'kasir' => AppRoutes.kasir,
      'superadmin' => AppRoutes.superadmin,
      'admin_toko' => AppRoutes.adminToko,
      'admin_workshop' => AppRoutes.adminWorkshop,
      'admin_warehouse' => AppRoutes.adminWarehouse,
      'tukang' => AppRoutes.tukang,
      'manajer' => AppRoutes.manajer,
      'owner' => AppRoutes.owner,
      'stockist' => AppRoutes.stockist,
      _ => AppRoutes.dashboard,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!_hydrated) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final userState = ref.watch(userStateProvider);
    if (!_hasValidSession(userState)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final name = ModalRoute.of(context)?.settings.name;
        if (name != AppRoutes.login && name != '/') {
          Navigator.of(context).pushNamedAndRemoveUntil(
            AppRoutes.login,
            (r) => false,
          );
        }
      });
      return const LoginPage();
    }

    final route = _homeRouteForRole(userState.role);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ModalRoute.of(context)?.settings.name;
      if (current != route) {
        Navigator.of(context).pushNamedAndRemoveUntil(route, (r) => false);
      }
    });

    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
