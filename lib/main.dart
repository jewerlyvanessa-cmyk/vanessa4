import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/theme/app_theme.dart';
import 'routes/app_routes.dart';
import 'providers/network_provider.dart';
import 'providers/user_state_provider.dart';
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
    WebSocketNotifier.onAdminForceLogout = _onAdminForceLogout;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      NetworkConfig.onUnauthorized = () {
        ref.read(userStateProvider.notifier).logout();
      };
    });
  }

  @override
  void dispose() {
    NetworkConfig.onUnauthorized = null;
    WebSocketNotifier.onAdminForceLogout = null;
    super.dispose();
  }

  void _onAdminForceLogout(String? reason) {
    ref.read(userStateProvider.notifier).logout();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = VanessaApp.navigatorKey.currentContext;
      if (ctx == null) return;
      final text = (reason != null && reason.trim().isNotEmpty)
          ? reason.trim()
          : 'Anda dilogoutkan oleh administrator.';
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(text)));
    });
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
      routes: AppRoutes.routes,
      onGenerateRoute: AppRoutes.onGenerateRoute,
      home: const _AppHomeGate(),
      builder: (context, child) {
        final mq = ResponsiveLayout.clampMediaQuery(MediaQuery.of(context));
        Widget navigatorChild = MediaQuery(
          data: mq,
          child: child ?? const SizedBox.shrink(),
        );
        navigatorChild = ResponsiveLayout.constrainContent(
          context,
          navigatorChild,
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


class _AppHomeGate extends ConsumerWidget {
  const _AppHomeGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userState = ref.watch(userStateProvider);
    final hasSession = userState.userId != null && userState.role.isNotEmpty;
    if (!hasSession) {
      // LoginPage is registered in AppRoutes.routes, but returning it directly
      // avoids relying on initialRoute during async state hydration.
      return const LoginPage();
    }

    // Route to the correct main page based on current role.
    // We intentionally build via AppRoutes.routes to avoid importing every module here.
    final role = userState.role.trim();
    final route = switch (role) {
      'cs' => AppRoutes.cs,
      'kasir' => AppRoutes.kasir,
      'superadmin' => AppRoutes.superadmin,
      'admin_toko' => AppRoutes.adminToko,
      'admin_workshop' => AppRoutes.adminWorkshop,
      'admin_warehouse' => AppRoutes.adminWarehouse,
      'tukang' => AppRoutes.tukang,
      'manajer' => AppRoutes.manajer,
      'stockist' => AppRoutes.stockist,
      _ => AppRoutes.dashboard,
    };

    // Use Navigator to *redirect* so we never stay on the wrong home widget.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = ModalRoute.of(context)?.settings.name;
      if (current != route) {
        Navigator.of(context).pushNamedAndRemoveUntil(route, (r) => false);
      }
    });

    // While redirecting, show a lightweight placeholder to avoid flashing dashboard content.
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
