import 'dart:convert';
import 'dart:typed_data';

import 'package:vanessa3/utils/stock_item_qr_print.dart';
import 'package:vanessa3/utils/stock_label_geometry.dart';

/// TSPL untuk Xprinter XP-TT426B — label jewelry Yupo 80×12 mm @ 203 DPI.
///
/// Cetak di kepala kiri+kanan (45×12 mm); ekor dan tepi backing tidak dicetak.
/// Sensor gap dipakai untuk mendeteksi posisi label sebelum cetak.
abstract final class StockLabelTspl {
  StockLabelTspl._();

  static const int _dpi = 203;

  /// Jarak antar-label (celah die-cut) pada roll gap Yupo, mm.
  static const double kYupoLabelGapMm = 2.0;

  /// Font TSPL "1" @ xmul/ymul = 1 → lebar karakter ~8 dot, tinggi ~12 dot.
  static const int _fontCharWidthDots = 8;
  static const int _fontLineHeightDots = 14;

  static int mmToDots(double mm) => (mm * _dpi / 25.4).round();

  static String _esc(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

  static String _truncate(String value, int maxChars) {
    final t = value.trim();
    if (t.length <= maxChars) return t;
    return '${t.substring(0, maxChars - 1)}…';
  }

  /// Setup media + kalibrasi gap sensor (sekali per job cetak).
  static String _jobHeader() {
    final labelHDots = mmToDots(kStockLabelHeightMm);
    final gapDots = mmToDots(kYupoLabelGapMm);
    final feedLimitMm = kStockLabelHeightMm + kYupoLabelGapMm + 4;

    return '''
SIZE $kStockLabelWidthMm mm,$kStockLabelHeightMm mm
GAP $kYupoLabelGapMm mm,0 mm
SPEED 4
DENSITY 10
DIRECTION 1,0
REFERENCE 0,0
OFFSET 0 mm
SET TEAR OFF
SET PEEL OFF
SET CUTTER OFF
LIMITFEED $feedLimitMm mm
GAPDETECT $labelHDots,$gapDots
''';
  }

  /// Teks rata kanan dalam zona kiri (sama seperti layout PDF).
  static int _textXRightAligned(String text, int zoneLeft, int zoneRight) {
    final width = text.length * _fontCharWidthDots;
    return (zoneRight - width).clamp(zoneLeft, zoneRight);
  }

  static void _writeTextBlockInHead(
    StringBuffer buf, {
    required List<String> lines,
    required int zoneLeft,
    required int zoneRight,
    required int headTop,
    required int headH,
    required int pad,
  }) {
    if (lines.isEmpty) return;

    final blockH = lines.length * _fontLineHeightDots;
    var y = (headTop + ((headH - blockH) / 2))
        .round()
        .clamp(headTop + pad, headTop + headH - blockH);

    for (final line in lines) {
      final x = _textXRightAligned(line, zoneLeft, zoneRight);
      buf.writeln('TEXT $x,$y,"1",0,1,1,"${_esc(line)}"');
      y += _fontLineHeightDots;
    }
  }

  static String? _buildLabelBody({
    required String payload,
    required String titleLine,
    required StockLabelPrintChoice format,
    String? weight,
    String? purity,
  }) {
    if (payload.trim().isEmpty) return null;

    final pad = mmToDots(_kLabelPadMm);
    final headLeft = mmToDots(StockLabelGeometry.headPrintableLeftMm);
    final headRight = mmToDots(StockLabelGeometry.headPrintableRightMm);
    final headTop = mmToDots(StockLabelGeometry.headPrintableTopMm);
    final headH = mmToDots(StockLabelGeometry.printableHeightMm);

    final codeBlockW = mmToDots(stockLabelCodeSectionWidthMm(format));
    final textZoneLeft = headLeft + pad;
    final textZoneRight = headRight - pad - codeBlockW;
    if (textZoneRight <= textZoneLeft) return null;

    final title = _truncate(
      titleLine.trim().isNotEmpty ? titleLine.trim() : payload,
      22,
    );
    final metaParts = <String>[];
    if (weight != null && weight.isNotEmpty) metaParts.add('Berat: $weight');
    if (purity != null && purity.isNotEmpty) metaParts.add('Kadar: $purity');
    final meta = metaParts.isEmpty ? null : _truncate(metaParts.join(' · '), 28);
    final code = _truncate(payload, 24);

    final textLines = <String>[title];
    if (meta != null) textLines.add(meta);
    textLines.add(code);

    final qrDots = mmToDots(kStockLabelQrMm);
    final barH = mmToDots(kStockLabelBarcodeHeightMm);
    final codeGap = mmToDots(_kCodeGapMm);

    final buf = StringBuffer();
    buf.writeln('CLS');

    _writeTextBlockInHead(
      buf,
      lines: textLines,
      zoneLeft: textZoneLeft,
      zoneRight: textZoneRight,
      headTop: headTop,
      headH: headH,
      pad: pad,
    );

    var codeX = headRight - pad - codeBlockW;
    final includeBarcode = format == StockLabelPrintChoice.barcode ||
        (format == StockLabelPrintChoice.both &&
            stockLabelCodeSectionWidthMm(format) > kStockLabelQrMm + _kCodeGapMm);

    if (format == StockLabelPrintChoice.qr ||
        format == StockLabelPrintChoice.both) {
      final qrY =
          (headTop + ((headH - qrDots) / 2)).round().clamp(headTop + pad, headTop + headH - qrDots);
      buf.writeln(
        'QRCODE $codeX,$qrY,M,3,A,0,M2,S3,"${_esc(payload)}"',
      );
      if (includeBarcode && format == StockLabelPrintChoice.both) {
        codeX += qrDots + codeGap;
      }
    }

    if (includeBarcode) {
      final barY =
          (headTop + ((headH - barH) / 2)).round().clamp(headTop + pad, headTop + headH - barH);
      buf.writeln(
        'BARCODE $codeX,$barY,"128",$barH,0,0,2,4,"${_esc(payload)}"',
      );
    }

    buf.writeln('PRINT 1,1');
    return buf.toString();
  }

  static String buildOne({
    required String payload,
    required String titleLine,
    required StockLabelPrintChoice format,
    String? weight,
    String? purity,
  }) {
    final body = _buildLabelBody(
      payload: payload,
      titleLine: titleLine,
      format: format,
      weight: weight,
      purity: purity,
    );
    if (body == null) return '';
    return '${_jobHeader()}$body';
  }

  /// Gabungkan beberapa label menjadi satu job TSPL.
  /// Header media + GAPDETECT dikirim sekali di awal job.
  static Uint8List buildBatch({
    required List<({
      String payload,
      String titleLine,
      StockLabelPrintChoice format,
      String? weight,
      String? purity,
    })> labels,
  }) {
    final buf = StringBuffer(_jobHeader());
    for (final label in labels) {
      final body = _buildLabelBody(
        payload: label.payload,
        titleLine: label.titleLine,
        format: label.format,
        weight: label.weight,
        purity: label.purity,
      );
      if (body != null) buf.write(body);
    }
    return Uint8List.fromList(utf8.encode(buf.toString()));
  }
}

const double _kLabelPadMm = 0.8;
const double _kCodeGapMm = 1.0;
