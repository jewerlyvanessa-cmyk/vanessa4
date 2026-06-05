import 'package:flutter/material.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/modules/admin_toko/logic/employee_group_utils.dart';
import 'package:vanessa3/modules/admin_toko/logic/employee_role_utils.dart';
import 'package:vanessa3/modules/admin_toko/widgets/employee_summary_card.dart';

typedef EmployeeRowAction = void Function(
  Map<String, dynamic> employee,
  String action,
);

typedef EmployeeDetailTap = void Function(
  String username,
  String status,
  List<Map<String, dynamic>> assignments,
);

class EmployeesManagementBody extends StatelessWidget {
  const EmployeesManagementBody({
    super.key,
    required this.allEmployees,
    required this.onEmployeeAction,
    required this.onShowDetail,
  });

  final List<dynamic> allEmployees;
  final EmployeeRowAction onEmployeeAction;
  final EmployeeDetailTap onShowDetail;

  @override
  Widget build(BuildContext context) {
    final allRows = EmployeeGroupUtils.asEmployeeMaps(allEmployees);
    final activeRows = allRows
        .where((e) => (e['status'] ?? '').toString() == 'active')
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 600;
        final pad = narrow ? 12.0 : 16.0;
        const desktopTableW = 880.0;
        final panelW = constraints.maxWidth;
        final BoxConstraints tableBoxConstraints;
        if (narrow) {
          tableBoxConstraints = BoxConstraints.tightFor(width: panelW - pad * 2);
        } else if (panelW - pad * 2 >= desktopTableW) {
          tableBoxConstraints = BoxConstraints.tightFor(width: desktopTableW);
        } else {
          tableBoxConstraints = const BoxConstraints(minWidth: desktopTableW);
        }

        final cs = Theme.of(context).colorScheme;
        final groups = EmployeeGroupUtils.groupByUser(activeRows);
        final rows = <DataRow>[];

        for (var i = 0; i < groups.length; i++) {
          final group = groups[i];
          final user = group.user;
          final username = (user['username'] ?? 'N/A').toString();
          final status = (user['status'] ?? 'active').toString();
          final assignments = group.assignments;
          final roles = assignments
              .map((a) => (a['role'] ?? '').toString().trim())
              .where((r) => r.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
          final primaryRole =
              roles.isNotEmpty ? roles.first : (user['role'] ?? '');
          final actionTarget = <String, dynamic>{
            ...user,
            if (primaryRole.toString().isNotEmpty) 'role': primaryRole,
          };
          final roleText = roles.isEmpty
              ? EmployeeRoleUtils.label(primaryRole.toString())
              : roles.map(EmployeeRoleUtils.label).join(', ');
          final statusLabel = status == 'active' ? 'Aktif' : 'Tidak aktif';

          final menu = <PopupMenuEntry<String>>[
            const PopupMenuItem(
              value: 'detail',
              child: Text('Detail penugasan'),
            ),
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            const PopupMenuItem(
              value: 'toggle_status',
              child: Text('Ubah status'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Hapus')),
          ];

          final actionCell = DataCell(
            Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<String>(
                tooltip: 'Tindakan',
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  if (v == 'detail') {
                    onShowDetail(username, status, assignments);
                  } else {
                    onEmployeeAction(actionTarget, v);
                  }
                },
                itemBuilder: (context) => menu,
              ),
            ),
          );

          rows.add(
            DataRow(
              color: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.hovered)) {
                  return cs.primary.withValues(alpha: 0.06);
                }
                return i.isOdd
                    ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
                    : null;
              }),
              cells: narrow
                  ? [
                      DataCell(
                        Text(
                          username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          statusLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      actionCell,
                    ]
                  : [
                      DataCell(
                        Text(
                          username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      DataCell(Text(statusLabel)),
                      DataCell(
                        Text(
                          roleText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      actionCell,
                    ],
            ),
          );
        }

        Widget summaryRow(List<Widget> children) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          );
        }

        Widget summaryCard(int count, IconData icon, Color color) {
          return Expanded(
            child: EmployeeSummaryCard(count: count, icon: icon, color: color),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, pad, pad, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  narrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            summaryRow([
                              summaryCard(
                                EmployeeGroupUtils.countUniqueUsers(allRows),
                                Icons.people,
                                Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              summaryCard(
                                EmployeeGroupUtils.countUniqueUsersByStatus(
                                  allRows,
                                  'active',
                                ),
                                Icons.check_circle,
                                Colors.green,
                              ),
                            ]),
                            const SizedBox(height: 8),
                            summaryRow([
                              summaryCard(
                                EmployeeGroupUtils.countUniqueUsersByStatus(
                                  allRows,
                                  'inactive',
                                ),
                                Icons.cancel,
                                Colors.red,
                              ),
                              const SizedBox(width: 8),
                              summaryCard(
                                EmployeeGroupUtils.countUniqueUsersWithRole(
                                  activeRows,
                                  'cs',
                                ),
                                Icons.support_agent,
                                Colors.purple,
                              ),
                            ]),
                          ],
                        )
                      : summaryRow([
                          summaryCard(
                            EmployeeGroupUtils.countUniqueUsers(allRows),
                            Icons.people,
                            Colors.blue,
                          ),
                          SizedBox(width: narrow ? 8 : 16),
                          summaryCard(
                            EmployeeGroupUtils.countUniqueUsersByStatus(
                              allRows,
                              'active',
                            ),
                            Icons.check_circle,
                            Colors.green,
                          ),
                          SizedBox(width: narrow ? 8 : 16),
                          summaryCard(
                            EmployeeGroupUtils.countUniqueUsersByStatus(
                              allRows,
                              'inactive',
                            ),
                            Icons.cancel,
                            Colors.red,
                          ),
                          SizedBox(width: narrow ? 8 : 16),
                          summaryCard(
                            EmployeeGroupUtils.countUniqueUsersWithRole(
                              activeRows,
                              'cs',
                            ),
                            Icons.support_agent,
                            Colors.purple,
                          ),
                        ]),
                  const SizedBox(height: 12),
                  Text(
                    'Daftar karyawan aktif (${EmployeeGroupUtils.countUniqueUsers(activeRows)})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, 8),
                child: groups.isEmpty
                    ? const Center(child: Text('Belum ada data karyawan'))
                    : Material(
                        elevation: 0,
                        color: cs.surfaceContainerLow.withValues(alpha: 0.65),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.45),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Scrollbar(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: ConstrainedBox(
                                  constraints: tableBoxConstraints,
                                  child: DataTable(
                                    headingRowColor: WidgetStateProperty.all(
                                      cs.surfaceContainerHigh,
                                    ),
                                    dataRowMinHeight: narrow ? 40 : 44,
                                    dataRowMaxHeight: narrow ? 52 : 60,
                                    columnSpacing: narrow ? 8 : 14,
                                    horizontalMargin: narrow ? 8 : 12,
                                    showCheckboxColumn: false,
                                    dividerThickness: 0.5,
                                    columns: narrow
                                        ? [
                                            DataColumn(
                                              label: dataTableColumnLabel(
                                                'Nama',
                                              ),
                                            ),
                                            DataColumn(
                                              label: dataTableColumnLabel(
                                                'Status',
                                              ),
                                            ),
                                            const DataColumn(
                                              label: SizedBox(width: 44),
                                            ),
                                          ]
                                        : [
                                            DataColumn(
                                              label: dataTableColumnLabel(
                                                'Nama',
                                              ),
                                            ),
                                            DataColumn(
                                              label: dataTableColumnLabel(
                                                'Status',
                                              ),
                                            ),
                                            DataColumn(
                                              label: dataTableColumnLabel(
                                                'Role',
                                              ),
                                            ),
                                            const DataColumn(
                                              label: SizedBox(width: 48),
                                            ),
                                          ],
                                    rows: rows,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
