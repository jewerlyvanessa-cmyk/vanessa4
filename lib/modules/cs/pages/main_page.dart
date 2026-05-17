import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vanessa3/core/state/user_state.dart';
import 'package:vanessa3/modules/admin_toko/pages/daily_orders_payments_page.dart';
import 'package:vanessa3/modules/admin_toko/pages/stock_page.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';

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
        final isServerHealthy = ref.watch(healthCheckProvider);

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Image.asset(
                  'assets/logo_bulat.png',
                  height: 36,
                  width: 36,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 12),
                const Text('CS'),
              ],
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    Icon(
                      isServerHealthy ? Icons.wifi : Icons.wifi_off,
                      color: isServerHealthy ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    const Text('Live', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              SwitchBranchRoleWidget(),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Logout',
                onPressed: () {
                  ref.read(webSocketProvider.notifier).disconnect();
                  ref.read(userStateProvider.notifier).logout();
                  Navigator.pushReplacementNamed(context, '/login');
                },
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: 24.0,
                  top: 24.0,
                  right: 24.0,
                  bottom: 8.0,
                ),
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
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
        );
      },
    );
  }
}
