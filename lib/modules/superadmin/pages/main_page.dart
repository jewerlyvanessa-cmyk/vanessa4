import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';
import 'package:vanessa3/shared_widgets/module_dashboard_app_bar.dart';
import 'package:vanessa3/shared_widgets/role_menu_body.dart';
import 'package:vanessa3/utils/responsive_layout.dart';
import 'package:vanessa3/providers/system_dashboard_provider.dart';
import 'user_management_page.dart';
import './branch_management_page.dart';
import 'package:vanessa3/modules/cs/pages/customers_page.dart';
import 'import_data_page.dart';
import 'export_data_page.dart';
import 'backup_google_drive_page.dart';
import 'backup_local_page.dart';
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
      appBar: const ModuleDashboardAppBar(title: 'Superadmin'),
      body: RoleMenuBody(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: ResponsiveLayout.roleMenuHeaderPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const UserBranchRoleHeader(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ResponsiveLayout.roleMenuScroll(
              context: context,
              child: Padding(
                padding: ResponsiveLayout.roleMenuHorizontalPadding,
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
                  ModuleMenuEntry(
                    icon: Icons.cloud_upload,
                    label: 'BACKUP DRIVE',
                    iconColor: Colors.indigo,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BackupGoogleDrivePage(),
                      ),
                    ),
                  ),
                  ModuleMenuEntry(
                    icon: Icons.phone_android,
                    label: 'BACKUP LOKAL',
                    iconColor: Colors.brown,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BackupLocalPage(),
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
