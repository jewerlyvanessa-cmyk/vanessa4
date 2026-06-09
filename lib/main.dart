import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/state/user_state.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/login_page.dart';
import 'routes/app_routes.dart';
import 'routes/role_home_route.dart';
import 'providers/network_provider.dart';
import 'providers/offline_queue_provider.dart';
import 'providers/user_state_provider.dart';
import 'utils/auth_session_end.dart';
import 'utils/network_config.dart';
import 'utils/network_connectivity.dart';
import 'utils/responsive_layout.dart';
import 'utils/sentry_bootstrap.dart';
import 'providers/websocket_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);

  assert(() {
    debugPrint(
      'Network Config - USE_LOCAL_API=${const bool.fromEnvironment('USE_LOCAL_API', defaultValue: false)} '
      'API_HOST="${const String.fromEnvironment('API_HOST', defaultValue: '')}" '
      'API_PORT="${const String.fromEnvironment('API_PORT', defaultValue: '')}" '
      'API_SCHEME="${const String.fromEnvironment('API_SCHEME', defaultValue: '')}"',
    );
    debugPrint('Network Config - Base URL: ${NetworkConfig.baseUrl}');
    debugPrint('Network Config - WebSocket URL: ${NetworkConfig.wsUrl}');
    return true;
  }());

  await SentryBootstrap.runApp(() {
    runApp(ProviderScope(child: const VanessaApp()));
  });
}

class VanessaApp extends ConsumerStatefulWidget {
  const VanessaApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

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
    final userState = ref.watch(userStateProvider);
    NetworkConfig.setAuthToken(
      userState.authToken.isEmpty ? null : userState.authToken,
    );

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
      initialRoute: '/',
      routes: <String, WidgetBuilder>{
        '/': (context) => const _AppHomeGate(),
        ...AppRoutes.routes,
      },
      onGenerateRoute: AppRoutes.onGenerateRoute,
      builder: (context, child) {
        // Clamp text scale agar layout tidak pecah di HP dengan teks sangat besar.
        final mq = ResponsiveLayout.clampMediaQuery(MediaQuery.of(context));
        Widget content = MediaQuery(
          data: mq,
          child: child ?? const SizedBox.shrink(),
        );

        // Web: safe area untuk notch/gesture bar browser.
        if (kIsWeb) content = ResponsiveLayout.appChrome(content);

        // Status koneksi — banner di atas Navigator, tidak mengganggu AppBar.
        final offline = !networkState.isOnline;
        final unreachable = !networkState.isBackendReachable;
        if (!offline && !unreachable) return content;

        return _ConnectionBanner(
          offline: offline,
          networkState: networkState,
          child: content,
        );
      },
    );
  }
}

/// Banner koneksi — terpisah agar build method utama tetap bersih.
class _ConnectionBanner extends ConsumerWidget {
  const _ConnectionBanner({
    required this.offline,
    required this.networkState,
    required this.child,
  });

  final bool offline;
  final dynamic networkState;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = offline ? Colors.red : Colors.orange;
    final label = offline ? 'Offline — Ketuk untuk coba ulang'
        : 'Server tidak terjangkau — Ketuk untuk coba ulang';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: color,
          child: InkWell(
            onTap: () async {
              final notifier = ref.read(networkStatusProvider.notifier);
              await notifier.refresh();
              final status = await NetworkConnectivity.getDetailedNetworkStatus(
                NetworkConfig.baseUrl,
              );
              if (!context.mounted) return;
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(
                  content: Text(status),
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Icon(Icons.refresh, color: Colors.white, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
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

    final route = homeRouteForRole(userState.role);
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
