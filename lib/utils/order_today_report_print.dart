import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

String _money(num v) =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
        .format(v);

String _dateSlug(DateTime d) => DateFormat('yyyy-MM-dd').format(d.toLocal());

double _toDouble(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

String _orderLabel(Map<String, dynamic> o) {
  final id = o['order_id']?.toString().trim();
  final num = o['order_number']?.toString().trim();
  if (num != null && num.isNotEmpty) return num;
  if (id != null && id.isNotEmpty) return '#$id';
  return '-';
}

String _orderCustomer(Map<String, dynamic> o) =>
    (o['customer_name'] ?? o['customer'] ?? '-').toString();

String _orderType(Map<String, dynamic> o) =>
    (o['order_type'] ?? o['type'] ?? '-').toString();

double _orderRoundedTotal(Map<String, dynamic> o) {
  // Prefer jumlah (rounded). Fallback total.
  final raw = o['jumlah'] ?? o['total'] ?? 0;
  return _toDouble(raw);
}

/// Cetak laporan Order Today (ringkasan + daftar order).
Future<void> printOrderTodayReportPdf(
  BuildContext context, {
  required DateTime reportDate,
  required String branchLabel,
  required Map<String, int> ordersByType,
  Map<String, int>? ordersByMode,
  required int totalOrders,
  required int pendingOrders,
  required int completedOrders,
  required double revenueJualCompleted,
  required double expenseBuybackCompleted,
  required double netRevenue,
  required List<Map<String, dynamic>> orders,
}) async {
  if (!context.mounted) return;
  try {
    int modeN(String k) => ordersByMode?[k] ?? 0;

    final doc = pw.Document();
    final dateLabel = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(reportDate);

    final rows = orders.length > 120 ? orders.sublist(0, 120) : orders;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) => [
          pw.Center(
            child: pw.Text(
              'ORDER TODAY',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Center(child: pw.Text(dateLabel, style: const pw.TextStyle(fontSize: 12))),
          pw.SizedBox(height: 16),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 12),
          pw.Text('Cabang: $branchLabel'),
          pw.SizedBox(height: 10),
          pw.Text(
            'Ringkasan',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Total order: $totalOrders'),
          pw.Text('Pending: $pendingOrders'),
          pw.Text('Selesai: $completedOrders'),
          pw.SizedBox(height: 8),
          pw.Text('Revenue jual (completed): ${_money(revenueJualCompleted)}'),
          pw.Text('Buyback (keluar) (completed): ${_money(expenseBuybackCompleted)}'),
          pw.Text('Net: ${_money(netRevenue)}'),
          pw.SizedBox(height: 12),
          pw.Text(
            'Order per mode',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Bullet(text: 'Toko: ${modeN('toko')}'),
          pw.Bullet(text: 'Online: ${modeN('online')}'),
          pw.SizedBox(height: 12),
          pw.Text(
            'Order per jenis',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Bullet(text: 'Jual: ${ordersByType['jual'] ?? 0}'),
          pw.Bullet(text: 'Buyback: ${ordersByType['buyback'] ?? 0}'),
          pw.Bullet(text: 'Service: ${ordersByType['service'] ?? 0}'),
          pw.Bullet(text: 'Custom: ${ordersByType['custom'] ?? 0}'),
          pw.SizedBox(height: 14),
          pw.Text(
            'Daftar order (maks 120 baris)',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (rows.isEmpty)
            pw.Text('Tidak ada order.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Order', 'Jenis', 'Customer', 'Total'],
              data: rows.map((o) {
                final t = _orderRoundedTotal(o);
                return [
                  _orderLabel(o),
                  _orderType(o),
                  _orderCustomer(o),
                  t == 0 ? '—' : _money(t),
                ];
              }).toList(),
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.2),
                1: pw.FlexColumnWidth(0.8),
                2: pw.FlexColumnWidth(1.6),
                3: pw.FlexColumnWidth(1.0),
              },
            ),
        ],
      ),
    );

    await Printing.layoutPdf(
      name: 'order_today_${_dateSlug(reportDate)}.pdf',
      onLayout: (format) async => doc.save(),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak laporan: $e')),
      );
    }
  }
}

