import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:vanessa3/utils/branch_logo_pdf.dart';

String _periodHeaderLine(DateTime from, DateTime to) {
  final fromL = DateTime(from.year, from.month, from.day);
  final toL = DateTime(to.year, to.month, to.day);
  if (fromL.year == toL.year &&
      fromL.month == toL.month &&
      fromL.day == toL.day) {
    return 'Periode: ${DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(fromL)}';
  }
  return 'Periode: ${DateFormat('dd MMM yyyy', 'id_ID').format(fromL)} – '
      '${DateFormat('dd MMM yyyy', 'id_ID').format(toL)}';
}

String _fileSlug(DateTime from, DateTime to) {
  final a = DateFormat('yyyy-MM-dd').format(from);
  final b = DateFormat('yyyy-MM-dd').format(to);
  return a == b ? a : '${a}_$b';
}

String _itemCode(Map<String, dynamic> i) =>
    (i['kode_produk'] ?? i['item_code'] ?? '-').toString();

int _qty(Map<String, dynamic> i) =>
    int.tryParse((i['quantity'] ?? i['qty'] ?? '0').toString()) ?? 0;

String _createdAt(Map<String, dynamic> i) {
  final v = i['created_at'];
  if (v == null) return '-';
  try {
    return DateFormat('dd/MM/yyyy HH:mm', 'id_ID')
        .format(DateTime.parse(v.toString()).toLocal());
  } catch (_) {
    return v.toString();
  }
}

/// Cetak PDF laporan input stok (user + cabang + periode, sama filter seperti layar).
Future<void> printStockistInputReportPdf(
  BuildContext context, {
  required DateTime fromDate,
  required DateTime toDate,
  required String branchLabel,
  required String branchIdForLogo,
  required String username,
  required int skuCount,
  required int totalQty,
  required List<Map<String, dynamic>> items,
  bool showCreatedByColumn = false,
}) async {
  if (!context.mounted) return;
  try {
    final logoBytes = await loadBranchLogoRasterBytesForPdf(branchIdForLogo);
    final doc = pw.Document();
    final rows = items.length > 120 ? items.sublist(0, 120) : items;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: pdfMultiPageHeaderLaporanCabang(
          title: 'LAPORAN INPUT STOK',
          leftLogoBytes: logoBytes,
          subtitles: [
            PdfLaporanHeaderSubtitleLine(_periodHeaderLine(fromDate, toDate)),
            PdfLaporanHeaderSubtitleLine(
              'Cabang: $branchLabel',
              fontSize: 11,
              color: PdfColors.grey700,
            ),
            PdfLaporanHeaderSubtitleLine(
              'Penginput: ${username.isEmpty ? '-' : username}',
              fontSize: 11,
              color: PdfColors.grey700,
            ),
          ],
        ),
        build: (ctx) => [
          pw.Text(
            'Ringkasan',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Jumlah SKU: $skuCount'),
          pw.Text('Total qty: $totalQty'),
          pw.SizedBox(height: 14),
          pw.Text(
            'Detail item',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (rows.isEmpty)
            pw.Text('Tidak ada item pada periode ini.')
          else
            pw.TableHelper.fromTextArray(
              headers: showCreatedByColumn
                  ? const ['Kode', 'Nama', 'Qty', 'Status', 'Penginput', 'Dibuat']
                  : const ['Kode', 'Nama', 'Qty', 'Status', 'Dibuat'],
              data: rows.map((i) {
                final name = (i['name'] ?? '-').toString();
                final shortName =
                    name.length > 42 ? '${name.substring(0, 39)}...' : name;
                final createdBy = (i['item_created_by_name'] ??
                        i['created_by_name'] ??
                        i['username'] ??
                        '-')
                    .toString();
                final base = [
                  _itemCode(i),
                  shortName,
                  '${_qty(i)}',
                  (i['status'] ?? '-').toString(),
                ];
                if (showCreatedByColumn) {
                  base.add(createdBy);
                }
                base.add(_createdAt(i));
                return base;
              }).toList(),
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              columnWidths: showCreatedByColumn
                  ? const {
                      0: pw.FlexColumnWidth(0.85),
                      1: pw.FlexColumnWidth(1.5),
                      2: pw.FlexColumnWidth(0.4),
                      3: pw.FlexColumnWidth(0.6),
                      4: pw.FlexColumnWidth(0.75),
                      5: pw.FlexColumnWidth(0.9),
                    }
                  : const {
                      0: pw.FlexColumnWidth(0.9),
                      1: pw.FlexColumnWidth(1.8),
                      2: pw.FlexColumnWidth(0.45),
                      3: pw.FlexColumnWidth(0.65),
                      4: pw.FlexColumnWidth(0.95),
                    },
            ),
          if (items.length > 120)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                'Catatan: PDF memuat 120 baris pertama dari ${items.length} item.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Dicetak: ${DateFormat('dd/MM/yyyy HH:mm', 'id_ID').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      name: 'laporan_input_stok_${_fileSlug(fromDate, toDate)}.pdf',
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
