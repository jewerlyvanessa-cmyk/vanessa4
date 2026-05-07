import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';
import 'package:vanessa3/providers/system_dashboard_provider.dart';
import 'user_management_page.dart';
import './branch_management_page.dart';
import 'package:vanessa3/modules/cs/pages/customers_page.dart';
import 'import_data_page.dart';
import 'export_data_page.dart';
import 'active_user_sessions_page.dart';

class SuperadminMainPage extends ConsumerStatefulWidget {
  const SuperadminMainPage({super.key});

  @override
  ConsumerState<SuperadminMainPage> createState() => _SuperadminMainPageState();
}

class _SuperadminMainPageState extends ConsumerState<SuperadminMainPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final us = ref.read(userStateProvider);
      if (us.userId != null && us.role.isNotEmpty) {
        ref
            .read(webSocketProvider.notifier)
            .ensureConnected(authToken: us.authToken);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch health check status for Live indicator
    final isServerHealthy = ref.watch(healthCheckProvider);

    ref.listen(userStateProvider, (previous, next) {
      if (next.userId != null && next.role.isNotEmpty) {
        ref.read(webSocketProvider.notifier).ensureConnected(authToken: next.authToken);
      }
    });

    // Initialize system dashboard provider
    ref.read(systemDashboardProvider.notifier).listenToUserStateChanges();

    // Listen to real-time order updates for superadmin management
    ref.listen(realTimeOrderUpdatesProvider, (previous, next) {
      next.whenData((update) {
        if (update['type'] == 'order_update' ||
            update['type'] == 'system_update') {
          // Refresh system dashboard when system-wide updates occur
          ref.read(systemDashboardProvider.notifier).refresh();
          // Show notification for system-wide updates, user management, etc.
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
            const Text('Superadmin'),
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
                    icon: DashboardMenuIcons.kelolaPengguna,
                    label: 'USER',
                    iconColor: Colors.blue,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const UserManagementPage(),
                      ),
                    ),
                  ),
                  ModuleMenuEntry(
                    icon: Icons.how_to_reg,
                    label: 'USER LOGIN',
                    iconColor: Colors.teal,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ActiveUserSessionsPage(),
                      ),
                    ),
                  ),
                  ModuleMenuEntry(
                    icon: Icons.business,
                    label: 'CABANG',
                    iconColor: Colors.orange,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BranchManagementPage(),
                      ),
                    ),
                  ),
                  ModuleMenuEntry(
                    icon: DashboardMenuIcons.pelanggan,
                    label: 'PELANGGAN',
                    iconColor: Colors.green,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CustomersPage(),
                      ),
                    ),
                  ),
                  ModuleMenuEntry(
                    icon: Icons.upload_file,
                    label: 'IMPORT DATA',
                    iconColor: Colors.purple,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ImportDataPage(),
                      ),
                    ),
                  ),
                  ModuleMenuEntry(
                    icon: Icons.download,
                    label: 'EXPORT DATA',
                    iconColor: Colors.red,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ExportDataPage(),
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

  void _showWorkNotification(BuildContext context, String message) {
    // Show notification for system-wide updates, user management, etc.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pemberitahuan Sistem: $message'),
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
