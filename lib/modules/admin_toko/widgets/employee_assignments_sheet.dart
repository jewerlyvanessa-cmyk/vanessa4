import 'package:flutter/material.dart';
import 'package:vanessa3/modules/admin_toko/logic/employee_role_utils.dart';

void showEmployeeAssignmentsSheet(
  BuildContext context, {
  required String username,
  required String defaultStatus,
  required List<Map<String, dynamic>> assignments,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                username,
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Penugasan role',
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
              const Divider(height: 24),
              if (assignments.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Tidak ada baris penugasan'),
                )
              else
                ...assignments.map((a) {
                  final role = (a['role'] ?? '').toString();
                  final rowStatus =
                      (a['status'] ?? defaultStatus).toString();
                  final userId = (a['user_id'] ?? '').toString();
                  return ListTile(
                    leading: Icon(
                      Icons.badge,
                      color: EmployeeRoleUtils.roleColor(role),
                    ),
                    title: Text(EmployeeRoleUtils.label(role)),
                    subtitle: Text('User ID: $userId'),
                    trailing: Text(
                      rowStatus == 'active' ? 'aktif' : 'nonaktif',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: rowStatus == 'active'
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      );
    },
  );
}
