import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/routes/app_navigator.dart';
import 'package:vanessa3/routes/app_routes.dart' hide SwitchBranchRoleWidget;
import 'package:vanessa3/shared_widgets/module_destination_sheet.dart';
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';
import 'package:vanessa3/providers/manager_dashboard_provider.dart';

class ManajerMainPage extends ConsumerWidget {
  const ManajerMainPage({super.key});

  void _openLaporanHarian(BuildContext context) {
    showModuleDestinationSheet(
      context,
      title: 'Laporan harian',
      options: [
        ModuleDestinationOption(
          label: 'Laporan penjualan',
          subtitle: 'Penjualan hari ini per cabang',
          icon: Icons.trending_up,
          iconColor: Colors.orange,
          onTap: () => pushAppRoute(context, AppRoutes.manajerSalesToday),
        ),
        ModuleDestinationOption(
          label: 'Laporan buyback',
          subtitle: 'Buyback hari ini per cabang',
          icon: Icons.currency_exchange,
          iconColor: Colors.deepOrange,
          onTap: () => pushAppRoute(context, AppRoutes.manajerBuybackReport),
        ),
      ],
    );
  }

  void _openStok(BuildContext context) {
    showModuleDestinationSheet(
      context,
      title: 'Stok',
      options: [
        ModuleDestinationOption(
          label: 'Stok global',
          subtitle: 'Inventori seluruh cabang',
          icon: DashboardMenuIcons.stokGlobal,
          iconColor: Colors.purple,
          onTap: () => pushAppRoute(context, AppRoutes.manajerGlobalStock),
        ),
        ModuleDestinationOption(
          label: 'Stok per cabang',
          subtitle: 'Inventori detail per toko',
          icon: Icons.store,
          iconColor: Colors.green,
          onTap: () => pushAppRoute(context, AppRoutes.manajerStockCabang),
        ),
        ModuleDestinationOption(
          label: 'Laporan rekap stok',
          subtitle: 'Ringkasan per jenis & periode',
          icon: Icons.inventory_2_outlined,
          iconColor: Colors.teal,
          onTap: () => pushAppRoute(context, AppRoutes.manajerStockReport),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isServerHealthy = ref.watch(healthCheckProvider);

    ref.listen(userStateProvider, (previous, next) {});

    ref.read(managerDashboardProvider.notifier).listenToUserStateChanges();

    ref.listen(userStateProvider, (previous, next) {
      if (next.userId != null && next.role.isNotEmpty) {
        final webSocketChannel = ref.read(webSocketProvider);
        if (webSocketChannel == null) {
          ref.read(webSocketProvider.notifier).initializeAfterLogin();
        }
      }
    });

    ref.listen(realTimeOrderUpdatesProvider, (previous, next) {
      next.whenData((update) {
        if (update['type'] == 'order_update' ||
            update['type'] == 'manager_alert') {
          ref.read(managerDashboardProvider.notifier).refresh();
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
              Navigator.pushReplacementNamed(context, AppRoutes.login);
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(
              left: 24.0,
              top: 24.0,
              right: 24.0,
              bottom: 8.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [UserBranchRoleHeader()],
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
                      onTap: () => pushAppRoute(
                        context,
                        AppRoutes.manajerBranchPerformance,
                      ),
                    ),
                    ModuleMenuEntry(
                      icon: DashboardMenuIcons.laporan,
                      label: 'LAPORAN HARIAN',
                      iconColor: Colors.orange,
                      onTap: () => _openLaporanHarian(context),
                    ),
                    ModuleMenuEntry(
                      icon: DashboardMenuIcons.stokGlobal,
                      label: 'STOK',
                      iconColor: Colors.teal,
                      onTap: () => _openStok(context),
                    ),
                    ModuleMenuEntry(
                      icon: DashboardMenuIcons.kelolaPengguna,
                      label: 'USER',
                      iconColor: Colors.purple,
                      onTap: () =>
                          pushAppRoute(context, AppRoutes.manajerEmployees),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.fact_check,
                      label: 'ORDER SELESAI',
                      iconColor: Colors.green,
                      onTap: () => pushAppRoute(
                        context,
                        AppRoutes.manajerCompletedOrdersToday,
                      ),
                    ),
                    ModuleMenuEntry(
                      icon: DashboardMenuIcons.pelanggan,
                      label: 'PELANGGAN',
                      iconColor: Colors.cyan,
                      onTap: () => pushAppRoute(context, AppRoutes.customers),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pemberitahuan Manajer: $message'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {},
        ),
      ),
    );
  }
}
