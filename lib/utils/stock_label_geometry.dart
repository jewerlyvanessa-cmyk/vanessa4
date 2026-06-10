/// Dimensi fisik label jewelry Yupo pada roll thermal 80×12 mm.
///
/// Zona cetak = seluruh kepala (kiri + kanan), 45×12 mm.
///
/// ```
/// |←3→|←——— ekor 29 ———→|←— kepala kiri 23 —→|← kepala kanan 22 →|←3→|
/// |    |   (tidak cetak)  |←—————— cetak 45×12 ————————————————→|    |
/// |←——————————————— 74 (body) ———————————————————————————————————→|
/// |←———————————————————— 80 total ———————————————————————————————→|
/// ```
abstract final class StockLabelGeometry {
  StockLabelGeometry._();

  static const double totalWidthMm = 80;
  static const double totalHeightMm = 12;

  static const double marginLeftMm = 3;
  static const double marginRightMm = 3;

  /// Tepi backing atas/bawah (bukan mengurangi tinggi kepala).
  static const double marginTopMm = 1;
  static const double marginBottomMm = 1;

  /// Ekor + kepala (tanpa tepi kiri/kanan backing).
  static const double bodyWidthMm = 74;

  static const double tailWidthMm = 29;

  /// Kepala kiri (leher) + kepala kanan (bendera).
  static const double headTotalWidthMm = 45;

  static const double headNeckWidthMm = 23;

  static const double headBannerWidthMm = 22;

  /// Zona cetak: kepala kiri + kanan, tinggi penuh label.
  static const double headPrintableWidthMm = headTotalWidthMm;

  static const double headPrintableHeightMm = totalHeightMm;

  /// Tepi kiri roll → tepi kiri zona cetak (setelah ekor).
  static const double headPrintableLeftMm = marginLeftMm + tailWidthMm;

  static const double headPrintableRightMm =
      headPrintableLeftMm + headPrintableWidthMm;

  static const double headPrintableTopMm = 0;

  /// Alias untuk layout PDF/TSPL.
  static const double printableHeightMm = headPrintableHeightMm;

  static bool get dimensionsConsistent =>
      marginLeftMm + bodyWidthMm + marginRightMm == totalWidthMm &&
      tailWidthMm + headTotalWidthMm == bodyWidthMm &&
      headNeckWidthMm + headBannerWidthMm == headTotalWidthMm &&
      headPrintableRightMm + marginRightMm == totalWidthMm;
}
