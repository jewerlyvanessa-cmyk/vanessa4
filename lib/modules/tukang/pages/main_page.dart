import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/providers/technician_dashboard_provider.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';
import 'work_queue_page.dart';
import 'update_progress_page.dart';
import 'material_usage_page.dart';
import 'work_history_page.dart';
import 'reports_page.dart';

class TukangMainPage extends ConsumerWidget {
  const TukangMainPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch health check status for Live indicator
    final isServerHealthy = ref.watch(healthCheckProvider);
    final dashboardAsync = ref.watch(technicianDashboardProvider);

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

    // Initialize technician dashboard provider
    ref.read(technicianDashboardProvider.notifier).listenToUserStateChanges();

    // Listen to real-time order updates for technician notifications
    ref.listen(realTimeOrderUpdatesProvider, (previous, next) {
      next.whenData((update) {
        if (update['type'] == 'order_update' ||
            update['type'] == 'technician_assignment') {
          // Refresh technician dashboard when work assignments occur
          ref.read(technicianDashboardProvider.notifier).refresh();
          // Show notification for new work assignments or order updates
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
            const Text('Teknisi'),
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
          // User Info Section
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

          // Dashboard Summary Cards
          dashboardAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => Padding(
              padding: const EdgeInsets.all(16.0),
              child: _DashboardSummaryCards(
                pendingWorkOrders: 0,
                inProgressWorkOrders: 0,
                completedWorkOrders: 0,
              ),
            ),
            data: (dashboardData) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _DashboardSummaryCards(
                pendingWorkOrders: dashboardData.pendingWorkOrders,
                inProgressWorkOrders: dashboardData.inProgressWorkOrders,
                completedWorkOrders: dashboardData.completedWorkOrders,
              ),
            ),
          ),

          // Menu Grid (ukuran/layout selaras dashboard CS)
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ModuleMenuGrid(
                  minCrossAxisCount: 4,
                  entries: [
                  ModuleMenuEntry(
                    icon: Icons.queue,
                    label: 'ANTRIAN KERJA',
                    iconColor: Colors.blue,
                    outlined: true,
                    badgeCount: dashboardAsync.maybeWhen(
                      data: (data) => data.pendingWorkOrders,
                      orElse: () => 0,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const WorkQueuePage(),
                        ),
                      );
                    },
                  ),
                  ModuleMenuEntry(
                    icon: Icons.update,
                    label: 'UPDATE PROGRESS',
                    iconColor: Colors.orange,
                    outlined: true,
                    badgeCount: dashboardAsync.maybeWhen(
                      data: (data) => data.inProgressWorkOrders,
                      orElse: () => 0,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const UpdateProgressPage(),
                        ),
                      );
                    },
                  ),
                  ModuleMenuEntry(
                    icon: Icons.inventory,
                    label: 'PENGGUNAAN MATERIAL',
                    iconColor: Colors.green,
                    outlined: true,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MaterialUsagePage(),
                        ),
                      );
                    },
                  ),
                  ModuleMenuEntry(
                    icon: Icons.history,
                    label: 'RIWAYAT PEKERJAAN',
                    iconColor: Colors.purple,
                    outlined: true,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const WorkHistoryPage(),
                        ),
                      );
                    },
                  ),
                  ModuleMenuEntry(
                    icon: DashboardMenuIcons.laporan,
                    label: 'LAPORAN',
                    iconColor: Colors.red,
                    outlined: true,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ReportsPage(),
                        ),
                      );
                    },
                  ),
                  ModuleMenuEntry(
                    icon: Icons.refresh,
                    label: 'REFRESH DATA',
                    iconColor: Colors.teal,
                    outlined: true,
                    onTap: () {
                      ref.read(technicianDashboardProvider.notifier).refresh();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Data dashboard diperbarui'),
                        ),
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
    // Show notification for new work assignments, progress updates, etc.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pemberitahuan Teknisi: $message'),
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

class _DashboardSummaryCards extends StatelessWidget {
  final int pendingWorkOrders;
  final int inProgressWorkOrders;
  final int completedWorkOrders;

  const _DashboardSummaryCards({
    required this.pendingWorkOrders,
    required this.inProgressWorkOrders,
    required this.completedWorkOrders,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            title: 'Menunggu',
            value: pendingWorkOrders.toString(),
            icon: Icons.schedule,
            color: Colors.orange,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            title: 'Dalam Proses',
            value: inProgressWorkOrders.toString(),
            icon: Icons.engineering,
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            title: 'Selesai',
            value: completedWorkOrders.toString(),
            icon: Icons.check_circle,
            color: Colors.green,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
