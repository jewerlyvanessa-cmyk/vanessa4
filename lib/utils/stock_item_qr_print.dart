import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Konversi cm → point PDF (72 pt = 1 inch, 2,54 cm = 1 inch).
double _pdfCmToPoints(double cm) => cm * 72.0 / 2.54;

/// Pilihan format cetak label stok.
enum StockLabelPrintChoice { qr, barcode, both }

/// Isi label: kode produk (untuk scan), fallback `item_id`.
String stockItemQrPayload(Map<String, dynamic> item) {
  final k = (item['kode_produk'] ?? item['item_code'] ?? '').toString().trim();
  if (k.isNotEmpty) return k;
  final id = item['item_id'];
  if (id != null) return id.toString();
  return '';
}

String _displayTitle(String titleLine, String payload) {
  final t = titleLine.trim();
  if (t.isNotEmpty) return t;
  return payload.isNotEmpty ? payload : 'Label stok';
}

String? _formatLabelWeight(dynamic raw) {
  if (raw == null) return null;
  final n = double.tryParse(raw.toString().trim());
  if (n == null || n <= 0) return null;
  if (n == n.roundToDouble()) return '${n.toInt()} g';
  return '${n.toStringAsFixed(2)} g';
}

String? _formatLabelPurity(dynamic raw) {
  final s = raw?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

({String? weight, String? purity}) _labelMetaFromItem(Map<String, dynamic>? item) {
  if (item == null) return (weight: null, purity: null);
  return (
    weight: _formatLabelWeight(item['weight']),
    purity: _formatLabelPurity(item['purity']),
  );
}

pw.Widget _weightPurityBlock({String? weight, String? purity}) {
  final parts = <String>[];
  if (weight != null) parts.add('Berat: $weight');
  if (purity != null) parts.add('Kadar: $purity');
  if (parts.isEmpty) return pw.SizedBox();
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 10),
    child: pw.Text(
      parts.join('   ·   '),
      style: const pw.TextStyle(fontSize: 11),
      textAlign: pw.TextAlign.center,
    ),
  );
}

pw.Widget _humanCodeLine(String payload) {
  return pw.Text(payload, style: const pw.TextStyle(fontSize: 12));
}

pw.Widget _qrBlock(String payload) {
  final qrSizePt = _pdfCmToPoints(1.0);
  return pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.BarcodeWidget(
        barcode: pw.Barcode.qrCode(),
        data: payload,
        width: qrSizePt,
        height: qrSizePt,
      ),
      pw.SizedBox(height: 8),
      _humanCodeLine(payload),
    ],
  );
}

pw.Widget _barcodeBlock(String payload) {
  final barW = _pdfCmToPoints(5.0);
  final barH = _pdfCmToPoints(1.6);
  return pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.BarcodeWidget(
        barcode: pw.Barcode.code128(),
        data: payload,
        width: barW,
        height: barH,
        drawText: false,
      ),
      pw.SizedBox(height: 6),
      _humanCodeLine(payload),
    ],
  );
}

pw.Widget _stockLabelPageContent({
  required String payload,
  required String titleLine,
  required StockLabelPrintChoice format,
  Map<String, dynamic>? item,
}) {
  final displayTitle = _displayTitle(titleLine, payload);
  final meta = _labelMetaFromItem(item);
  return pw.Center(
    child: pw.Padding(
      padding: const pw.EdgeInsets.all(24),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            displayTitle,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
            textAlign: pw.TextAlign.center,
          ),
          _weightPurityBlock(weight: meta.weight, purity: meta.purity),
          if (format == StockLabelPrintChoice.qr ||
              format == StockLabelPrintChoice.both)
            _qrBlock(payload),
          if (format == StockLabelPrintChoice.both) pw.SizedBox(height: 16),
          if (format == StockLabelPrintChoice.barcode ||
              format == StockLabelPrintChoice.both)
            _barcodeBlock(payload),
        ],
      ),
    ),
  );
}

Future<Uint8List> buildStockItemLabelPdf({
  required String payload,
  String titleLine = '',
  StockLabelPrintChoice format = StockLabelPrintChoice.qr,
  Map<String, dynamic>? item,
}) async {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => _stockLabelPageContent(
        payload: payload,
        titleLine: titleLine,
        format: format,
        item: item,
      ),
    ),
  );
  return doc.save();
}

Future<Uint8List> buildStockItemQrPdf({
  required String qrPayload,
  String titleLine = '',
}) =>
    buildStockItemLabelPdf(
      payload: qrPayload,
      titleLine: titleLine,
      format: StockLabelPrintChoice.qr,
    );

Future<Uint8List> buildStockItemsLabelPdf(
  List<Map<String, dynamic>> items,
  StockLabelPrintChoice format,
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
        build: (context) => _stockLabelPageContent(
          payload: payload,
          titleLine: title,
          format: format,
          item: item,
        ),
      ),
    );
  }
  return doc.save();
}

Future<Uint8List> buildStockItemsBulkQrPdf(
  List<Map<String, dynamic>> items,
) =>
    buildStockItemsLabelPdf(items, StockLabelPrintChoice.qr);

