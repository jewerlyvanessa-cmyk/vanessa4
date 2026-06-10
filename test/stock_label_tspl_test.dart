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
    expect(job, isNot(contains('\nHOME\n')));
    expect(job, contains('SET TEAR ON'));
    // BACKFEED eksplisit di header untuk retrak simetris
    expect(job, contains('BACKFEED '));
    expect(job, contains('QRCODE'));

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
    expect(job, contains('FEED '));
  });

  test('pre-print check job homes paper without printing', () {
    final precheck = String.fromCharCodes(StockLabelTspl.buildPrePrintCheckJob());
    expect(precheck, contains('HOME'));
    expect(precheck, isNot(contains('PRINT')));
  });

  test('gap calibration job includes GAPDETECT only', () {
    final text = String.fromCharCodes(StockLabelTspl.buildGapCalibrationJob());
    expect(text, contains('GAPDETECT'));
    expect(text, isNot(contains('PRINT')));
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
}
