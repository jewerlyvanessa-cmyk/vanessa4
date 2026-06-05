import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vanessa3/core/state/user_state.dart';
import 'package:vanessa3/modules/admin_toko/pages/daily_orders_payments_page.dart';
import 'package:vanessa3/modules/admin_toko/pages/stock_page.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/shared_widgets/module_dashboard_app_bar.dart';
import 'package:vanessa3/shared_widgets/role_menu_body.dart';
import 'package:vanessa3/shared_widgets/offline_status_banner.dart';
import 'package:vanessa3/services/offline_sync_events.dart';
import 'package:vanessa3/providers/order_today_provider.dart';
import 'package:vanessa3/providers/cs_daily_orders_refresh_provider.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

String getMainModuleForRole(String role) {
  switch (role) {
    case 'cs':
      return 'cs';
    case 'kasir':
      return 'kasir';
    case 'superadmin':
      return 'superadmin';
    case 'admin_toko':
      return 'admin_toko';
    case 'admin_workshop':
      return 'admin_workshop';
    case 'admin_warehouse':
      return 'admin_warehouse';
    case 'tukang':
      return 'tukang';
    case 'manajer':
      return 'manajer';
    case 'stockist':
      return 'stockist';
    default:
      return 'dashboard';
  }
}

void navigateToMainModule(BuildContext context, String mainModule) {
  final navigator = Navigator.of(context);
  switch (mainModule) {
    case 'cs':
      navigator.pushReplacementNamed('/cs');
      break;
    case 'kasir':
      navigator.pushReplacementNamed('/kasir');
      break;
    case 'admin_toko':
      navigator.pushReplacementNamed('/admin_toko');
      break;
    case 'admin_workshop':
      navigator.pushReplacementNamed('/admin_workshop');
      break;
    case 'admin_warehouse':
      navigator.pushReplacementNamed('/admin_warehouse');
      break;
    case 'tukang':
      navigator.pushReplacementNamed('/tukang');
      break;
    case 'superadmin':
      navigator.pushReplacementNamed('/superadmin');
      break;
    case 'manajer':
      navigator.pushReplacementNamed('/manager');
      break;
    case 'stockist':
      navigator.pushReplacementNamed('/stockist');
      break;
    default:
      navigator.pushReplacementNamed('/dashboard');
  }
}

class CSMainPage extends ConsumerStatefulWidget {
  const CSMainPage({super.key});

  @override
  ConsumerState<CSMainPage> createState() => _CSMainPageState();
}

class _CSMainPageState extends ConsumerState<CSMainPage> {
  ProviderSubscription<UserState>? _csUserSessionSub;
  StreamSubscription<void>? _offlineSyncSub;

  @override
  void initState() {
    super.initState();
    _offlineSyncSub = OfflineSyncEvents.onFlushed.listen((_) {
      if (!mounted) return;
      ref.invalidate(orderTodayStatsProvider);
      ref.invalidate(todayOrdersProvider);
      bumpCsDailyOrdersListRevision(ref);
    });
  }

  @override
  void dispose() {
    _offlineSyncSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _csUserSessionSub ??= ref.listenManual<UserState>(
      userStateProvider,
      (previous, next) {
        if (next.userId != null && next.role.isNotEmpty) {
          final webSocketChannel = ref.read(webSocketProvider);
          if (webSocketChannel == null) {
            ref.read(webSocketProvider.notifier).initializeAfterLogin();
          }
        }
      },
      fireImmediately: true,
    );
  }

  void _openOrderDanBayar(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => const DailyOrdersPaymentsPage(ordersOnly: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        return Scaffold(
          appBar: const ModuleDashboardAppBar(title: 'CS'),
          body: RoleMenuBody(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const OfflineStatusBanner(),
              Padding(
                padding: ResponsiveLayout.roleMenuHeaderPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [UserBranchRoleHeader()],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ModuleMenuGrid(
                  minCrossAxisCount: 4,
                  entries: [
                    ModuleMenuEntry(
                      icon: Icons.shopping_cart,
                      label: 'JUAL',
                      iconColor: Colors.orange,
                      onTap: () => Navigator.pushNamed(context, '/jual'),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.replay,
                      label: 'BUYBACK',
                      iconColor: Colors.green,
                      onTap: () => Navigator.pushNamed(context, '/buyback'),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.build,
                      label: 'SERVICE',
                      iconColor: Colors.blue,
                      onTap: () => Navigator.pushNamed(context, '/service'),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.design_services,
                      label: 'CUSTOM',
                      iconColor: Colors.purple,
                      onTap: () => Navigator.pushNamed(context, '/custom'),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.assignment_return,
                      label: 'AMBIL',
                      iconColor: Colors.indigo,
                      onTap: () => Navigator.pushNamed(context, '/ambil'),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.receipt_long,
                      label: 'ORDER TODAY',
                      iconColor: Colors.blue,
                      onTap: () => _openOrderDanBayar(context),
                    ),
                    ModuleMenuEntry(
                      icon: DashboardMenuIcons.pelanggan,
                      label: 'PELANGGAN',
                      iconColor: Colors.cyan,
                      onTap: () => Navigator.pushNamed(context, '/customers'),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.inventory_2,
                      label: 'STOK',
                      iconColor: Colors.teal,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const StockPage(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    0,
                    12,
                    12 + ResponsiveLayout.scrollEndGap(context),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: const DailyOrdersPaymentsPage(
                      embedInParent: true,
                      ordersOnly: true,
                    ),
                  ),
                ),
              ),
            ],
            ),
          ),
        );
      },
    );
  }
}
