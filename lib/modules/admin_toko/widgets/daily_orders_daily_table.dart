import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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

    Widget tableCell(Widget child, {bool numeric = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Align(
          alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        ),
      );
    }

    final headerStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 11,
          height: 1.15,
        );

    Widget tappableCell(
      Map<String, dynamic> row,
      Widget child, {
      bool numeric = false,
    }) {
      return InkWell(
        onTap: () => onOrderTap(row),
        child: tableCell(child, numeric: numeric),
      );
    }

    final tableRows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(color: Colors.grey.shade200),
        children: [
          tableCell(Text('No. Nota', style: headerStyle)),
          tableCell(Text('Order', style: headerStyle)),
          tableCell(Text('Item', style: headerStyle)),
          tableCell(Text('Total', style: headerStyle), numeric: true),
          tableCell(Text('Status', style: headerStyle)),
        ],
      ),
      for (var i = 0; i < lines.length; i++)
        TableRow(
          decoration: BoxDecoration(
            color: i.isOdd ? const Color(0xFFFFF8EE) : null,
          ),
          children: [
            tappableCell(
              lines[i],
              cell(displayOrderNumber(lines[i]), maxLines: 1),
            ),
            tappableCell(
              lines[i],
              cell((lines[i]['order_type'] ?? '—').toString(), maxLines: 1),
            ),
            tappableCell(
              lines[i],
              cell(lineItemName(lines[i]), maxLines: 1),
            ),
            tappableCell(
              lines[i],
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: cell(
                  orderTotalDisplayStr(lines[i]),
                  maxLines: 1,
                  align: TextAlign.end,
                ),
              ),
              numeric: true,
            ),
            tappableCell(lines[i], statusCellBuilder(lines[i])),
          ],
        ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.15),
          1: FlexColumnWidth(0.75),
          2: FlexColumnWidth(2.2),
          3: FlexColumnWidth(0.95),
          4: FlexColumnWidth(1.15),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder(
          horizontalInside: BorderSide(color: Colors.grey.shade300, width: 0.5),
        ),
        children: tableRows,
      ),
    );
  }
}