Future<void> _runPrint(
  BuildContext context,
  Future<Uint8List> Function() buildPdf, {
  required String errorPrefix,
}) async {
  try {
    final bytes = await buildPdf();
    if (!context.mounted) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$errorPrefix: $e')),
      );
    }
  }
}

Future<StockLabelPrintChoice?> _askLabelPrintChoice(
  BuildContext context, {
  required String title,
  required String message,
  bool allowSkip = true,
}) async {
  return showDialog<StockLabelPrintChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        if (allowSkip)
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Lewati'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, StockLabelPrintChoice.qr),
          child: const Text('Cetak QR'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, StockLabelPrintChoice.barcode),
          child: const Text('Cetak barcode'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, StockLabelPrintChoice.both),
          icon: const Icon(Icons.print, size: 20),
          label: const Text('Keduanya'),
        ),
      ],
    ),
  );
}

Future<void> _printOneItem(
  BuildContext context, {
  required Map<String, dynamic> item,
  required StockLabelPrintChoice format,
}) async {
  final payload = stockItemQrPayload(item);
  if (payload.isEmpty) return;
  final name = (item['name'] ?? '').toString().trim();
  final title = name.isNotEmpty ? name : payload;
  await _runPrint(
    context,
    () => buildStockItemLabelPdf(
      payload: payload,
      titleLine: title,
      format: format,
      item: item,
    ),
    errorPrefix: 'Gagal cetak label',
  );
}

Future<void> _printManyItems(
  BuildContext context, {
  required List<Map<String, dynamic>> items,
  required StockLabelPrintChoice format,
}) async {
  final withPayload = items
      .where((i) => stockItemQrPayload(i).isNotEmpty)
      .map((i) => Map<String, dynamic>.from(i))
      .toList();
  if (withPayload.isEmpty) return;
  await _runPrint(
    context,
    () => buildStockItemsLabelPdf(withPayload, format),
    errorPrefix: 'Gagal cetak label',
  );
}

/// Dialog pilih format lalu cetak (disarankan setelah simpan stok).
Future<void> promptPrintStockItemLabel(
  BuildContext context, {
  required Map<String, dynamic> item,
  bool afterSave = false,
}) async {
  final payload = stockItemQrPayload(item);
  if (payload.isEmpty) return;

  final name = (item['name'] ?? '').toString().trim();
  final choice = await _askLabelPrintChoice(
    context,
    title: afterSave ? 'Stok tersimpan' : 'Cetak label stok?',
    message: afterSave
        ? 'Cetak label untuk kode $payload?'
            '${name.isNotEmpty ? '\n($name)' : ''}'
        : 'Kode: $payload${name.isNotEmpty ? '\nNama: $name' : ''}\n\n'
            'Pilih format cetak.',
  );
  if (!context.mounted || choice == null) return;

  await _printOneItem(context, item: item, format: choice);
}

/// Setelah simpan massal: pilih format lalu satu PDF multi-halaman.
Future<void> promptPrintStockItemsLabelBulk(
  BuildContext context, {
  required List<Map<String, dynamic>> items,
  bool afterSave = false,
}) async {
  final withPayload = items
      .where((i) => stockItemQrPayload(i).isNotEmpty)
      .map((i) => Map<String, dynamic>.from(i))
      .toList();
  if (withPayload.isEmpty) return;

  final choice = await _askLabelPrintChoice(
    context,
    title: afterSave ? 'Stok massal tersimpan' : 'Cetak label stok massal?',
    message: afterSave
        ? 'Cetak ${withPayload.length} label?'
        : '${withPayload.length} label (satu halaman per item).\n'
            'Pilih QR, barcode Code 128, atau keduanya.',
  );
  if (!context.mounted || choice == null) return;

  await _printManyItems(context, items: withPayload, format: choice);
}

/// Cetak QR saja (kompatibilitas / cetak ulang cepat).
Future<void> promptPrintStockItemQr(
  BuildContext context, {
  required Map<String, dynamic> item,
  bool askConfirm = true,
}) async {
  final payload = stockItemQrPayload(item);
  if (payload.isEmpty) return;

  final name = (item['name'] ?? '').toString().trim();

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

  await _printOneItem(
    context,
    item: item,
    format: StockLabelPrintChoice.qr,
  );
}

/// Cetak QR massal saja (kompatibilitas).
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

  await _printManyItems(
    context,
    items: withPayload,
    format: StockLabelPrintChoice.qr,
  );
}

/// Cetak barcode saja (satu item).
Future<void> promptPrintStockItemBarcode(
  BuildContext context, {
  required Map<String, dynamic> item,
  bool askConfirm = true,
}) async {
  final payload = stockItemQrPayload(item);
  if (payload.isEmpty) return;

  final name = (item['name'] ?? '').toString().trim();

  if (askConfirm) {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cetak barcode stok?'),
        content: Text(
          'Barcode Code 128 berisi kode:\n$payload'
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
            label: const Text('Cetak barcode'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
  }

  await _printOneItem(
    context,
    item: item,
    format: StockLabelPrintChoice.barcode,
  );
}
