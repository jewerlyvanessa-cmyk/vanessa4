import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

/// Font Roboto dari [assets/fonts] untuk dokumen PDF (faktur, laporan, dll.).
abstract final class PdfFonts {
  static pw.Font? _regular;
  static pw.Font? _bold;
  static pw.Font? _italic;

  static Future<void> ensureLoaded() async {
    if (_regular != null) return;
    try {
      final regularBytes = await rootBundle.load(
        'assets/fonts/Roboto-Regular.ttf',
      );
      final boldBytes = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
      final italicBytes = await rootBundle.load(
        'assets/fonts/Roboto-Italic.ttf',
      );
      _regular = pw.Font.ttf(regularBytes);
      _bold = pw.Font.ttf(boldBytes);
      _italic = pw.Font.ttf(italicBytes);
    } catch (_) {
      // Hot reload tidak memuat asset baru — restart app. Fallback agar cetak tetap jalan.
      _regular = pw.Font.helvetica();
      _bold = pw.Font.helveticaBold();
      _italic = pw.Font.helveticaOblique();
    }
  }

  static pw.Font get regular {
    final f = _regular;
    if (f == null) {
      throw StateError('PdfFonts.ensureLoaded() belum dipanggil');
    }
    return f;
  }

  static pw.Font get bold {
    final f = _bold;
    if (f == null) {
      throw StateError('PdfFonts.ensureLoaded() belum dipanggil');
    }
    return f;
  }

  static pw.Font get italic {
    final f = _italic;
    if (f == null) {
      throw StateError('PdfFonts.ensureLoaded() belum dipanggil');
    }
    return f;
  }

  static pw.ThemeData get theme => pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        italic: italic,
        boldItalic: bold,
      );
}
