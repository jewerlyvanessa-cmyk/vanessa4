import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';
import 'workshop_orders_page.dart';
import 'technician_management_page.dart';
import 'material_stock_page.dart';
import 'workshop_reports_page.dart';
import 'workshop_settings_page.dart';
import '../../admin_toko/pages/goods_transfer_page.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/providers/workshop_dashboard_provider.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';

class AdminWorkshopMainPage extends ConsumerWidget {
  const AdminWorkshopMainPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch health check status for Live indicator
    final isServerHealthy = ref.watch(healthCheckProvider);

    // Listen to user state changes for consistency with other pages
    ref.listen(userStateProvider, (previous, next) {
      // Force rebuild when user state changes (e.g., branch/role switch)
      // This ensures UI stays consistent across all pages

      // Initialize WebSocket if user is logged in and WebSocket is not connected
      if (next.userId != null && next.role.isNotEmpty) {
        final webSocketChannel = ref.read(webSocketProvider);
        if (webSocketChannel == null) {
          ref.read(webSocketProvider.notifier).initializeAfterLogin();
        }
      }
    });

    // Initialize workshop dashboard provider
    ref.read(workshopDashboardProvider.notifier).listenToUserStateChanges();

    // Listen to real-time order updates for workshop management
    ref.listen(realTimeOrderUpdatesProvider, (previous, next) {
      next.whenData((update) {
        if (update['type'] == 'order_update' ||
            update['type'] == 'workshop_assignment') {
          // Refresh workshop dashboard when orders or assignments occur
          ref.read(workshopDashboardProvider.notifier).refresh();
          // Show notification for new workshop orders or technician updates
          _showWorkshopNotification(context, update['data']);
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Workshop'),
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/logo_bulat.png', fit: BoxFit.contain),
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
              children: [const UserBranchRoleHeader()],
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
                      icon: Icons.build,
                      label: 'ORDER WORKSHOP',
                      iconColor: Colors.blue,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const WorkshopOrdersPage(),
                        ),
                      ),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.local_shipping,
                      label: 'KIRIM / TERIMA',
                      iconColor: Colors.teal,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const GoodsTransferPage(),
                        ),
                      ),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.engineering,
                      label: 'TEKNISI',
                      iconColor: Colors.orange,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const TechnicianManagementPage(),
                        ),
                      ),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.inventory,
                      label: 'STOK MATERIAL',
                      iconColor: Colors.green,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MaterialStockPage(),
                        ),
                      ),
                    ),
                    ModuleMenuEntry(
                      icon: DashboardMenuIcons.laporan,
                      label: 'LAPORAN WORKSHOP',
                      iconColor: Colors.purple,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const WorkshopReportsPage(),
                        ),
                      ),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.settings,
                      label: 'PENGATURAN',
                      iconColor: Colors.grey,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const WorkshopSettingsPage(),
                        ),
                      ),
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

  void _showWorkshopNotification(BuildContext context, String message) {
    // Show notification for workshop orders, technician assignments, etc.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pemberitahuan Workshop: $message'),
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
