import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/modules/admin_toko/utils/daily_orders_payments_helpers.dart';
import 'package:vanessa3/utils/order_bill_amount.dart';

/// Tabel daftar order harian (mobile: dedupe per order, web: satu baris per item).
class DailyOrdersDailyTable extends StatelessWidget {
  const DailyOrdersDailyTable({
    super.key,
    required this.ordersRaw,
    required this.filteredTableRaw,
    required this.emptyHint,
    required this.emptyFilterMessage,
    required this.onOrderTap,
    required this.statusCellBuilder,
    required this.filterDeduped,
  });

  final List<dynamic> ordersRaw;
  final List<dynamic> filteredTableRaw;
  final String emptyHint;
  final String emptyFilterMessage;
  final void Function(Map<String, dynamic> order) onOrderTap;
  final Widget Function(Map<String, dynamic> row) statusCellBuilder;
  final List<Map<String, dynamic>> Function(List<Map<String, dynamic>> deduped)
      filterDeduped;

  @override
  Widget build(BuildContext context) {
    if (ordersRaw.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }
    if (filteredTableRaw.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyFilterMessage,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (kIsWeb) {
      return _OrdersTableWeb(
        ordersRaw: filteredTableRaw,
        onOrderTap: onOrderTap,
        statusCellBuilder: statusCellBuilder,
      );
    }
    return _OrdersTableMobile(
      ordersRaw: filteredTableRaw,
      onOrderTap: onOrderTap,
      statusCellBuilder: statusCellBuilder,
      filterDeduped: filterDeduped,
    );
  }
}

class _OrdersTableMobile extends StatelessWidget {
  const _OrdersTableMobile({
    required this.ordersRaw,
    required this.onOrderTap,
    required this.statusCellBuilder,
    required this.filterDeduped,
  });

  final List<dynamic> ordersRaw;
  final void Function(Map<String, dynamic> order) onOrderTap;
  final Widget Function(Map<String, dynamic> row) statusCellBuilder;
  final List<Map<String, dynamic>> Function(List<Map<String, dynamic>> deduped)
      filterDeduped;

  @override
  Widget build(BuildContext context) {
    final orders = filterDeduped(dedupeOrdersById(ordersRaw));
    if (orders.isEmpty) {
      return const Center(child: Text('Tidak ada order'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(Colors.grey.shade200),
                dataRowColor: WidgetStateProperty.all(const Color(0xFFFFF8EE)),
                headingRowHeight: 34,
                dataRowMinHeight: 32,
                dataRowMaxHeight: 44,
                columnSpacing: 12,
                horizontalMargin: 12,
                columns: const [
                  DataColumn(
                    label: Text(
                      'No. Nota',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        height: 1.1,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Order',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        height: 1.1,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Item',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        height: 1.1,
                      ),
                    ),
                  ),
                  DataColumn(
                    numeric: true,
                    label: Text(
                      'Total',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        height: 1.1,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Status',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
                rows: orders.map((o) {
                  final no = displayOrderNumber(o);
                  final total = orderBillAmountFromRow(o);
                  void openRow() => onOrderTap(o);
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(no, style: const TextStyle(fontSize: 12, height: 1.2)),
                        onTap: openRow,
                      ),
                      DataCell(
                        Text(
                          (o['order_type'] ?? '-').toString(),
                          style: const TextStyle(fontSize: 12, height: 1.2),
                        ),
                        onTap: openRow,
                      ),
                      DataCell(
                        Text(
                          (o['nama_item'] ?? '-').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, height: 1.2),
                        ),
                        onTap: openRow,
                      ),
                      DataCell(
                        Text(
                          fmtDailyOrderMoney(total),
                          style: const TextStyle(fontSize: 12, height: 1.2),
                        ),
                        onTap: openRow,
                      ),
                      DataCell(
                        statusCellBuilder(o),
                        onTap: openRow,
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OrdersTableWeb extends StatelessWidget {
  const _OrdersTableWeb({
    required this.ordersRaw,
    required this.onOrderTap,
    required this.statusCellBuilder,
  });

  final List<dynamic> ordersRaw;
  final void Function(Map<String, dynamic> order) onOrderTap;
  final Widget Function(Map<String, dynamic> row) statusCellBuilder;

  @override
  Widget build(BuildContext context) {
    final lines = rawOrderLineRows(ordersRaw);
    if (lines.isEmpty) {
      return const Center(child: Text('Tidak ada order'));
    }

    Widget cell(
      String text, {
      int maxLines = 2,
      TextAlign align = TextAlign.start,
    }) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 12,
              height: 1.2,
            ),
      );
    }

    final rows = <DataRow>[];
    for (final row in lines) {
      final no = displayOrderNumber(row);
      rows.add(
        DataRow(
          onSelectChanged: (_) => onOrderTap(row),
          cells: [
            DataCell(cell(no, maxLines: 1)),
            DataCell(cell((row['order_type'] ?? '—').toString(), maxLines: 1)),
            DataCell(cell(lineItemName(row), maxLines: 1)),
            DataCell(
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: cell(
                  orderTotalDisplayStr(row),
                  maxLines: 1,
                  align: TextAlign.end,
                ),
              ),
            ),
            DataCell(statusCellBuilder(row)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(Colors.grey.shade200),
                  dataRowColor: WidgetStateProperty.all(const Color(0xFFFFF8EE)),
                  headingRowHeight: 34,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 44,
                  columnSpacing: 10,
                  horizontalMargin: 8,
                  showCheckboxColumn: false,
                  columns: [
                    DataColumn(label: dataTableColumnLabel('No. Nota')),
                    DataColumn(label: dataTableColumnLabel('Order')),
                    DataColumn(label: dataTableColumnLabel('Item')),
                    DataColumn(
                      label: dataTableColumnLabel('Total'),
                      numeric: true,
                    ),
                    DataColumn(label: dataTableColumnLabel('Status')),
                  ],
                  rows: rows,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
