import 'package:flutter/material.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/modules/cs/logic/customers_utils.dart';
import 'package:vanessa3/modules/cs/widgets/customers_summary_metric_card.dart';
import 'package:vanessa3/providers/customers_provider.dart';

class CustomersDataTable extends StatelessWidget {
  const CustomersDataTable({
    super.key,
    required this.customersState,
    required this.role,
    required this.onAction,
  });

  final CustomersState customersState;
  final String role;
  final void Function(String action, Map<String, dynamic> customer) onAction;

  TextStyle _mobileRowTextStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium;
    return (base ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
  }

  TextStyle _desktopRowTextStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium;
    return (base ?? const TextStyle()).copyWith(height: 1.25);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final withEmail = customersState.customers
        .where(
          (c) =>
              c['email'] != null && c['email'].toString().trim().isNotEmpty,
        )
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 600;
        const desktopTableWidth = 840.0;
        final panelW = constraints.maxWidth;
        final BoxConstraints tableBoxConstraints;
        if (narrow) {
          tableBoxConstraints = BoxConstraints.tightFor(width: panelW);
        } else if (panelW >= desktopTableWidth) {
          tableBoxConstraints =
              BoxConstraints.tightFor(width: desktopTableWidth);
        } else {
          tableBoxConstraints =
              const BoxConstraints(minWidth: desktopTableWidth);
        }
        final mobileStyle = _mobileRowTextStyle(context);
        final desktopStyle = _desktopRowTextStyle(context);

        final columns = narrow
            ? <DataColumn>[
                DataColumn(label: dataTableColumnLabel('Nama')),
                DataColumn(label: dataTableColumnLabel('Alamat')),
                DataColumn(label: dataTableColumnLabel('Telepon')),
                const DataColumn(label: SizedBox(width: 44)),
              ]
            : <DataColumn>[
                DataColumn(label: dataTableColumnLabel('Nama')),
                DataColumn(label: dataTableColumnLabel('Email')),
                DataColumn(label: dataTableColumnLabel('Telepon')),
                DataColumn(label: dataTableColumnLabel('Alamat')),
                const DataColumn(label: SizedBox(width: 48)),
              ];

        final menuEntries = CustomersUtils.customerMenuEntries(context, role);
        final rows = <DataRow>[];
        for (var i = 0; i < customersState.customers.length; i++) {
          final customer = customersState.customers[i];
          final name = CustomersUtils.cellStr(customer['name']);
          final email = CustomersUtils.cellStr(customer['email']);
          final phone = CustomersUtils.cellStr(customer['phone']);
          final address = CustomersUtils.cellStr(customer['address']);

          final actionCell = menuEntries.isEmpty
              ? DataCell(
                  Text(
                    '—',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                )
              : DataCell(
                  Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<String>(
                      tooltip: 'Tindakan',
                      icon: const Icon(Icons.more_vert),
                      onSelected: (action) => onAction(action, customer),
                      itemBuilder: (context) => menuEntries,
                    ),
                  ),
                );

          final cells = narrow
              ? <DataCell>[
                  DataCell(
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mobileStyle.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataCell(
                    Text(
                      address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: mobileStyle,
                    ),
                  ),
                  DataCell(
                    Text(
                      phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mobileStyle,
                    ),
                  ),
                  actionCell,
                ]
              : <DataCell>[
                  DataCell(
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: desktopStyle.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataCell(
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: desktopStyle.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: desktopStyle,
                    ),
                  ),
                  DataCell(
                    Text(
                      address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: desktopStyle.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.2,
                      ),
                    ),
                  ),
                  actionCell,
                ];

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
              cells: cells,
            ),
          );
        }

        final pad = narrow ? 12.0 : 16.0;
        final cardGap = narrow ? 8.0 : 12.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: CustomersSummaryMetricCard(
                        compact: narrow,
                        icon: Icons.people_rounded,
                        accent: cs.primary,
                        label: 'Total pelanggan',
                        value: '${customersState.customers.length}',
                      ),
                    ),
                    SizedBox(width: cardGap),
                    Expanded(
                      child: CustomersSummaryMetricCard(
                        compact: narrow,
                        icon: Icons.mark_email_read_rounded,
                        accent: Colors.green.shade700,
                        label: 'Dengan email',
                        value: '$withEmail',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 8),
              child: Text(
                'Daftar pelanggan (${customersState.customers.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, 4),
                child: Material(
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
                              dataRowMaxHeight: narrow ? 62 : 60,
                              columnSpacing: narrow ? 8 : 12,
                              horizontalMargin: narrow ? 8 : 10,
                              showCheckboxColumn: false,
                              dividerThickness: 0.5,
                              columns: columns,
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
