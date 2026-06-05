import 'package:flutter/material.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/modules/admin_workshop/logic/workshop_orders_utils.dart';

class WorkshopOrdersDataTable extends StatelessWidget {
  const WorkshopOrdersDataTable({
    super.key,
    required this.orders,
    required this.role,
    required this.onAction,
  });

  final List<dynamic> orders;
  final String role;
  final void Function(dynamic order, String action) onAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 600;
        final cs = Theme.of(context).colorScheme;
        const desktopW = 960.0;
        final w = constraints.maxWidth;
        final BoxConstraints box;
        if (narrow) {
          box = BoxConstraints.tightFor(width: w);
        } else if (w >= desktopW) {
          box = BoxConstraints.tightFor(width: desktopW);
        } else {
          box = const BoxConstraints(minWidth: desktopW);
        }

        final rows = <DataRow>[];
        for (var i = 0; i < orders.length; i++) {
          final order = orders[i];
          final oid = (order['order_id'] ?? '—').toString();
          final cust = (order['customer_name'] ?? 'N/A').toString();
          final item =
              (order['item_name'] ?? order['nama_item'] ?? 'N/A').toString();
          final tech =
              (order['technician_name'] ?? 'Belum diassign').toString();
          final st = order['status'];
          final stLabel = WorkshopOrdersUtils.statusLabel(st);
          final stColor = WorkshopOrdersUtils.statusColor(st);
          final menu = DataCell(
            Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'Tindakan',
                onSelected: (action) => onAction(order, action),
                itemBuilder: (context) => [
                  if (role == 'tukang')
                    const PopupMenuItem(
                      value: 'start_work',
                      child: Text('Mulai kerja'),
                    ),
                  if (const {
                    'admin_workshop',
                    'superadmin',
                    'manajer',
                  }.contains(role))
                    const PopupMenuItem(
                      value: 'assign_technician',
                      child: Text('Assign tukang'),
                    ),
                  const PopupMenuItem(
                    value: 'cost_breakdown',
                    child: Text('Biaya aktual (tagihan)'),
                  ),
                  const PopupMenuItem(
                    value: 'update_status',
                    child: Text('Update status'),
                  ),
                  const PopupMenuItem(
                    value: 'view_details',
                    child: Text('Lihat detail'),
                  ),
                ],
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '#$oid · $cust',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              stLabel,
                              style: TextStyle(
                                fontSize: 11,
                                color: stColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      menu,
                    ]
                  : [
                      DataCell(Text('#$oid')),
                      DataCell(
                        Text(
                          cust,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DataCell(
                        Text(
                          item,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DataCell(
                        Text(
                          tech,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DataCell(
                        Text(
                          stLabel,
                          style: TextStyle(
                            color: stColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      menu,
                    ],
            ),
          );
        }

        return Material(
          elevation: 0,
          color: cs.surfaceContainerLow.withValues(alpha: 0.65),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
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
                    constraints: box,
                    child: DataTable(
                      headingRowColor:
                          WidgetStateProperty.all(cs.surfaceContainerHigh),
                      dataRowMinHeight: narrow ? 52 : 48,
                      dataRowMaxHeight: narrow ? 72 : 56,
                      columnSpacing: narrow ? 8 : 12,
                      horizontalMargin: narrow ? 8 : 12,
                      showCheckboxColumn: false,
                      dividerThickness: 0.5,
                      columns: narrow
                          ? [
                              DataColumn(
                                label: dataTableColumnLabel('Order'),
                              ),
                              const DataColumn(label: SizedBox(width: 44)),
                            ]
                          : [
                              DataColumn(
                                label: dataTableColumnLabel('Order'),
                              ),
                              DataColumn(
                                label: dataTableColumnLabel('Pelanggan'),
                              ),
                              DataColumn(
                                label: dataTableColumnLabel('Item'),
                              ),
                              DataColumn(
                                label: dataTableColumnLabel('Tukang'),
                              ),
                              DataColumn(
                                label: dataTableColumnLabel('Status'),
                              ),
                              const DataColumn(label: SizedBox(width: 48)),
                            ],
                      rows: rows,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
