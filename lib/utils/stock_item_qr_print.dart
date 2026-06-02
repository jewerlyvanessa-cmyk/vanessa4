import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:vanessa3/utils/save_download_bytes.dart';
import 'package:vanessa3/utils/open_pdf_web_stub.dart'
    if (dart.library.html) 'package:vanessa3/utils/open_pdf_web.dart'
    as open_pdf_web;

/// Label stok thermal: 80 × 12 mm (satu label per halaman PDF).
const double kStockLabelWidthMm = 80;
const double kStockLabelHeightMm = 12;
const double kStockLabelQrMm = 8;
const double kStockLabelBarcodeWidthMm = 20;
const double kStockLabelBarcodeHeightMm = 8;
/// Jarak tepi kanan label ke area teks (judul / berat / kode): 2,5 cm.
const double kStockLabelTextOffsetFromRightMm = 25;

PdfPageFormat get stockLabelPageFormat => PdfPageFormat(
      kStockLabelWidthMm * PdfPageFormat.mm,
      kStockLabelHeightMm * PdfPageFormat.mm,
      marginAll: 0,
    );

/// Konversi mm → point PDF (72 pt = 1 inch, 25,4 mm = 1 inch).
double _pdfMmToPoints(double mm) => mm * 72.0 / 25.4;

const double _kLabelPadMm = 0.8;
const double _kCodeGapMm = 1.0;

double _codeSectionWidthMm(StockLabelPrintChoice format) {
  switch (format) {
    case StockLabelPrintChoice.qr:
      return kStockLabelQrMm;
    case StockLabelPrintChoice.barcode:
      return kStockLabelBarcodeWidthMm;
    case StockLabelPrintChoice.both:
      return kStockLabelQrMm + _kCodeGapMm + kStockLabelBarcodeWidthMm;
  }
}

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

({String? weight, String? purity}) _labelMetaFromItem(
  Map<String, dynamic>? item,
) {
  if (item == null) return (weight: null, purity: null);
  return (
    weight: _formatLabelWeight(item['weight']),
    purity: _formatLabelPurity(item['purity']),
  );
}

