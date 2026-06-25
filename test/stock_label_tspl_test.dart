import 'package:flutter_test/flutter_test.dart';
import 'package:vanessa3/utils/stock_item_qr_print.dart';
import 'package:vanessa3/utils/stock_label_geometry.dart';
import 'package:vanessa3/utils/stock_label_tspl.dart';

void main() {
  test('TSPL job uses die-cut 74mm and REFERENCE at kepala', () {
    final job = StockLabelTspl.buildOne(
      payload: 'TEST-001',
      titleLine: 'Cincin',
      format: StockLabelPrintChoice.qr,
    );
    expect(job, contains('SIZE 74.0 mm,12.0 mm'));
    expect(job, isNot(contains('GAPDETECT')));
    // TSPL2: HOME feeds FORWARD → skip label. Tidak dipakai di print job.
    // SET TEAR OFF: berhenti di gap tanpa feed ekstra ke tear bar antar sesi.
    expect(job, isNot(contains('HOME')));
    expect(job, isNot(contains('BACKFEED')));
    expect(job, isNot(contains('BACKUP')));
    expect(job, contains('SET TEAR OFF'));
    expect(job, isNot(contains('SET TEAR ON')));
    expect(job, contains('QRCODE'));
    expect(job, contains('GAP 3.0 mm,0 mm'));
    expect(job, isNot(matches(RegExp(r'PRINT 1,1\r?\nFEED'))));

    final textX = int.parse(
      RegExp(r'TEXT (\d+),').firstMatch(job)!.group(1)!,
    );
    final qrX = int.parse(
      RegExp(r'QRCODE (\d+),').firstMatch(job)!.group(1)!,
    );
    final zoneSplitX =
        (StockLabelGeometry.headTextZoneWidthMm * 203 / 25.4).round();
    expect(textX, lessThan(zoneSplitX));
    expect(qrX, greaterThanOrEqualTo(zoneSplitX));
  });

  test('pre-print check job gap-detects without printing', () {
    final precheck =
        String.fromCharCodes(StockLabelTspl.buildPrePrintCheckJob());
    expect(precheck, contains('GAPDETECT'));
    expect(precheck, isNot(contains('HOME')));
    expect(precheck, isNot(contains('PRINT')));
    // TSPL: GAP + GAPDETECT bersamaan bisa feed berlebihan.
    expect(precheck, isNot(contains(RegExp(r'\nGAP \d'))));
  });

  test('gap calibration job includes GAPDETECT only', () {
    final text = String.fromCharCodes(StockLabelTspl.buildGapCalibrationJob());
    expect(text, contains('GAPDETECT'));
    expect(text, isNot(contains('PRINT')));
    expect(text, isNot(contains(RegExp(r'\nGAP \d'))));
  });

  test('code layout always fits right head zone', () {
    const padMm = 0.8;
    final zoneInner = StockLabelGeometry.headCodeZoneWidthMm - (2 * padMm);
    for (final format in StockLabelPrintChoice.values) {
      final layout = stockLabelResolveCodeLayout(format);
      expect(layout.totalWidthMm, lessThanOrEqualTo(zoneInner));
    }
  });

  test('barcode module width scales by payload length', () {
    final short = StockLabelTspl.buildOne(
      payload: 'C006',
      titleLine: 'Cincin',
      format: StockLabelPrintChoice.barcode,
    );
    expect(short, contains('BARCODE'));
    expect(short, contains(',2,4,"C006"'));

    final long = StockLabelTspl.buildOne(
      payload: 'CODE-PRODUK-001234',
      titleLine: 'Cincin',
      format: StockLabelPrintChoice.barcode,
    );
    expect(long, contains('BARCODE'));
    expect(long, contains(',1,2,"CODE-PRODUK-001234"'));
  });

  test('calibration sample draws box in head zone', () {
    final bytes = StockLabelTspl.buildCalibrationSample();
    final text = String.fromCharCodes(bytes);
    expect(text, contains('BOX 0,0,'));
    expect(text, contains('ATAS-KIRI'));
  });

  test('text band matches 9mm QR slot with double-height font', () {
    final job = StockLabelTspl.buildOne(
      payload: 'C006',
      titleLine: 'Cincin',
      format: StockLabelPrintChoice.qr,
    );
    // 9mm band → 3 lines @ y×2 (24+24+24 = 72 dots).
    expect(job, matches(RegExp(r'TEXT \d+,\d+,"1",0,1,2,')));

    final textY = int.parse(
      RegExp(r'TEXT \d+,(\d+),').firstMatch(job)!.group(1)!,
    );
    final qrY = int.parse(
      RegExp(r'QRCODE \d+,(\d+),').firstMatch(job)!.group(1)!,
    );
    final bandTop = (12 * 203 / 25.4).round() -
        (0.5 * 203 / 25.4).round() -
        (9 * 203 / 25.4).round();
    expect(textY, bandTop);
    expect(qrY, greaterThanOrEqualTo(bandTop));
    expect(job, contains(',M,3,A,0,M2,S3,"C006"'));
  });

  test('barcode-only text band matches 8mm barcode height', () {
    final job = StockLabelTspl.buildOne(
      payload: 'C006',
      titleLine: 'Cincin',
      format: StockLabelPrintChoice.barcode,
    );
    expect(job, matches(RegExp(r'TEXT \d+,\d+,"1",0,1,2,')));

    final textY = int.parse(
      RegExp(r'TEXT \d+,(\d+),').firstMatch(job)!.group(1)!,
    );
    final barY = int.parse(
      RegExp(r'BARCODE \d+,(\d+),').firstMatch(job)!.group(1)!,
    );
    expect(textY, barY);
  });

  test('job ends at PRINT without extra FEED that skips labels', () {
    final job = StockLabelTspl.buildOne(
      payload: 'X',
      titleLine: 'X',
      format: StockLabelPrintChoice.qr,
    );
    expect(job.trimRight(), endsWith('PRINT 1,1'));
    expect(job, isNot(contains('\nFEED ')));
  });

  test('REFERENCE Y includes calibration offset for bottom alignment', () {
    final job = StockLabelTspl.buildOne(
      payload: 'X',
      titleLine: 'X',
      format: StockLabelPrintChoice.qr,
    );
    final refY = int.parse(
      RegExp(r'REFERENCE \d+,(\d+)').firstMatch(job)!.group(1)!,
    );
    final expectedY = (StockLabelGeometry.tsplCalibrationOffsetYMm * 203 / 25.4)
        .round();
    expect(refY, expectedY);
  });

  test('barcode-only job includes BARCODE not QRCODE', () {
    final job = StockLabelTspl.buildOne(
      payload: 'BRK-001',
      titleLine: 'Gelang',
      format: StockLabelPrintChoice.barcode,
      purity: '8k',
      weight: '3.45 g',
    );
    expect(job, contains('BARCODE'));
    expect(job, isNot(contains('QRCODE')));
    expect(job, contains('Kode: BRK-001'));
  });

  test('QR 9mm layout uses module 3 for short codes, 2 for long', () {
    final short = StockLabelTspl.buildOne(
      payload: 'C006',
      titleLine: 'Cincin',
      format: StockLabelPrintChoice.qr,
    );
    expect(short, contains('QRCODE'));
    expect(short, contains(',M,3,A,0,M2,S3,"C006"'));

    final medium = StockLabelTspl.buildOne(
      payload: 'BRK-001',
      titleLine: 'Gelang',
      format: StockLabelPrintChoice.qr,
    );
    expect(medium, contains(',M,2,A,0,M2,S3,"BRK-001"'));

    final long = StockLabelTspl.buildOne(
      payload: 'CODE-PRODUK-001234',
      titleLine: 'Gelang',
      format: StockLabelPrintChoice.qr,
    );
    expect(long, contains(',M,2,A,0,M2,S3,"CODE-PRODUK-001234"'));
  });

  test('new roll job uses GAPDETECT only without HOME', () {
    final text = String.fromCharCodes(StockLabelTspl.buildNewRollPositionJob());
    expect(text, contains('GAPDETECT'));
    expect(text, isNot(contains('HOME')));
    expect(text, isNot(contains('PRINT')));
    expect(text, isNot(contains(RegExp(r'\nGAP \d'))));
    expect(text, contains('LIMITFEED'));
  });

  test('TSPL jobs use CRLF line endings', () {
    final bytes = StockLabelTspl.buildBatch(
      labels: [
        (
          payload: 'X',
          titleLine: 'X',
          format: StockLabelPrintChoice.qr,
          weight: null,
          purity: null,
        ),
      ],
    );
    expect(bytes, contains(13)); // CR
    expect(bytes, contains(10)); // LF
    expect(String.fromCharCodes(bytes), contains('SIZE 74.0 mm,12.0 mm\r\n'));
  });

  test('job header has LIMITFEED, no BACKUP/BACKFEED/HOME in header', () {
    final headerOnly = StockLabelTspl.buildOne(
      payload: 'X',
      titleLine: 'X',
      format: StockLabelPrintChoice.qr,
    ).split('CLS').first;
    expect(headerOnly, contains('LIMITFEED'));
    expect(headerOnly, isNot(contains('BACKFEED')));
    expect(headerOnly, isNot(contains('BACKUP ')));
    expect(headerOnly, isNot(contains('\nHOME\n')));
  });
}
