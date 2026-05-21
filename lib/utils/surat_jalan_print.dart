import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:vanessa3/utils/branch_logo_pdf.dart';

Future<void> printSuratJalanTransfer(
  BuildContext context, {
  required Map<String, dynamic> transfer,
  required String fromBranchName,
  required String toBranchName,
  String fromBranchIdForLogo = '',
}) async {
  try {
    // Satu banner cabang pengirim saja — asset logo cabang lebar penuh (bukan ikon kecil).
    final logoBytes = await loadBranchLogoRasterBytesForPdf(fromBranchIdForLogo);
    final doc = pw.Document();

    String dateStr(dynamic created) {
      if (created == null) return '-';
      try {
        return DateTime.parse(created.toString())
            .toLocal()
            .toString()
            .split('.')
            .first;
      } catch (_) {
        return created.toString();
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: pdfMultiPageHeaderLaporanCabang(
          title: 'SURAT JALAN',
          leftLogoBytes: logoBytes,
        ),
        build: (ctx) => [
          pw.Text('No Transfer: ${transfer['transfer_id'] ?? '-'}'),
          pw.Text('Tanggal: ${dateStr(transfer['created_at'])}'),
          pw.SizedBox(height: 12),
          pw.Text('Dari: $fromBranchName'),
          pw.Text('Ke: $toBranchName'),
          pw.Text('Kurir: ${(transfer['courier'] ?? '-').toString()}'),
          pw.SizedBox(height: 16),
          pw.Text(
            'Barang',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const ['Item', 'Qty', 'Catatan'],
            data: [
              [
                (transfer['item_name'] ?? '-').toString(),
                (transfer['quantity'] ?? '-').toString(),
                (transfer['notes'] ?? '').toString(),
              ],
            ],
            cellAlignment: pw.Alignment.centerLeft,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          ),
          pw.SizedBox(height: 28),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                children: [
                  pw.Text('Pengirim'),
                  pw.SizedBox(height: 48),
                  pw.Text('(....................)'),
                ],
              ),
              pw.Column(
                children: [
                  pw.Text('Penerima'),
                  pw.SizedBox(height: 48),
                  pw.Text('(....................)'),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      name: 'surat_jalan_${transfer['transfer_id'] ?? 'transfer'}.pdf',
      onLayout: (format) async => doc.save(),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak surat jalan: $e')),
      );
    }
  }
}

Future<void> printSuratJalanTransfers(
  BuildContext context, {
  required List<Map<String, dynamic>> transfers,
  required String fromBranchName,
  required String toBranchName,
  required String fromBranchIdForLogo,
  required String courier,
  String notes = '',
}) async {
  if (transfers.isEmpty) return;

  try {
    final logoBytes = await loadBranchLogoRasterBytesForPdf(fromBranchIdForLogo);
    final doc = pw.Document();

    String dateStr(dynamic created) {
      if (created == null) return '-';
      try {
        return DateTime.parse(created.toString())
            .toLocal()
            .toString()
            .split('.')
            .first;
      } catch (_) {
        return created.toString();
      }
    }

    final transferIds = transfers
        .map((t) => t['transfer_id']?.toString())
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList();

    final createdAt = transfers
        .map((t) => t['created_at'])
        .firstWhere((v) => v != null, orElse: () => null);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: pdfMultiPageHeaderLaporanCabang(
          title: 'SURAT JALAN',
          leftLogoBytes: logoBytes,
        ),
        build: (ctx) => [
          pw.Text(
            'No Transfer: ${transferIds.isEmpty ? '-' : transferIds.join(', ')}',
          ),
          pw.Text('Tanggal: ${dateStr(createdAt)}'),
          pw.SizedBox(height: 12),
          pw.Text('Dari: $fromBranchName'),
          pw.Text('Ke: $toBranchName'),
          pw.Text('Kurir: ${courier.isEmpty ? '-' : courier}'),
          if (notes.trim().isNotEmpty) pw.Text('Catatan: ${notes.trim()}'),
          pw.SizedBox(height: 16),
          pw.Text(
            'Barang',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const ['Item', 'Qty'],
            data: transfers
                .map(
                  (t) => [
                    (t['item_name'] ?? '-').toString(),
                    (t['quantity'] ?? '-').toString(),
                  ],
                )
                .toList(),
            cellAlignment: pw.Alignment.centerLeft,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          ),
          pw.SizedBox(height: 28),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                children: [
                  pw.Text('Pengirim'),
                  pw.SizedBox(height: 48),
                  pw.Text('(....................)'),
                ],
              ),
              pw.Column(
                children: [
                  pw.Text('Penerima'),
                  pw.SizedBox(height: 48),
                  pw.Text('(....................)'),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      name: 'surat_jalan_${transferIds.isEmpty ? 'transfer' : transferIds.first}.pdf',
      onLayout: (format) async => doc.save(),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak surat jalan: $e')),
      );
    }
  }
}