String? _metaLine({String? weight, String? purity}) {
  final parts = <String>[];
  if (weight != null) parts.add('Berat: $weight');
  if (purity != null) parts.add('Kadar: $purity');
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

pw.Widget _qrBlock(String payload) {
  final size = _pdfMmToPoints(kStockLabelQrMm);
  return pw.BarcodeWidget(
    barcode: pw.Barcode.qrCode(),
    data: payload,
    width: size,
    height: size,
  );
}

pw.Widget _barcodeBlock(String payload) {
  return pw.BarcodeWidget(
    barcode: pw.Barcode.code128(),
    data: payload,
    width: _pdfMmToPoints(kStockLabelBarcodeWidthMm),
    height: _pdfMmToPoints(kStockLabelBarcodeHeightMm),
    drawText: false,
  );
}

pw.Widget _labelTextColumn({
  required String displayTitle,
  required String payload,
  String? weight,
  String? purity,
}) {
  final titleStyle =
      pw.TextStyle(fontSize: 5.5, fontWeight: pw.FontWeight.bold);
  final metaStyle = pw.TextStyle(fontSize: 4.8);
  final codeStyle = pw.TextStyle(fontSize: 5.2);

  final meta = _metaLine(weight: weight, purity: purity);
  final children = <pw.Widget>[
    pw.Text(
      displayTitle,
      style: titleStyle,
      maxLines: 1,
      overflow: pw.TextOverflow.clip,
    ),
  ];
  if (meta != null) {
    children.add(
      pw.Text(
        meta,
        style: metaStyle,
        maxLines: 1,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }
  children.add(
    pw.Text(
      payload,
      style: codeStyle,
      maxLines: 1,
      overflow: pw.TextOverflow.clip,
    ),
  );

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    mainAxisAlignment: pw.MainAxisAlignment.center,
    mainAxisSize: pw.MainAxisSize.min,
    children: children,
  );
}

pw.Widget _codeBlocksRow(
  String payload,
  StockLabelPrintChoice format,
  double gap,
) {
  final children = <pw.Widget>[];
  if (format == StockLabelPrintChoice.qr ||
      format == StockLabelPrintChoice.both) {
    children.add(_qrBlock(payload));
  }
  if (format == StockLabelPrintChoice.both) {
    children.add(pw.SizedBox(width: gap));
  }
  if (format == StockLabelPrintChoice.barcode ||
      format == StockLabelPrintChoice.both) {
    children.add(_barcodeBlock(payload));
  }
  return pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: children,
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
  final pad = _pdfMmToPoints(_kLabelPadMm);
  final gap = _pdfMmToPoints(_kCodeGapMm);
  final codeWidthMm = _codeSectionWidthMm(format);

  return pw.SizedBox(
    width: _pdfMmToPoints(kStockLabelWidthMm),
    height: _pdfMmToPoints(kStockLabelHeightMm),
    child: pw.Padding(
      padding: pw.EdgeInsets.all(pad),
      child: pw.Stack(
        children: [
          pw.Positioned(
            left: 0,
            right: _pdfMmToPoints(kStockLabelTextOffsetFromRightMm - _kLabelPadMm),
            top: 0,
            bottom: 0,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: _labelTextColumn(
                displayTitle: displayTitle,
                payload: payload,
                weight: meta.weight,
                purity: meta.purity,
              ),
            ),
          ),
          pw.Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: pw.SizedBox(
              width: _pdfMmToPoints(codeWidthMm),
              child: pw.Center(
                child: _codeBlocksRow(payload, format, gap),
              ),
            ),
          ),
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
      pageFormat: stockLabelPageFormat,
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
        pageFormat: stockLabelPageFormat,
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

const _labelPrintChannel = MethodChannel('com.example.vanessa3/label_print');

bool get _useNativeLabelPrint =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Cetak label di mobile dengan ukuran kertas tepat 80×12 mm (sama seperti web).
Future<bool> _printLabelNative(Uint8List bytes, {required int pageCount}) async {
  final result = await _labelPrintChannel.invokeMethod<bool>(
    'printLabelPdf',
    <String, dynamic>{
      'name': 'label_stok',
      'widthMm': kStockLabelWidthMm,
      'heightMm': kStockLabelHeightMm,
      'pageCount': pageCount,
      'data': bytes,
    },
  );
  return result ?? false;
}

/// Perkiraan jumlah halaman label dalam PDF (satu label = satu halaman).
int _estimateLabelPdfPageCount(Uint8List bytes) {
  final text = String.fromCharCodes(bytes);
  final matches = RegExp(r'/Type\s*/Page(?!s)').allMatches(text);
  return matches.isEmpty ? 1 : matches.length;
}

String _labelPdfFileName() {
  final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  return 'label_stok_$stamp.pdf';
}

/// Simpan PDF label langsung (80×12 mm per halaman, tanpa dialog cetak Android).
Future<void> _saveLabelPdf(
  BuildContext context,
  Uint8List bytes,
) async {
  try {
    if (_useNativeLabelPrint) {
      final path = await _labelPrintChannel.invokeMethod<String>(
        'saveLabelPdf',
        <String, dynamic>{
          'fileName': _labelPdfFileName(),
          'data': bytes,
        },
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path != null && path.isNotEmpty
                ? 'PDF label tersimpan ($kStockLabelWidthMm×$kStockLabelHeightMm mm per halaman).\n$path'
                : 'PDF label tersimpan.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    await saveDownloadBytes(
      filename: _labelPdfFileName(),
      bytes: bytes,
      mimeType: 'application/pdf',
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal simpan PDF: $e')),
      );
    }
  }
}

enum _LabelOutput { print, savePdf }

Future<_LabelOutput?> _askLabelOutput(BuildContext context) async {
  return showModalBottomSheet<_LabelOutput>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.print),
            title: const Text('Cetak'),
            subtitle: Text(
              'Printer / Save as PDF sistem ($kStockLabelWidthMm×$kStockLabelHeightMm mm)',
            ),
            onTap: () => Navigator.pop(ctx, _LabelOutput.print),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf),
            title: const Text('Simpan PDF'),
            subtitle: Text(
              'File PDF ukuran tepat $kStockLabelWidthMm×$kStockLabelHeightMm mm per label',
            ),
            onTap: () => Navigator.pop(ctx, _LabelOutput.savePdf),
          ),
        ],
      ),
    ),
  );
}

