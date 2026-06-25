import 'dart:convert';
import 'dart:typed_data';

import 'package:vanessa3/utils/stock_item_qr_print.dart';
import 'package:vanessa3/utils/stock_label_geometry.dart';

class StockLabelTsplSettings {
  const StockLabelTsplSettings({
    this.gapMm = StockLabelTspl.kDefaultGapMm,
    this.speed = 4,
    this.density = 8,
    this.calibrationOffsetXMm = StockLabelGeometry.tsplCalibrationOffsetXMm,
    this.calibrationOffsetYMm = StockLabelGeometry.tsplCalibrationOffsetYMm,
  });

  final double gapMm;
  final int speed;
  final int density;
  final double calibrationOffsetXMm;
  final double calibrationOffsetYMm;

  StockLabelTsplSettings copyWith({
    double? gapMm,
    int? speed,
    int? density,
    double? calibrationOffsetXMm,
    double? calibrationOffsetYMm,
  }) {
    return StockLabelTsplSettings(
      gapMm: gapMm ?? this.gapMm,
      speed: speed ?? this.speed,
      density: density ?? this.density,
      calibrationOffsetXMm: calibrationOffsetXMm ?? this.calibrationOffsetXMm,
      calibrationOffsetYMm: calibrationOffsetYMm ?? this.calibrationOffsetYMm,
    );
  }
}

/// TSPL untuk Xprinter XP-TT426B — label jewelry Yupo @ 203 DPI.
///
/// Skenario cetak:
///  1. Header: SIZE/GAP/SET TEAR OFF — tanpa HOME (TSPL2 HOME feed maju → skip label).
///  2. PRINT otomatis deteksi gap per label via sensor.
///  3. Label tengah batch: SET TEAR OFF — berhenti di awal label berikutnya (siap cetak lagi).
///  4. Label terakhir batch: SET TEAR ON sebelum PRINT — label jadi di tear bar, bisa dirobek.
///     Tanpa FEED eject terpisah (printer tidak rewind; eject memajukan label berikutnya → kosong).
///  5. Tanpa GAPDETECT otomatis di job cetak — posisi sudah benar setelah job sebelumnya.
abstract final class StockLabelTspl {
  StockLabelTspl._();

  static const int _dpi = 203;

  /// Default jarak antar-label (celah die-cut) pada roll gap Yupo, mm.
  static const double kDefaultGapMm = 3.0;

  static const int _fontBaseCharWidthDots = 8;
  static const int _fontBaseCharHeightDots = 12;

  static int mmToDots(double mm) => (mm * _dpi / 25.4).round();

  /// Xprinter TSPL mengharapkan CRLF; LF saja kadang diabaikan firmware.
  static Uint8List _encodeTspl(String commands) {
    final normalized = commands.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
    return Uint8List.fromList(utf8.encode(normalized));
  }

