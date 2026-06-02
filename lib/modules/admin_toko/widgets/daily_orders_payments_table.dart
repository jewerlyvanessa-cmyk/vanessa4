import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/modules/admin_toko/utils/daily_orders_payments_helpers.dart';
import 'package:vanessa3/utils/order_status_ui.dart';
import 'package:vanessa3/utils/payment_order_flow.dart';

/// Tabel pembayaran harian (selaras tab Pembayaran di halaman admin toko).
class DailyOrdersPaymentsTable extends StatelessWidget {
  const DailyOrdersPaymentsTable({
    super.key,
    required this.transactions,
    required this.ordersRaw,
    required this.serviceCustomMode,
  });

  final List<Map<String, dynamic>> transactions;
  final List<dynamic> ordersRaw;
  final bool serviceCustomMode;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return Center(
        child: Text(
          serviceCustomMode
              ? 'Tidak ada pembayaran untuk order Service/Custom hari ini'
              : 'Tidak ada pembayaran',
        ),
      );
    }

    final orderById = orderByIdDeduped(ordersRaw);

    final columns = <DataColumn>[
      DataColumn(label: dataTableColumnLabel('No. order')),
      DataColumn(label: dataTableColumnLabel('Jenis order')),
      DataColumn(label: dataTableColumnLabel('Nama item')),
      DataColumn(
        numeric: true,
        label: dataTableColumnLabel('Jumlah', numeric: true),
      ),
      DataColumn(label: dataTableColumnLabel('Status')),
    ];

    final rows = transactions.map((p) {
      final oid = p['order_id']?.toString() ?? '';
      final order = orderById[oid];
      final no = dailyOrderItemFieldStr(p, const [
        'order_number',
        'nota_order',
      ]).trim();
      final displayPayNo = no != '—'
          ? no
          : displayOrderNumber(order ?? const {});
      final orderType = (order?['order_type'] ?? p['order_type'] ?? '—')
          .toString();
      final statusRaw = order?['status']?.toString();
      final amt = dailyOrdersToNum(p['amount']);
      final isOut = paymentIsExpenseOrderType(orderType);
      final amtStyle = TextStyle(
        fontSize: 12,
        height: 1.2,
        color: isOut ? Colors.red.shade700 : Colors.green.shade800,
        fontWeight: isOut ? FontWeight.w700 : FontWeight.w600,
      );
      return DataRow(
        cells: [
          DataCell(
            Text(
              displayPayNo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, height: 1.2),
            ),
          ),
          DataCell(
            Text(
              isOut ? '$orderType · keluar' : orderType,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                color: isOut ? Colors.red.shade700 : null,
              ),
            ),
          ),
          DataCell(
            Text(
              (p['nama_item'] ?? '-').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, height: 1.2),
            ),
          ),
          DataCell(
            Text(
              isOut ? '− ${fmtDailyOrderMoney(amt)}' : fmtDailyOrderMoney(amt),
              style: amtStyle,
            ),
          ),
          DataCell(
            Text(
              statusRaw != null && statusRaw.isNotEmpty
                  ? orderStatusLabel(statusRaw)
                  : '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: OrderStatusUi.color(statusRaw),
                fontWeight: FontWeight.w600,
                fontSize: 12,
                height: 1.2,
              ),
            ),
          ),
        ],
      );
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final minW = kIsWeb
            ? (640.0 > constraints.maxWidth ? 640.0 : constraints.maxWidth)
            : constraints.maxWidth;
        final table = DataTable(
          headingRowHeight: 34,
          dataRowMinHeight: 32,
          dataRowMaxHeight: 44,
          columnSpacing: kIsWeb ? 10 : 12,
          horizontalMargin: kIsWeb ? 8 : 16,
          headingRowColor: kIsWeb
              ? WidgetStateProperty.all(Colors.grey.shade200)
              : null,
          dataRowColor: WidgetStateProperty.all(const Color(0xFFFFF8EE)),
          showCheckboxColumn: false,
          columns: columns,
          rows: rows,
        );

        final scrolls = SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minW),
              child: table,
            ),
          ),
        );

        if (kIsWeb) {
          return Scrollbar(child: scrolls);
        }
        return scrolls;
      },
    );
  }
}
