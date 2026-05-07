import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/providers/user_state_provider.dart';

class UserBranchRoleHeader extends ConsumerWidget {
  const UserBranchRoleHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userState = ref.watch(userStateProvider);

    String branchName = userState.branch;
    if (userState.branch.isNotEmpty && userState.branches.isNotEmpty) {
      try {
        final found = userState.branches.firstWhere(
          (b) => b['branch_id'].toString() == userState.branch,
        );
        branchName = (found['name'] ?? userState.branch).toString();
      } catch (_) {
        branchName = userState.branch;
      }
    }

    final username = (userState.username.isNotEmpty ? userState.username : '-')
        .toUpperCase();
    final branch = (branchName.isNotEmpty ? branchName : '-').toUpperCase();
    final role = (userState.role.isNotEmpty ? userState.role : '-').toUpperCase();

    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 12,
          height: 1.15,
          fontWeight: FontWeight.w600,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Row(label: 'USER', value: username, style: textStyle),
        const SizedBox(height: 2),
        _Row(label: 'BRANCH AKTIF', value: branch, style: textStyle),
        const SizedBox(height: 2),
        _Row(label: 'ROLE AKTIF', value: role, style: textStyle),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? style;

  const _Row({required this.label, required this.value, required this.style});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 110, child: Text(label, style: style)),
        Text(':', style: style),
        const SizedBox(width: 6),
        Expanded(child: Text(value, style: style)),
      ],
    );
  }
}

