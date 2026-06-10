import 'dart:convert';
import 'dart:typed_data';

import 'package:vanessa3/utils/stock_item_qr_print.dart';
import 'package:vanessa3/utils/stock_label_geometry.dart';

/// TSPL untuk Xprinter XP-TT426B — label jewelry Yupo @ 203 DPI.
///
/// Skenario cetak:
///  1. Header kirim BACKFEED = persis sama dengan feed akhir job sebelumnya.
///     Printer menarik kertas mundur ke posisi label pertama sebelum cetak.
///  2. Cetak semua label, teks di tengah kepala kiri, barcode di kepala kanan.
///  3. Setelah label terakhir, feed maju [kPostPrintExtraLabels] label kosong
///     agar label terakhir mudah disobek.
///
/// Simetri: BACKFEED == post-print feed → posisi selalu tepat secara otomatis.
/// Pertama kali (fresh roll): user tekan FEED printer 1× untuk align awal.
abstract final class StockLabelTspl {
  StockLabelTspl._();

  static const int _dpi = 203;
  static const int _density = 8;

  /// Jarak antar-label (celah die-cut) pada roll gap Yupo, mm.
  static const double kYupoLabelGapMm = 2.0;

  /// Jumlah label kosong yang dikeluarkan setelah cetak terakhir.
  static const double kPostPrintExtraLabels = 4.0;

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

  static int get _headWidthDots => mmToDots(StockLabelGeometry.headPrintableWidthMm);

  static int get _headHeightDots => mmToDots(StockLabelGeometry.headPrintableHeightMm);

  /// Setup media + anchor origin kepala, plus retrak otomatis.
  ///
  /// BACKFEED = persis sama dengan post-print feed akhir job sebelumnya,
  /// sehingga printer selalu kembali ke label pertama secara otomatis.
  static String _jobHeader() {
    final refX = mmToDots(StockLabelGeometry.tsplReferenceLeftMm);
    final refY = mmToDots(StockLabelGeometry.tsplReferenceTopMm);
    final backfeedDots = _postPrintFeedDots();

    return '''
SIZE ${StockLabelGeometry.tsplMediaWidthMm} mm,${StockLabelGeometry.tsplMediaHeightMm} mm
GAP $kYupoLabelGapMm mm,0 mm
SPEED 4
DENSITY $_density
DIRECTION 1,0
REFERENCE $refX,$refY
OFFSET 0 mm
SET TEAR ON
SET PEEL OFF
SET CUTTER OFF
BACKFEED $backfeedDots
''';
  }

  /// Kalibrasi gap sensor — **hanya sekali** saat ganti roll / printer nyala.
  /// Akan membuang beberapa label kosong (normal).
  static Uint8List buildGapCalibrationJob() {
    final labelHDots = mmToDots(StockLabelGeometry.tsplMediaHeightMm);
    final gapDots = mmToDots(kYupoLabelGapMm);
    final buf = StringBuffer()
      ..writeln(
        'SIZE ${StockLabelGeometry.tsplMediaWidthMm} mm,'
        '${StockLabelGeometry.tsplMediaHeightMm} mm',
      )
      ..writeln('GAP $kYupoLabelGapMm mm,0 mm')
      ..writeln('GAPDETECT $labelHDots,$gapDots');
    return Uint8List.fromList(utf8.encode(buf.toString()));
  }

  /// Auto-posisi untuk roll baru dari POSISI MANA PUN.
  ///
  /// Kirim SIZE + GAP lalu [EOP]: printer scan maju sampai sensor gap
  /// menemukan celah antar-label, berhenti tepat di awal label berikutnya.
  /// Membuang paling banyak 1 label (bagian label saat ini yang terlewat).
  /// Cukup dilakukan SEKALI setiap ganti roll; setelah itu BACKFEED simetris
  /// menangani posisi otomatis antar job.
  static Uint8List buildNewRollPositionJob() {
    final buf = StringBuffer()
      ..writeln(
        'SIZE ${StockLabelGeometry.tsplMediaWidthMm} mm,'
        '${StockLabelGeometry.tsplMediaHeightMm} mm',
      )
      ..writeln('GAP $kYupoLabelGapMm mm,0 mm')
      ..writeln('DIRECTION 1,0')
      ..writeln('EOP');
    return Uint8List.fromList(utf8.encode(buf.toString()));
  }

