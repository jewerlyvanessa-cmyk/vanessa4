import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:vanessa3/utils/branch_logo_pdf.dart';
import 'package:vanessa3/utils/order_status_ui.dart';

String _money(num v) =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
        .format(v);

String _dateSlug(DateTime d) => DateFormat('yyyy-MM-dd').format(d.toLocal());

String _orderNota(Map<String, dynamic> row) {
  final n = row['order_number']?.toString().trim();
  if (n != null && n.isNotEmpty) return n;
  final legacy = row['nota_order']?.toString().trim();
  if (legacy != null && legacy.isNotEmpty) return legacy;
  final id = row['order_id']?.toString().trim();
  if (id != null && id.isNotEmpty) return id;
  return '—';
}

String _orderItemName(Map<String, dynamic> row, {required bool lineItems}) {
  if (lineItems) {
    for (final k in ['nama_item', 'item_name', 'name']) {
      final v = row[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return '—';
  }
  return (row['nama_item'] ?? '—').toString();
}

num _orderTotal(Map<String, dynamic> row, {required bool lineItems}) {
  if (lineItems) {
    final raw = row['item_total'] ?? row['line_total'];
    if (raw != null) {
      final n = raw is num ? raw : num.tryParse(raw.toString());
      if (n != null && n > 0) return n;
    }
  }
  final j = row['jumlah'] ?? row['total'];
  if (j is num) return j;
  return num.tryParse(j?.toString() ?? '') ?? 0;
}

String _paymentMethodLabel(String method) {
  switch (method.trim().toLowerCase()) {
    case 'cash':
      return 'Tunai';
    case 'transfer':
      return 'Transfer';
    case 'qris':
      return 'QRIS';
    case 'ewallet':
    case 'e-wallet':
      return 'E-Wallet';
    default:
      return method.isEmpty ? '—' : method;
  }
}

/// Cetak PDF laporan Order & Pembayaran (filter & tanggal sama seperti layar).
Future<void> printDailyOrdersPaymentsReportPdf(
  BuildContext context, {
  required DateTime reportDate,
  required String branchLabel,
  required String branchIdForLogo,
  required String reportTitle,
  String? filterDescription,
  String? userLabel,
  required bool ordersOnly,
  required int totalOrders,
  required int completedOrders,
  required int pendingOrders,
  required int tokoCount,
  required int onlineCount,
  required num paymentTotal,
  required int paymentTrxCount,
  required List<Map<String, dynamic>> orderRows,
  required bool orderRowsAreLineItems,
  List<Map<String, dynamic>>? paymentRows,
}) async {
  if (!context.mounted) return;

  try {
    final logoBytes = await loadBranchLogoRasterBytesForPdf(branchIdForLogo);
    final dateLabel =
        DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(reportDate);
    final printedAt =
        DateFormat('dd/MM/yyyy HH:mm', 'id_ID').format(DateTime.now());

    final orderTable = orderRows.length > 120
        ? orderRows.sublist(0, 120)
        : orderRows;
    final payTable = paymentRows == null
        ? <Map<String, dynamic>>[]
        : (paymentRows.length > 80
            ? paymentRows.sublist(0, 80)
            : paymentRows);

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: pdfMultiPageHeaderLaporanCabang(
          title: reportTitle.toUpperCase(),
          leftLogoBytes: logoBytes,
          subtitles: [
            PdfLaporanHeaderSubtitleLine(dateLabel),
            PdfLaporanHeaderSubtitleLine(
              'Cabang: $branchLabel',
              fontSize: 11,
              color: PdfColors.grey700,
            ),
            if (userLabel != null && userLabel.trim().isNotEmpty)
              PdfLaporanHeaderSubtitleLine(
                userLabel.trim(),
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            if (filterDescription != null && filterDescription.trim().isNotEmpty)
              PdfLaporanHeaderSubtitleLine(
                'Filter: ${filterDescription.trim()}',
                fontSize: 10,
                color: PdfColors.grey700,
              ),
          ],
        ),
        build: (ctx) {
          final blocks = <pw.Widget>[
            pw.Text(
              'Ringkasan',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text('Total order: $totalOrders'),
            pw.Text('Selesai: $completedOrders · Pending: $pendingOrders'),
            pw.Text('Toko: $tokoCount · Online: $onlineCount'),
            if (!ordersOnly) ...[
              pw.SizedBox(height: 4),
              pw.Text('Pembayaran: ${_money(paymentTotal)} ($paymentTrxCount trx)'),
            ],
            pw.SizedBox(height: 14),
            pw.Text(
              'Daftar order',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            if (orderTable.isEmpty)
              pw.Text('Tidak ada order pada filter ini.')
            else
              pw.TableHelper.fromTextArray(
                headers: const ['No. Nota', 'Order', 'Item', 'Total', 'Status'],
                data: orderTable.map((o) {
                  final total = _orderTotal(
                    o,
                    lineItems: orderRowsAreLineItems,
                  );
                  return [
                    _orderNota(o),
                    (o['order_type'] ?? '—').toString(),
                    _orderItemName(o, lineItems: orderRowsAreLineItems),
                    total == 0 ? '—' : _money(total),
                    OrderStatusUi.label(o['status']?.toString()),
                  ];
                }).toList(),
                cellAlignment: pw.Alignment.centerLeft,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey300),
                cellStyle: const pw.TextStyle(fontSize: 9),
                columnWidths: const {
                  0: pw.FlexColumnWidth(1.1),
                  1: pw.FlexColumnWidth(0.7),
                  2: pw.FlexColumnWidth(1.5),
                  3: pw.FlexColumnWidth(0.85),
                  4: pw.FlexColumnWidth(0.9),
                },
              ),
            if (orderRows.length > 120)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 6),
                child: pw.Text(
                  'Catatan: PDF memuat 120 baris pertama dari ${orderRows.length} baris order.',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
          ];

          if (!ordersOnly) {
            blocks.addAll([
              pw.SizedBox(height: 16),
              pw.Text(
                'Daftar pembayaran',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              if (payTable.isEmpty)
                pw.Text('Tidak ada pembayaran pada tanggal ini.')
              else
                pw.TableHelper.fromTextArray(
                  headers: const [
                    'No. Nota',
                    'Jenis',
                    'Item',
                    'Nominal',
                    'Metode',
                  ],
                  data: payTable.map((p) {
                    final amt = p['amount'];
                    final n = amt is num
                        ? amt
                        : num.tryParse(amt?.toString() ?? '') ?? 0;
                    return [
                      _orderNota(p),
                      (p['order_type'] ?? '—').toString(),
                      (p['nama_item'] ?? '—').toString(),
                      n == 0 ? '—' : _money(n),
                      _paymentMethodLabel(
                        (p['payment_method'] ?? p['method'] ?? '').toString(),
                      ),
                    ];
                  }).toList(),
                  cellAlignment: pw.Alignment.centerLeft,
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  headerDecoration:
                      const pw.BoxDecoration(color: PdfColors.grey300),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.0),
                    1: pw.FlexColumnWidth(0.65),
                    2: pw.FlexColumnWidth(1.2),
                    3: pw.FlexColumnWidth(0.85),
                    4: pw.FlexColumnWidth(0.7),
                  },
                ),
              if (paymentRows != null && paymentRows.length > 80)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 6),
                  child: pw.Text(
                    'Catatan: PDF memuat 80 transaksi pertama dari ${paymentRows.length}.',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey700,
                    ),
                  ),
                ),
            ]);
          }

          blocks.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 10),
              child: pw.Text(
                'Dicetak: $printedAt',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            ),
          );

          return blocks;
        },
      ),
    );

    await Printing.layoutPdf(
      name: 'laporan_order_bayar_${_dateSlug(reportDate)}.pdf',
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