Future<void> _runPrint(
  BuildContext context,
  Future<Uint8List> Function() buildPdf, {
  required String errorPrefix,
}) async {
  try {
    final bytes = await buildPdf();
    if (!context.mounted) return;

    // Selalu tawarkan opsi Simpan PDF. Untuk web/desktop, ini sering lebih stabil
    // daripada langsung print (driver/browser kadang gagal render barcode/QR).
    final output = await _askLabelOutput(context);
    if (!context.mounted || output == null) return;

    if (output == _LabelOutput.savePdf) {
      await _saveLabelPdf(context, bytes);
      return;
    }

    // Web: lebih andal buka PDF di tab baru, lalu user print dari viewer browser.
    // `Printing.layoutPdf` sering gagal render barcode/QR pada beberapa driver/printer.
    if (kIsWeb) {
      await open_pdf_web.openPdfInBrowserTab(bytes: bytes);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'PDF label dibuka di tab baru. Gunakan Print di viewer browser untuk hasil paling stabil.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    if (_useNativeLabelPrint && context.mounted) {
      final ok = await _printLabelNative(
        bytes,
        pageCount: _estimateLabelPdfPageCount(bytes),
      );
      if (ok) return;

      // Fallback: beberapa printer/driver Android kadang gagal render page custom kecil.
      // Simpan PDF lalu minta user cetak dari viewer/Files (biasanya lebih stabil).
      if (!context.mounted) return;
      await _saveLabelPdf(context, bytes);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cetak langsung gagal. PDF label sudah disimpan — buka file tersebut lalu cetak dari viewer untuk hasil paling stabil.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    await Printing.layoutPdf(
      name: 'label_stok',
      format: stockLabelPageFormat,
      dynamicLayout: false,
      usePrinterSettings: false,
      forceCustomPrintPaper: true,
      onLayout: (_) async => bytes,
    );
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
        ? 'Cetak label $kStockLabelWidthMm×$kStockLabelHeightMm mm untuk kode $payload?'
            '${name.isNotEmpty ? '\n($name)' : ''}'
        : 'Kode: $payload${name.isNotEmpty ? '\nNama: $name' : ''}\n\n'
            'Label $kStockLabelWidthMm×$kStockLabelHeightMm mm. Pilih format cetak.',
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
        ? 'Cetak ${withPayload.length} label ($kStockLabelWidthMm×$kStockLabelHeightMm mm)?'
        : '${withPayload.length} label, satu halaman per item '
            '($kStockLabelWidthMm×$kStockLabelHeightMm mm).\n'
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
          '${name.isNotEmpty ? '\n\nNama: $name' : ''}\n\n'
          'Ukuran label $kStockLabelWidthMm×$kStockLabelHeightMm mm, QR $kStockLabelQrMm mm.',
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
          '${withPayload.length} label ($kStockLabelWidthMm×$kStockLabelHeightMm mm, '
          'satu halaman per item, QR $kStockLabelQrMm mm).',
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
          '${name.isNotEmpty ? '\n\nNama: $name' : ''}\n\n'
          'Label $kStockLabelWidthMm×$kStockLabelHeightMm mm, '
          'barcode $kStockLabelBarcodeWidthMm×$kStockLabelBarcodeHeightMm mm.',
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
