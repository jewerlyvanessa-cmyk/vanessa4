import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';
import 'package:vanessa3/providers/manager_dashboard_provider.dart';
import 'package:vanessa3/routes/app_routes.dart' as routes;

class ManajerMainPage extends ConsumerWidget {
  const ManajerMainPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch health check status for Live indicator
    final isServerHealthy = ref.watch(healthCheckProvider);

    // Listen to user state changes for consistency with other pages
    ref.listen(userStateProvider, (previous, next) {
      // Force rebuild when user state changes (e.g., branch/role switch)
      // This ensures UI stays consistent across all pages
    });

    // Initialize manager dashboard provider
    ref.read(managerDashboardProvider.notifier).listenToUserStateChanges();

    // Listen to user state changes and initialize WebSocket if needed
    ref.listen(userStateProvider, (previous, next) {
      if (next.userId != null && next.role.isNotEmpty) {
        final webSocketChannel = ref.read(webSocketProvider);
        if (webSocketChannel == null) {
          ref.read(webSocketProvider.notifier).initializeAfterLogin();
        }
      }
    });

    // Listen to real-time order updates for manager oversight
    ref.listen(realTimeOrderUpdatesProvider, (previous, next) {
      next.whenData((update) {
        if (update['type'] == 'order_update' ||
            update['type'] == 'manager_alert') {
          // Refresh manager dashboard when performance or order updates occur
          ref.read(managerDashboardProvider.notifier).refresh();
          // Show notification for managerial alerts, performance updates, etc.
          _showWorkNotification(context, update['data']);
        }
      });
    });

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
            const Text('Manajer'),
          ],
        ),
        actions: [
          // Real-time connection indicator
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
              children: [
                const UserBranchRoleHeader(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ModuleMenuGrid(
                  minCrossAxisCount: 4,
                  entries: [
                  ModuleMenuEntry(
                    icon: Icons.bar_chart,
                    label: 'PERFORMA CABANG',
                    iconColor: Colors.blue,
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        routes.AppRoutes.manajerBranchPerformance,
                      );
                    },
                  ),
                  ModuleMenuEntry(
                    icon: Icons.trending_up,
                    label: 'LAPORAN PENJUALAN',
                    iconColor: Colors.orange,
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        routes.AppRoutes.manajerSalesToday,
                      );
                    },
                  ),
                  ModuleMenuEntry(
                    icon: Icons.currency_exchange,
                    label: 'LAPORAN BUYBACK',
                    iconColor: Colors.deepOrange,
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        routes.AppRoutes.manajerBuybackReport,
                      );
                    },
                  ),
                  ModuleMenuEntry(
                    icon: Icons.inventory_2_outlined,
                    label: 'LAPORAN STOK',
                    iconColor: Colors.teal,
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        routes.AppRoutes.manajerStockReport,
                      );
                    },
                  ),
                  ModuleMenuEntry(
                    icon: DashboardMenuIcons.stokGlobal,
                    label: 'STOK GLOBAL',
                    iconColor: Colors.green,
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        routes.AppRoutes.manajerGlobalStock,
                      );
                    },
                  ),
                  ModuleMenuEntry(
                    icon: DashboardMenuIcons.kelolaPengguna,
                    label: 'USER',
                    iconColor: Colors.purple,
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        routes.AppRoutes.manajerEmployees,
                      );
                    },
                  ),
                  ModuleMenuEntry(
                    icon: Icons.fact_check,
                    label: 'ORDER COMPLETED HARI INI',
                    iconColor: Colors.green,
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        routes.AppRoutes.manajerCompletedOrdersToday,
                      );
                    },
                  ),
                  ModuleMenuEntry(
                    icon: DashboardMenuIcons.pelanggan,
                    label: 'PELANGGAN',
                    iconColor: Colors.cyan,
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        routes.AppRoutes.customers,
                      );
                    },
                  ),
                ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showWorkNotification(BuildContext context, String message) {
    // Show notification for managerial alerts, performance updates, etc.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pemberitahuan Manajer: $message'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {
            // Handle notification action
          },
        ),
      ),
    );
  }
}
