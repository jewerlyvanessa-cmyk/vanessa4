import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';
import 'package:vanessa3/utils/auth_session_end.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

/// Logo + judul modul — teks memendek otomatis di layar sempit (hindari overflow AppBar).
class ModuleAppBarTitle extends StatelessWidget {
  const ModuleAppBarTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(
          'assets/logo_bulat.png',
          height: 36,
          width: 36,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// AppBar standar halaman menu dashboard (semua role).
class ModuleDashboardAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const ModuleDashboardAppBar({
    super.key,
    required this.title,
    this.logoInLeading = false,
  });

  final String title;

  /// Logo di [AppBar.leading] (mis. Admin Workshop) — judul hanya teks.
  final bool logoInLeading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isServerHealthy = ref.watch(healthCheckProvider);
    final compact = ResponsiveLayout.isCompact(context);

    return AppBar(
      title: logoInLeading
          ? Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : ModuleAppBarTitle(title: title),
      leading: logoInLeading
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: Image.asset(
                'assets/logo_bulat.png',
                fit: BoxFit.contain,
              ),
            )
          : null,
      leadingWidth: logoInLeading ? 56 : null,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isServerHealthy ? Icons.wifi : Icons.wifi_off,
                color: isServerHealthy ? Colors.green : Colors.red,
                size: 20,
              ),
              if (!compact) ...[
                const SizedBox(width: 4),
                const Text('Live', style: TextStyle(fontSize: 12)),
              ],
            ],
          ),
        ),
        const SwitchBranchRoleWidget(),
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Logout',
          onPressed: () {
            ref.read(webSocketProvider.notifier).disconnect();
            ref.read(userStateProvider.notifier).logout();
            navigateToLoginClearingStack(VanessaApp.navigatorKey);
          },
        ),
      ],
    );
  }
}
