import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Buka PDF di tab baru (reliable di Safari/Chrome mobile; `Printing.layoutPdf` sering gagal).
Future<void> openPdfInBrowserTab({required Uint8List bytes}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);
  final opened = web.window.open(url, '_blank');
  if (opened == null) {
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..target = '_blank'
      ..rel = 'noopener';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  }
  // Biarkan blob URL hidup agar tab sempat memuat PDF.
}
