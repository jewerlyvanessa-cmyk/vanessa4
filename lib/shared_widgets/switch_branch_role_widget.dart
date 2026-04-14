import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/shared_widgets/module_navigation_util.dart';

class SwitchBranchRoleWidget extends ConsumerWidget {
  final void Function(String branchId, String role)? onSwitched;
  const SwitchBranchRoleWidget({super.key, this.onSwitched});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userState = ref.watch(userStateProvider);
    final branchList = userState.branches;
    final currentBranch = userState.branch;

    // Cari branch aktif dan roles di branch tersebut
    final branchObj = branchList.firstWhere(
      (b) => b['branch_id'].toString() == currentBranch,
      orElse: () => <String, dynamic>{},
    );
    final rolesInBranch = (branchObj['roles'] is List)
        ? List<String>.from(branchObj['roles'])
        : <String>[];

    return Row(
      children: [
        if (branchList.length > 1)
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_tree),
            tooltip: 'Ganti Branch',
            onSelected: (branchId) {
              ref.read(userStateProvider.notifier).setBranch(branchId);
              final branchObj = branchList.firstWhere(
                (b) => b['branch_id'].toString() == branchId,
                orElse: () => <String, dynamic>{},
              );
              final rolesInBranch = (branchObj['roles'] is List)
                  ? List<String>.from(branchObj['roles'])
                  : <String>[];
              String newRole = '';
              if (rolesInBranch.isNotEmpty) {
                newRole = rolesInBranch[0];
                ref.read(userStateProvider.notifier).setRole(newRole);
                // Navigasi ke halaman sesuai role baru
                final mainModule = getMainModuleForRole(newRole);
                navigateToMainModule(context, mainModule);
              } else {
                ref.read(userStateProvider.notifier).setRole('');
              }
              if (onSwitched != null) {
                onSwitched!(branchId, newRole);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Branch diganti ke: ${branchObj['name'] ?? branchId}, role: $newRole')),
              );
            },
            itemBuilder: (context) => branchList.map((branch) => PopupMenuItem(
              value: branch['branch_id'].toString(),
              child: Text(branch['name'] ?? branch['branch_id'].toString()),
            )).toList(),
          ),
        if (rolesInBranch.length > 1)
          PopupMenuButton<String>(
            icon: const Icon(Icons.switch_account),
            tooltip: 'Ganti Role',
            onSelected: (role) {
              ref.read(userStateProvider.notifier).setRole(role);
              // Navigasi ke halaman sesuai role
              final mainModule = getMainModuleForRole(role);
              navigateToMainModule(context, mainModule);
              if (onSwitched != null) {
                onSwitched!(currentBranch, role);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Role diganti ke: $role')),
              );
            },
            itemBuilder: (context) => rolesInBranch.map((role) => PopupMenuItem(
              value: role,
              child: Text(role),
            )).toList(),
          ),
      ],
    );
  }
}
