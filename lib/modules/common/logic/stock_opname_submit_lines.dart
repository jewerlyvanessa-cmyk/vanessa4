import 'package:vanessa3/modules/common/logic/stock_opname_item_utils.dart';
import 'package:vanessa3/utils/stock_inventory_search.dart';

/// Bangun baris submit POST /items/stock-opname dari state sesi opname.
abstract final class StockOpnameSubmitLines {
  StockOpnameSubmitLines._();

  static List<Map<String, dynamic>> missingChanges({
    required List<Map<String, dynamic>> scopeItems,
    required Set<String> missingIds,
  }) {
    final out = <Map<String, dynamic>>[];
    for (final m in scopeItems) {
      final id = StockOpnameItemUtils.itemIdStr(m);
      if (!missingIds.contains(id)) continue;

      final sys = stockItemQuantity(m);
      if (sys <= 0) continue;

      out.add({
        'item_id': int.tryParse(id) ?? m['item_id'],
        'counted_quantity': 0,
        'name': (m['name'] ?? '-').toString(),
        'kode': StockOpnameItemUtils.itemCode(m),
        'system_quantity': sys,
        'delta': -sys,
        'kind': 'missing',
      });
    }
    return out;
  }

  static List<Map<String, dynamic>> verifiedLines({
    required List<Map<String, dynamic>> scopeItems,
    required Set<String> verifiedIds,
  }) {
    final out = <Map<String, dynamic>>[];
    for (final m in scopeItems) {
      final id = StockOpnameItemUtils.itemIdStr(m);
      if (!verifiedIds.contains(id)) continue;
      final sys = stockItemQuantity(m);
      out.add({
        'item_id': int.tryParse(id) ?? m['item_id'],
        'counted_quantity': sys,
        'verified': true,
        'name': (m['name'] ?? '-').toString(),
        'kode': StockOpnameItemUtils.itemCode(m),
        'kind': 'verified',
      });
    }
    return out;
  }

  static List<Map<String, dynamic>> allSubmitLines({
    required List<Map<String, dynamic>> scopeItems,
    required Set<String> verifiedIds,
    required Set<String> missingIds,
  }) {
    return [
      ...missingChanges(scopeItems: scopeItems, missingIds: missingIds),
      ...verifiedLines(scopeItems: scopeItems, verifiedIds: verifiedIds),
    ];
  }
}
