import 'package:flutter_test/flutter_test.dart';
import 'package:vanessa3/utils/stock_label_geometry.dart';

void main() {
  test('jewelry label dimensions are internally consistent', () {
    expect(StockLabelGeometry.dimensionsConsistent, isTrue);
    expect(StockLabelGeometry.headPrintableLeftMm, 32);
    expect(StockLabelGeometry.headPrintableRightMm, 77);
    expect(StockLabelGeometry.tsplHeadLeftMm, 29);
    expect(StockLabelGeometry.tsplMediaWidthMm, 74);
    expect(StockLabelGeometry.headPrintableWidthMm, 45);
    expect(StockLabelGeometry.headTextZoneWidthMm, 23);
    expect(StockLabelGeometry.headCodeZoneWidthMm, 22);
    expect(StockLabelGeometry.headCodeZoneLeftMm, 55);
    expect(StockLabelGeometry.printableHeightMm, 12);
  });
}