  static String _esc(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

  static String _truncate(String value, int maxChars) {
    final t = value.trim();
    if (t.length <= maxChars) return t;
    return '${t.substring(0, maxChars - 1)}…';
  }

  static int get _headWidthDots => mmToDots(StockLabelGeometry.headPrintableWidthMm);

  static int get _headHeightDots => mmToDots(StockLabelGeometry.headPrintableHeightMm);

  /// Batas maksimum jarak pencarian gap oleh sensor (mm).
  /// 4× pitch agar sensor tidak runaway jika gap terlewat.
  static double _limitFeedMm(StockLabelTsplSettings settings) =>
      (StockLabelGeometry.tsplMediaHeightMm + settings.gapMm) * 4;

  /// Setup media + anchor origin kepala.
  ///
  /// Tidak ada HOME/FORMFEED di sini — XP-TT426B adalah TSPL2 di mana
  /// HOME feeds FORWARD (skip label). SET TEAR OFF + PRINT menangani
  /// posisi via gap sensor tanpa feed ekstra ke tear bar antar sesi.
  static String _jobHeader(StockLabelTsplSettings settings) {
    final refLeftMm = StockLabelGeometry.tsplHeadLeftMm + settings.calibrationOffsetXMm;
    final refTopMm = settings.calibrationOffsetYMm;
    final refX = mmToDots(refLeftMm);
    final refY = mmToDots(refTopMm);

    return '''
SIZE ${StockLabelGeometry.tsplMediaWidthMm} mm,${StockLabelGeometry.tsplMediaHeightMm} mm
GAP ${settings.gapMm} mm,0 mm
SPEED ${settings.speed}
DENSITY ${settings.density}
DIRECTION 1,0
REFERENCE $refX,$refY
OFFSET 0 mm
SET TEAR OFF
SET PEEL OFF
SET CUTTER OFF
LIMITFEED ${_limitFeedMm(settings).toStringAsFixed(0)} mm
''';
  }

  /// Kalibrasi gap sensor — **hanya sekali** saat ganti roll / printer nyala.
  /// Akan membuang beberapa label kosong (normal).
  static Uint8List buildGapCalibrationJob({StockLabelTsplSettings settings = const StockLabelTsplSettings()}) {
    final labelHDots = mmToDots(StockLabelGeometry.tsplMediaHeightMm);
    final gapDots = mmToDots(settings.gapMm);
    // TSPL: jangan kirim GAP bersamaan GAPDETECT — bisa konflik & feed berlebihan.
    final buf = StringBuffer()
      ..writeln(
        'SIZE ${StockLabelGeometry.tsplMediaWidthMm} mm,'
        '${StockLabelGeometry.tsplMediaHeightMm} mm',
      )
      ..writeln('GAPDETECT $labelHDots,$gapDots');
    return _encodeTspl(buf.toString());
  }

  /// Auto-posisi untuk roll baru / setelah buka cover printer dari posisi mana pun.
  ///
  /// Hanya GAPDETECT — HOME pada TSPL2 feed maju dan membuang label kosong.
  /// Panggil SEKALI saat pasang roll baru, lalu cetak normal.
  static Uint8List buildNewRollPositionJob({StockLabelTsplSettings settings = const StockLabelTsplSettings()}) {
    final labelHDots = mmToDots(StockLabelGeometry.tsplMediaHeightMm);
    final gapDots = mmToDots(settings.gapMm);
    final buf = StringBuffer()
      ..writeln(
        'SIZE ${StockLabelGeometry.tsplMediaWidthMm} mm,'
        '${StockLabelGeometry.tsplMediaHeightMm} mm',
      )
      ..writeln('DIRECTION 1,0')
      ..writeln('OFFSET 0 mm')
      ..writeln('LIMITFEED ${_limitFeedMm(settings).toStringAsFixed(0)} mm')
      ..writeln('GAPDETECT $labelHDots,$gapDots');
    return _encodeTspl(buf.toString());
  }

  /// Pre-check posisi awal paper sebelum job print (tanpa cetak).
  static Uint8List buildPrePrintCheckJob({StockLabelTsplSettings settings = const StockLabelTsplSettings()}) {
    final labelHDots = mmToDots(StockLabelGeometry.tsplMediaHeightMm);
    final gapDots = mmToDots(settings.gapMm);
    final buf = StringBuffer()
      ..writeln(
        'SIZE ${StockLabelGeometry.tsplMediaWidthMm} mm,'
        '${StockLabelGeometry.tsplMediaHeightMm} mm',
      )
      ..writeln('DIRECTION 1,0')
      ..writeln('OFFSET 0 mm')
      ..writeln('LIMITFEED ${_limitFeedMm(settings).toStringAsFixed(0)} mm')
      ..writeln('GAPDETECT $labelHDots,$gapDots');
    return _encodeTspl(buf.toString());
  }

  static int _maxCharsForZone(int zoneLeft, int zoneRight, {int xMul = 1}) {
    final zoneW = (zoneRight - zoneLeft).clamp(0, 10000);
    final charW = _fontBaseCharWidthDots * xMul;
    return (zoneW / charW).floor().clamp(4, 40);
  }

  /// Tinggi vertikal zona konten — sama dengan slot QR (9 mm) atau barcode (8 mm).
  static int _contentBandHeightDots(StockLabelCodeLayout layout) {
    if (layout.showQr) return mmToDots(kStockLabelQrMm);
    return mmToDots(kStockLabelBarcodeHeightMm);
  }

  /// Skala font TSPL "1" agar [lineCount] baris memenuhi [bandHeightDots].
  static ({
    int yMul,
    int xMul,
    int lineHeightDots,
    int charHeightDots,
  }) _fitTextMetrics(int bandHeightDots, int lineCount) {
    for (final yMul in [2, 1]) {
      final charH = _fontBaseCharHeightDots * yMul;
      if (lineCount <= 0) break;
      if (lineCount == 1) {
        if (charH <= bandHeightDots) {
          return (
            yMul: yMul,
            xMul: 1,
            lineHeightDots: charH,
            charHeightDots: charH,
          );
        }
        continue;
      }
      final step = ((bandHeightDots - charH) / (lineCount - 1)).floor();
      if (step < (charH * 2 / 3).floor()) continue;
      final blockH = charH + (lineCount - 1) * step;
      if (blockH <= bandHeightDots) {
        return (
          yMul: yMul,
          xMul: 1,
          lineHeightDots: step,
          charHeightDots: charH,
        );
      }
    }
    return (
      yMul: 1,
      xMul: 1,
      lineHeightDots: 15,
      charHeightDots: _fontBaseCharHeightDots,
    );
  }

  static int _bandTopY(int bandHeightDots) => _yFromBottomDots(bandHeightDots);

  static ({int narrow, int wide}) _barcodeModuleWidthForPayload(String payload) {
    final len = payload.trim().length;
    if (len <= 8) return (narrow: 2, wide: 4);
    if (len <= 12) return (narrow: 2, wide: 3);
    return (narrow: 1, wide: 2);
  }

  /// Perkiraan jumlah modul QR (EC level M) dari panjang payload.
  static int _estimatedQrModules(String payload) {
    final len = payload.trim().length;
    if (len <= 6) return 21;
    if (len <= 10) return 25;
    if (len <= 14) return 29;
    if (len <= 20) return 33;
    return 37;
  }

  /// Module 3 (~9mm) untuk kode pendek; turun ke 2 jika tidak muat band 9mm.
  static int _qrModuleSizeForPayload(String payload) {
    final modules = _estimatedQrModules(payload);
    final bandDots = mmToDots(kStockLabelQrMm);
    if (modules * 3 <= bandDots) return 3;
    if (modules * 2 <= bandDots) return 2;
    return 1;
  }

  static int _codeYInBand(int bandTopY, int bandH, int elementH) {
    if (elementH >= bandH) return bandTopY + bandH - elementH;
    return bandTopY + ((bandH - elementH) / 2).round();
  }

  /// Y (dots) agar elemen [elementHeightDots] rapat ke bawah kepala.
  static int _yFromBottomDots(int elementHeightDots) {
    final bottomPad = mmToDots(_kContentBottomMarginMm);
    return (_headHeightDots - bottomPad - elementHeightDots)
        .clamp(0, _headHeightDots - elementHeightDots);
  }

  static void _writeTextBlockInHead(
    StringBuffer buf, {
    required List<String> lines,
    required int zoneLeft,
    required int bandHeightDots,
  }) {
    if (lines.isEmpty) return;

    final metrics = _fitTextMetrics(bandHeightDots, lines.length);
    var y = _bandTopY(bandHeightDots);

    for (final line in lines) {
      buf.writeln(
        'TEXT $zoneLeft,$y,"1",0,${metrics.xMul},${metrics.yMul},"${_esc(line)}"',
      );
      y += metrics.lineHeightDots;
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
    final textZoneW = mmToDots(StockLabelGeometry.headTextZoneWidthMm);
    final codeZoneLeft = textZoneW;
    final codeZoneW = mmToDots(StockLabelGeometry.headCodeZoneWidthMm);
    final codeBlockW = mmToDots(layout.totalWidthMm);
    final textPad = mmToDots(_kTextPadMm);
    final textZoneLeft = textPad;
    final textZoneRight = textZoneW - textPad;
    if (textZoneRight <= textZoneLeft) return null;
    final bandH = _contentBandHeightDots(layout);
    final textMetrics = _fitTextMetrics(bandH, 3);
    final maxTextChars = _maxCharsForZone(
      textZoneLeft,
      textZoneRight,
      xMul: textMetrics.xMul,
    );

    final textLines = stockLabelTextLines(
      payload: payload,
      purity: purity,
      weight: weight,
    ).map((line) => _truncate(line, maxTextChars)).toList();

    final qrDots = mmToDots(kStockLabelQrMm);
    final barH = mmToDots(kStockLabelBarcodeHeightMm);
    final codeGap = mmToDots(_kCodeGapMm);
    final bandTopY = _bandTopY(bandH);

    final buf = StringBuffer();
    buf.writeln('CLS');

    _writeTextBlockInHead(
      buf,
      lines: textLines,
      zoneLeft: textZoneLeft,
      bandHeightDots: bandH,
    );

    var codeX = codeZoneLeft + ((codeZoneW - codeBlockW) / 2).round();
    final includeBarcode = layout.showBarcode;

    if (layout.showQr) {
      final qrModule = _qrModuleSizeForPayload(payload);
      final qrHeightDots = _estimatedQrModules(payload) * qrModule;
      final qrY = _codeYInBand(bandTopY, bandH, qrHeightDots);
      buf.writeln(
        'QRCODE $codeX,$qrY,M,$qrModule,A,0,M2,S3,"${_esc(payload)}"',
      );
      if (includeBarcode) {
        codeX += qrDots + codeGap;
      }
    }

    if (includeBarcode) {
      final barY = _codeYInBand(bandTopY, bandH, barH);
      final module = _barcodeModuleWidthForPayload(payload);
      buf.writeln(
        'BARCODE $codeX,$barY,"128",$barH,0,0,${module.narrow},${module.wide},"${_esc(payload)}"',
      );
    }

    buf.writeln('PRINT 1,1');
    return buf.toString();
  }

  /// Label uji: kotak + garis tengah zona kepala — untuk kalibrasi offset.
  static Uint8List buildCalibrationSample({
    StockLabelTsplSettings settings = const StockLabelTsplSettings(),
  }) {
    final w = _headWidthDots;
    final h = _headHeightDots;
    final buf = StringBuffer(_jobHeader(settings))
      ..writeln('CLS')
      ..writeln('BOX 0,0,$w,$h,2')
      ..writeln('BAR $w,0,$w,$h')
      ..writeln('TEXT 2,2,"1",0,1,1,"ATAS-KIRI"')
      ..writeln('TEXT 2,${h - 14},"1",0,1,1,"BAWAH"')
      ..writeln('PRINT 1,1');
    return _encodeTspl(buf.toString());
  }

  static String buildOne({
    required String payload,
    required String titleLine,
    required StockLabelPrintChoice format,
    String? weight,
    String? purity,
    StockLabelTsplSettings settings = const StockLabelTsplSettings(),
  }) {
    final body = _buildLabelBody(
      payload: payload,
      titleLine: titleLine,
      format: format,
      weight: weight,
      purity: purity,
    );
    if (body == null) return '';
    // Satu label = label terakhir → posisikan di tear bar tanpa FEED eject.
    return '${_jobHeader(settings)}SET TEAR ON\n$body';
  }

  static Uint8List buildBatch({
    required List<({
      String payload,
      String titleLine,
      StockLabelPrintChoice format,
      String? weight,
      String? purity,
    })> labels,
    StockLabelTsplSettings settings = const StockLabelTsplSettings(),
  }) {
    final bodies = <String>[];
    for (final label in labels) {
      final body = _buildLabelBody(
        payload: label.payload,
        titleLine: label.titleLine,
        format: label.format,
        weight: label.weight,
        purity: label.purity,
      );
      if (body != null) bodies.add(body);
    }

    final buf = StringBuffer(_jobHeader(settings));
    for (var i = 0; i < bodies.length; i++) {
      if (i == bodies.length - 1) buf.writeln('SET TEAR ON');
      buf.write(bodies[i]);
    }
    return _encodeTspl(buf.toString());
  }
}

// Teks: inset kiri — sudut die-cut leher memotong huruf jika terlalu kiri.
const double _kTextPadMm = 3.0;

// Jarak tepi bawah kepala ke dasar band konten (+ tsplCalibrationOffsetYMm).
const double _kContentBottomMarginMm = 0.5;

const double _kCodeGapMm = 1.0;
