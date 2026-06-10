/// Dimensi fisik label jewelry Yupo pada roll thermal 80×12 mm.
///
/// Dua sistem koordinat:
/// - **PDF / web** — kanvas penuh roll 80 mm (termasuk tepi backing 3 mm).
/// - **TSPL / printer** — media die-cut 74 mm; origin printer = tepi kiri die-cut.
///
/// ```
/// roll 80mm:  |←3→|←—— ekor 29 ——→|←—— kepala 45 ——→|←3→|
/// die-cut 74:       |←—— ekor 29 ——→|←—— kepala 45 ——→|
/// PDF cetak @32–77mm roll  |  TSPL cetak @29–74mm die-cut (REFERENCE)
/// ```
abstract final class StockLabelGeometry {
  StockLabelGeometry._();

  static const double totalWidthMm = 80;
  static const double totalHeightMm = 12;

  static const double marginLeftMm = 3;
  static const double marginRightMm = 3;
  static const double marginTopMm = 1;
  static const double marginBottomMm = 1;

  /// Ekor + kepala (tanpa tepi kiri/kanan backing).
  static const double bodyWidthMm = 74;

  static const double tailWidthMm = 29;

  /// Kepala kiri (leher) + kepala kanan (bendera).
  static const double headTotalWidthMm = 45;

  static const double headNeckWidthMm = 23;

  static const double headBannerWidthMm = 22;

  /// Zona kepala kiri: teks.
  static const double headTextZoneWidthMm = headNeckWidthMm;

  /// Zona kepala kanan: QR / barcode.
  static const double headCodeZoneWidthMm = headBannerWidthMm;

  static const double headPrintableWidthMm = headTotalWidthMm;

  static const double headPrintableHeightMm = totalHeightMm;

  /// PDF: offset dari tepi kiri roll.
  static const double headPrintableLeftMm = marginLeftMm + tailWidthMm;

  static const double headPrintableRightMm =
      headPrintableLeftMm + headPrintableWidthMm;

  static const double headTextZoneLeftMm = headPrintableLeftMm;

  static const double headCodeZoneLeftMm =
      headTextZoneLeftMm + headTextZoneWidthMm;

  static const double headPrintableTopMm = 0;

  static const double printableHeightMm = headPrintableHeightMm;

  // ── TSPL (die-cut 74 mm, origin = tepi kiri label tempel) ───────────────

  static const double tsplMediaWidthMm = bodyWidthMm;

  static const double tsplMediaHeightMm = totalHeightMm;

  /// Offset X kepala dari origin die-cut (= lebar ekor).
  static const double tsplHeadLeftMm = tailWidthMm;

  static const double tsplHeadRightMm = bodyWidthMm;

  /// Dalam koordinat TSPL (origin di tepi kiri die-cut):
  /// teks = 29..52 mm, kode = 52..74 mm.
  static const double tsplTextZoneLeftMm = tsplHeadLeftMm;
  static const double tsplCodeZoneLeftMm =
      tsplTextZoneLeftMm + headTextZoneWidthMm;

  /// Fine-tune setelah uji cetak fisik (mm).
  /// Geser ke kanan: naikkan [tsplCalibrationOffsetXMm].
  /// Geser ke bawah: naikkan [tsplCalibrationOffsetYMm].
  static const double tsplCalibrationOffsetXMm = 0;
  static const double tsplCalibrationOffsetYMm = 0;

  static const double tsplReferenceLeftMm =
      tsplHeadLeftMm + tsplCalibrationOffsetXMm;

  static const double tsplReferenceTopMm = tsplCalibrationOffsetYMm;

  static bool get dimensionsConsistent =>
      marginLeftMm + bodyWidthMm + marginRightMm == totalWidthMm &&
      tailWidthMm + headTotalWidthMm == bodyWidthMm &&
      headNeckWidthMm + headBannerWidthMm == headTotalWidthMm &&
      headPrintableRightMm + marginRightMm == totalWidthMm &&
      tsplHeadLeftMm + headTotalWidthMm == tsplMediaWidthMm;
}
