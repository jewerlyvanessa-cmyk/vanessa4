import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/module_navigation_util.dart';

class SwitchBranchRoleWidget extends ConsumerWidget {
  final void Function(String branchId, String role)? onSwitched;
  const SwitchBranchRoleWidget({super.key, this.onSwitched});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userState = ref.watch(userStateProvider);
    final branchList = userState.branches;
    final currentBranch = userState.branch;

    final branchObj = branchList.firstWhere(
      (b) => b['branch_id'].toString() == currentBranch,
      orElse: () => <String, dynamic>{},
    );
    final rolesInBranch = (branchObj['roles'] is List)
        ? List<String>.from(branchObj['roles'])
        : <String>[];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (branchList.length > 1)
          kIsWeb
              ? IconButton(
                  icon: const Icon(Icons.account_tree),
                  tooltip: 'Ganti Branch',
                  onPressed: () => _showWebBranchPicker(
                    context,
                    ref,
                    branchList,
                    currentBranch,
                    onSwitched,
                  ),
                )
              : PopupMenuButton<String>(
                  icon: const Icon(Icons.account_tree),
                  tooltip: 'Ganti Branch',
                  onSelected: (branchId) {
                    _onBranchSelected(
                      context,
                      ref,
                      branchList,
                      branchId,
                      onSwitched,
                    );
                  },
                  itemBuilder: (context) => branchList
                      .map(
                        (branch) => PopupMenuItem<String>(
                          value: branch['branch_id'].toString(),
                          child: Text(
                            branch['name']?.toString() ??
                                branch['branch_id'].toString(),
                          ),
                        ),
                      )
                      .toList(),
                ),
        if (rolesInBranch.length > 1)
          kIsWeb
              ? IconButton(
                  icon: const Icon(Icons.switch_account),
                  tooltip: 'Ganti Role',
                  onPressed: () => _showWebRolePicker(
                    context,
                    ref,
                    rolesInBranch,
                    currentBranch,
                    onSwitched,
                  ),
                )
              : PopupMenuButton<String>(
                  icon: const Icon(Icons.switch_account),
                  tooltip: 'Ganti Role',
                  onSelected: (role) {
                    _onRoleSelected(
                      context,
                      ref,
                      currentBranch,
                      role,
                      onSwitched,
                    );
                  },
                  itemBuilder: (context) => rolesInBranch
                      .map(
                        (role) => PopupMenuItem<String>(
                          value: role,
                          child: Text(role),
                        ),
                      )
                      .toList(),
                ),
      ],
    );
  }
}

Future<void> _onBranchSelected(
  BuildContext context,
  WidgetRef ref,
  List<Map<String, dynamic>> branchList,
  String branchId,
  void Function(String branchId, String role)? onSwitched,
) async {
  final bObj = branchList.firstWhere(
    (b) => b['branch_id'].toString() == branchId,
    orElse: () => <String, dynamic>{},
  );
  final roles = (bObj['roles'] is List)
      ? List<String>.from(bObj['roles'])
      : <String>[];
  if (roles.isEmpty) {
    ref.read(userStateProvider.notifier).setBranch(branchId);
    ref.read(userStateProvider.notifier).setRole('');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cabang ${bObj['name'] ?? branchId} tidak punya peran — hubungi admin.',
          ),
        ),
      );
    }
    return;
  }
  final newRole = roles[0].trim().toLowerCase();
  final s = ref.read(userStateProvider);
  if (s.userId == null) return;
  try {
    final data = await ApiService.switchSessionContext(
      branchId: branchId,
      role: newRole,
    );
    final newToken = data['token']?.toString() ?? '';
    if (newToken.isEmpty) {
      throw Exception('Token kosong dari server');
    }
    ref.read(userStateProvider.notifier).setUserData(
          userId: s.userId,
          username: s.username,
          branch: branchId,
          role: newRole,
          authToken: newToken,
          roles: s.roles,
          branches: s.branches,
        );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal ganti cabang: $e')),
      );
    }
    return;
  }
  if (!context.mounted) return;
  navigateToMainModule(context, getMainModuleForRole(newRole));
  onSwitched?.call(branchId, newRole);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Branch diganti ke: ${bObj['name'] ?? branchId}, role: $newRole',
      ),
    ),
  );
}

Future<void> _onRoleSelected(
  BuildContext context,
  WidgetRef ref,
  String currentBranch,
  String role,
  void Function(String branchId, String role)? onSwitched,
) async {
  final normalizedRole = role.trim().toLowerCase();
  final s = ref.read(userStateProvider);
  if (s.userId == null) return;
  try {
    final data = await ApiService.switchSessionContext(
      branchId: currentBranch,
      role: normalizedRole,
    );
    final newToken = data['token']?.toString() ?? '';
    if (newToken.isEmpty) {
      throw Exception('Token kosong dari server');
    }
    ref.read(userStateProvider.notifier).setUserData(
          userId: s.userId,
          username: s.username,
          branch: currentBranch,
          role: normalizedRole,
          authToken: newToken,
          roles: s.roles,
          branches: s.branches,
        );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal ganti peran: $e')),
      );
    }
    return;
  }
  if (!context.mounted) return;
  navigateToMainModule(context, getMainModuleForRole(normalizedRole));
  onSwitched?.call(currentBranch, normalizedRole);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Role diganti ke: $normalizedRole')),
  );
}

Future<void> _showWebBranchPicker(
  BuildContext context,
  WidgetRef ref,
  List<Map<String, dynamic>> branchList,
  String currentBranch,
  void Function(String branchId, String role)? onSwitched,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Pilih cabang',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            ...branchList.map((branch) {
              final id = branch['branch_id'].toString();
              final name =
                  branch['name']?.toString() ?? branch['branch_id'].toString();
              final selected = id == currentBranch;
              return ListTile(
                title: Text(name),
                leading: Icon(
                  selected ? Icons.check_circle : Icons.store_outlined,
                  color:
                      selected ? Theme.of(ctx).colorScheme.primary : null,
                ),
                selected: selected,
                onTap: () {
                  Navigator.pop(ctx);
                  _onBranchSelected(context, ref, branchList, id, onSwitched);
                },
              );
            }),
          ],
        ),
      );
    },
  );
}

Future<void> _showWebRolePicker(
  BuildContext context,
  WidgetRef ref,
  List<String> rolesInBranch,
  String currentBranch,
  void Function(String branchId, String role)? onSwitched,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Pilih peran',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            ...rolesInBranch.map((role) {
              return ListTile(
                title: Text(role),
                leading: const Icon(Icons.badge_outlined),
                onTap: () {
                  Navigator.pop(ctx);
                  _onRoleSelected(
                    context,
                    ref,
                    currentBranch,
                    role,
                    onSwitched,
                  );
                },
              );
            }),
          ],
        ),
      );
    },
  );
}