  /// Pre-check posisi awal paper sebelum job print:
  /// minta printer cari top-of-label saat ini (tanpa cetak).
  static Uint8List buildPrePrintCheckJob() {
    final buf = StringBuffer()
      ..writeln(
        'SIZE ${StockLabelGeometry.tsplMediaWidthMm} mm,'
        '${StockLabelGeometry.tsplMediaHeightMm} mm',
      )
      ..writeln('GAP $kYupoLabelGapMm mm,0 mm')
      ..writeln('DIRECTION 1,0')
      ..writeln('OFFSET 0 mm')
      ..writeln('HOME');
    return Uint8List.fromList(utf8.encode(buf.toString()));
  }

  static int _maxCharsForZone(int zoneLeft, int zoneRight) {
    final zoneW = (zoneRight - zoneLeft).clamp(0, 10000);
    return (zoneW / _fontCharWidthDots).floor().clamp(4, 40);
  }

  static ({int narrow, int wide}) _barcodeModuleWidthForPayload(String payload) {
    final len = payload.trim().length;
    if (len <= 8) return (narrow: 2, wide: 4);
    if (len <= 12) return (narrow: 2, wide: 3);
    return (narrow: 1, wide: 2);
  }

  static void _writeTextBlockInHead(
    StringBuffer buf, {
    required List<String> lines,
    required int zoneLeft,
    required int zoneRight,
    required int pad,
  }) {
    if (lines.isEmpty) return;

    final blockH = lines.length * _fontLineHeightDots;
    var y = ((_headHeightDots - blockH) / 2)
        .round()
        .clamp(pad, _headHeightDots - blockH);

    for (final line in lines) {
      final x = zoneLeft;
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

    final layout = stockLabelResolveCodeLayout(format);
    final pad = mmToDots(_kLabelPadMm);
    final textZoneW = mmToDots(StockLabelGeometry.headTextZoneWidthMm);
    final codeZoneLeft = textZoneW;
    final codeZoneW = mmToDots(StockLabelGeometry.headCodeZoneWidthMm);
    final codeBlockW = mmToDots(layout.totalWidthMm);
    final textZoneLeft = pad;
    final textZoneRight = textZoneW - pad;
    if (textZoneRight <= textZoneLeft) return null;
    final maxTextChars = _maxCharsForZone(textZoneLeft, textZoneRight);

    final textLines = stockLabelTextLines(
      payload: payload,
      purity: purity,
      weight: weight,
    ).map((line) => _truncate(line, maxTextChars)).toList();

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
      pad: pad,
    );

    var codeX = codeZoneLeft + ((codeZoneW - codeBlockW) / 2).round();
    final includeBarcode = layout.showBarcode;

    if (layout.showQr) {
      final qrY = ((_headHeightDots - qrDots) / 2)
          .round()
          .clamp(pad, _headHeightDots - qrDots);
      buf.writeln(
        'QRCODE $codeX,$qrY,M,3,A,0,M2,S3,"${_esc(payload)}"',
      );
      if (includeBarcode) {
        codeX += qrDots + codeGap;
      }
    }

    if (includeBarcode) {
      final barY = ((_headHeightDots - barH) / 2)
          .round()
          .clamp(pad, _headHeightDots - barH);
      final module = _barcodeModuleWidthForPayload(payload);
      buf.writeln(
        'BARCODE $codeX,$barY,"128",$barH,0,0,${module.narrow},${module.wide},"${_esc(payload)}"',
      );
    }

    buf.writeln('PRINT 1,1');
    return buf.toString();
  }

  /// Label uji: kotak + garis tengah zona kepala — untuk kalibrasi offset.
  static Uint8List buildCalibrationSample() {
    final w = _headWidthDots;
    final h = _headHeightDots;
    final buf = StringBuffer(_jobHeader())
      ..writeln('CLS')
      ..writeln('BOX 0,0,$w,$h,2')
      ..writeln('BAR $w,0,$w,$h')
      ..writeln('TEXT 2,2,"1",0,1,1,"ATAS-KIRI"')
      ..writeln('TEXT 2,${h - 14},"1",0,1,1,"BAWAH"')
      ..writeln('PRINT 1,1');
    return Uint8List.fromList(utf8.encode(buf.toString()));
  }

  static int _postPrintFeedDots() {
    final pitchMm = StockLabelGeometry.tsplMediaHeightMm + kYupoLabelGapMm;
    return mmToDots(pitchMm * kPostPrintExtraLabels);
  }

  static String _tearFeedCommand() {
    final dots = _postPrintFeedDots();
    if (dots <= 0) return '';
    return 'FEED $dots\n';
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
    return '${_jobHeader()}$body${_tearFeedCommand()}';
  }

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
    buf.write(_tearFeedCommand());
    return Uint8List.fromList(utf8.encode(buf.toString()));
  }
}

const double _kLabelPadMm = 0.8;
const double _kCodeGapMm = 1.0;
