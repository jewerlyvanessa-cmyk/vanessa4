import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Konversi cm → point PDF (72 pt = 1 inch, 2,54 cm = 1 inch).
double _pdfCmToPoints(double cm) => cm * 72.0 / 2.54;

/// Isi QR: kode produk (untuk scan di kasir), fallback `item_id`.
String stockItemQrPayload(Map<String, dynamic> item) {
  final k = (item['kode_produk'] ?? item['item_code'] ?? '').toString().trim();
  if (k.isNotEmpty) return k;
  final id = item['item_id'];
  if (id != null) return id.toString();
  return '';
}

pw.Widget _stockQrLabelPageContent({
  required String qrPayload,
  required String titleLine,
}) {
  final displayTitle =
      titleLine.trim().isNotEmpty ? titleLine.trim() : 'Label stok';
  final qrSizePt = _pdfCmToPoints(1.0);
  return pw.Center(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(24),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 1),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            displayTitle,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: qrPayload,
            width: qrSizePt,
            height: qrSizePt,
          ),
          pw.SizedBox(height: 12),
          pw.Text(qrPayload, style: const pw.TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}

Future<Uint8List> buildStockItemQrPdf({
  required String qrPayload,
  String titleLine = '',
}) async {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => _stockQrLabelPageContent(
        qrPayload: qrPayload,
        titleLine: titleLine,
      ),
    ),
  );
  return doc.save();
}

/// Satu halaman A4 per item, QR 1 cm (sama seperti cetak tunggal).
Future<Uint8List> buildStockItemsBulkQrPdf(
  List<Map<String, dynamic>> items,
) async {
  final doc = pw.Document();
  for (final item in items) {
    final payload = stockItemQrPayload(item);
    if (payload.isEmpty) continue;
    final name = (item['name'] ?? '').toString().trim();
    final title = name.isNotEmpty ? name : payload;
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => _stockQrLabelPageContent(
          qrPayload: payload,
          titleLine: title,
        ),
      ),
    );
  }
  return doc.save();
}

/// Buka layar cetak PDF stok (satu label). Jika [askConfirm], tampilkan dialog dulu.
Future<void> promptPrintStockItemQr(
  BuildContext context, {
  required Map<String, dynamic> item,
  bool askConfirm = true,
}) async {
  final payload = stockItemQrPayload(item);
  if (payload.isEmpty) return;

  final name = (item['name'] ?? '').toString().trim();
  final title = name.isNotEmpty ? name : payload;

  if (askConfirm) {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cetak QR stok?'),
        content: Text(
          'QR berisi kode:\n$payload'
          '${name.isNotEmpty ? '\n\nNama: $name' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.print, size: 20),
            label: const Text('Cetak QR'),
          ),
        ],
      ),
    );

    if (go != true || !context.mounted) return;
  }

  try {
    final bytes =
        await buildStockItemQrPdf(qrPayload: payload, titleLine: title);
    if (!context.mounted) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal cetak QR: $e')),
      );
    }
  }
}

/// Cetak satu PDF berisi banyak label (satu halaman per item). Jika [askConfirm], dialog dulu.
Future<void> promptPrintStockItemsQrBulk(
  BuildContext context, {
  required List<Map<String, dynamic>> items,
  bool askConfirm = true,
}) async {
  final withPayload = items
      .where((i) => stockItemQrPayload(i).isNotEmpty)
      .map((i) => Map<String, dynamic>.from(i))
      .toList();
  if (withPayload.isEmpty) return;

  if (askConfirm) {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cetak QR stok massal?'),
        content: Text(
          '${withPayload.length} label akan digabung dalam satu PDF '
          '(satu halaman per item, QR 1×1 cm).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.print, size: 20),
            label: const Text('Cetak QR'),
          ),
        ],
      ),
    );

    if (go != true || !context.mounted) return;
  }

  try {
    final bytes = await buildStockItemsBulkQrPdf(withPayload);
    if (!context.mounted) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal cetak QR: $e')),
      );
    }
  }
}
