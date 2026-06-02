import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/modules/kasir/kasir_order_display.dart';

/// Tabel antrian bayar lebar penuh (dashboard kasir & halaman antrian).
class KasirPaymentQueueTable extends StatelessWidget {
  const KasirPaymentQueueTable({
    super.key,
    required this.orders,
    required this.width,
    this.maxHeight,
    required this.onOrderTap,
    this.cellPadding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.showOrderTypeColumn = true,
    this.decorated = true,
  });

  final List<Map<String, dynamic>> orders;
  final double width;
  final double? maxHeight;
  final void Function(Map<String, dynamic> order) onOrderTap;
  final EdgeInsets cellPadding;
  final bool showOrderTypeColumn;
  final bool decorated;

  static String orderNota(Map<String, dynamic> order) {
    final n = order['order_number']?.toString().trim() ?? '';
    return n.isEmpty ? '—' : n;
  }

  static String fmtMoney(num n) => NumberFormat.currency(
        locale: 'id_ID',
        symbol: 'Rp ',
        decimalDigits: 0,
      ).format(n);

  static num amountDue(Map<String, dynamic> order) {
    for (final k in const ['remaining_amount', 'amount']) {
      final v = order[k];
      if (v == null) continue;
      if (v is num) return v;
      final parsed = num.tryParse(v.toString());
      if (parsed != null) return parsed;
    }
    final t = order['total'];
    if (t is num) return t;
    return num.tryParse(t?.toString() ?? '0') ?? 0;
  }

  static String orderItemLabel(Map<String, dynamic> order) {
    final type = (order['order_type'] ?? '').toString().trim();
    final item = kasirOrderItemTitle(order);
    if (type.isEmpty || type == '—') return item;
    if (item == 'N/A') return type;
    return '$type $item';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderSide = BorderSide(
      color: cs.outlineVariant.withValues(alpha: 0.45),
      width: 0.5,
    );

    Widget headerCell(String label, {bool alignRight = false}) {
      return Padding(
        padding: cellPadding,
        child: Align(
          alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
          child: dataTableColumnLabel(label),
        ),
      );
    }

    Widget dataCell(
      String text, {
      TextStyle? style,
      int maxLines = 1,
      bool alignRight = false,
      VoidCallback? onTap,
    }) {
      final child = Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: style,
      );
      return Padding(
        padding: cellPadding,
        child: Align(
          alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
          child: onTap == null ? child : InkWell(onTap: onTap, child: child),
        ),
      );
    }

    final headerChildren = <Widget>[
      headerCell('No. Nota'),
      if (showOrderTypeColumn) headerCell('Order'),
      headerCell('Order Item'),
      headerCell('Jumlah', alignRight: true),
    ];

    final columnWidths = showOrderTypeColumn
        ? const {
            0: FlexColumnWidth(2.2),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(3.2),
            3: FlexColumnWidth(1.6),
          }
        : const {
            0: FlexColumnWidth(2.2),
            1: FlexColumnWidth(4.2),
            2: FlexColumnWidth(1.6),
          };

    final tableRows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(color: cs.surfaceContainerHigh),
        children: headerChildren,
      ),
    ];

    for (var i = 0; i < orders.length; i++) {
      final order = orders[i];
      if (order.isNotEmpty) normalizeKasirOrderMap(order);
      final pay = order.isEmpty ? null : () => onOrderTap(order);

      final dataChildren = <Widget>[
        dataCell(
          orderNota(order),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: AppTypography.tableCell,
          ),
          onTap: pay,
        ),
        if (showOrderTypeColumn)
          dataCell('${order['order_type'] ?? '—'}', onTap: pay),
        dataCell(
          showOrderTypeColumn
              ? kasirOrderItemTitle(order)
              : orderItemLabel(order),
          maxLines: 2,
          onTap: pay,
        ),
        dataCell(
          fmtMoney(amountDue(order)),
          alignRight: true,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: cs.primary,
            fontSize: AppTypography.tableCell,
          ),
          onTap: pay,
        ),
      ];

      tableRows.add(
        TableRow(
          decoration: BoxDecoration(
            color: i.isOdd
                ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
                : null,
          ),
          children: dataChildren,
        ),
      );
    }

    final table = Table(
      columnWidths: columnWidths,
      border: TableBorder(horizontalInside: borderSide),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: tableRows,
    );

    Widget scrollChild = maxHeight != null
        ? SizedBox(
            width: width,
            height: maxHeight,
            child: SingleChildScrollView(child: table),
          )
        : SizedBox(width: width, child: table);

    scrollChild = Scrollbar(child: scrollChild);

    if (!decorated) return scrollChild;

    return Material(
      elevation: 0,
      color: cs.surfaceContainerLow.withValues(alpha: 0.65),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: scrollChild,
    );
  }
}
