import 'package:vanessa3/utils/stock_inventory_search.dart';

/// Helper kode/id item untuk stok opname.
abstract final class StockOpnameItemUtils {
  StockOpnameItemUtils._();

  static bool branchIsActive(Map<String, dynamic> b) {
    final s = (b['status'] ?? 'active').toString().trim().toLowerCase();
    return s.isEmpty || s == 'active';
  }

  static String normalizeScanCode(String raw) {
    final candidate = raw
        .trim()
        .split('\n')
        .first
        .trim()
        .split(RegExp(r'\s*[-–]\s*'))
        .first
        .trim();
    return normalizeStockSearchQuery(candidate).toLowerCase();
  }

  static String itemCode(Map<String, dynamic> m) =>
      (m['item_code'] ?? m['kode_produk'] ?? '').toString().trim();

  static String itemIdStr(Map<String, dynamic> m) =>
      (m['item_id'] ?? '').toString();
}
