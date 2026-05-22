import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vanessa3/utils/save_download_bytes.dart';

import 'open_pdf_web_stub.dart'
    if (dart.library.html) 'open_pdf_web.dart' as open_pdf_web;

enum _WebPdfAction { open, download, share }

/// Kirim PDF ke printer (native/desktop) atau unduh/buka/bagikan (web & web mobile).
Future<void> deliverPdfDocument(
  BuildContext context, {
  required Uint8List pdfBytes,
  required String filename,
  required PdfPageFormat format,
}) async {
  if (kIsWeb) {
    await _deliverPdfOnWeb(context, pdfBytes: pdfBytes, filename: filename);
    return;
  }

  try {
    final info = await Printing.info();
    if (info.canPrint) {
      await Printing.layoutPdf(
        name: filename,
        format: format,
        onLayout: (_) async => pdfBytes,
      );
      return;
    }
  } catch (_) {}

  try {
    await Printing.sharePdf(bytes: pdfBytes, filename: filename);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membagikan PDF: $e')),
      );
    }
  }
}

Future<void> _deliverPdfOnWeb(
  BuildContext context, {
  required Uint8List pdfBytes,
  required String filename,
}) async {
  if (!context.mounted) return;

  final action = await showModalBottomSheet<_WebPdfAction>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Cetak di browser HP',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Pilih "Buka PDF" lalu gunakan menu Share/Cetak di browser. '
                'Dialog cetak langsung sering tidak muncul di Safari mobile.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Buka PDF'),
              subtitle: const Text('Disarankan — cetak dari menu browser'),
              onTap: () => Navigator.pop(ctx, _WebPdfAction.open),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Unduh PDF'),
              onTap: () => Navigator.pop(ctx, _WebPdfAction.download),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Bagikan'),
              onTap: () => Navigator.pop(ctx, _WebPdfAction.share),
            ),
          ],
        ),
      ),
    ),
  );

  if (!context.mounted || action == null) return;

  try {
    switch (action) {
      case _WebPdfAction.open:
        await open_pdf_web.openPdfInBrowserTab(bytes: pdfBytes);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'PDF dibuka di tab baru. Gunakan Share → Print di browser untuk cetak.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
        break;
      case _WebPdfAction.download:
        await saveDownloadBytes(
          filename: filename.endsWith('.pdf') ? filename : '$filename.pdf',
          bytes: pdfBytes,
          mimeType: 'application/pdf',
        );
        break;
      case _WebPdfAction.share:
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                pdfBytes,
                name: filename.endsWith('.pdf') ? filename : '$filename.pdf',
                mimeType: 'application/pdf',
              ),
            ],
            subject: filename,
          ),
        );
        break;
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menampilkan PDF: $e')),
      );
    }
  }
}
