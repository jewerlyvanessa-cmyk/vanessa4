import 'package:vanessa3/modules/cs/logic/jual_form_utils.dart';

/// Snapshot field form jual setelah pilih item dari stok.
class JualStockItemSnapshot {
  const JualStockItemSnapshot({
    required this.item,
    required this.itemCode,
    required this.namaItem,
    required this.berat,
    required this.material,
    required this.kadar,
    required this.kategori,
    required this.jenis,
    required this.tipe,
  });

  final Map<String, dynamic> item;
  final String itemCode;
  final String namaItem;
  final String berat;
  final String material;
  final String kadar;
  final String kategori;
  final String jenis;
  final String tipe;

  static JualStockItemSnapshot? fromStockItem(Map<String, dynamic> item) {
    if (!JualFormUtils.isSellableStockStatus(item['status']?.toString())) {
      return null;
    }
    return JualStockItemSnapshot(
      item: item,
      itemCode: (item['kode_produk'] ?? item['item_code'] ?? '').toString(),
      namaItem: (item['name'] ?? '').toString(),
      berat: item['weight']?.toString() ?? '',
      material: (item['material'] ?? '').toString(),
      kadar: (item['purity'] ?? '').toString(),
      kategori: (item['kategori'] ?? '').toString(),
      jenis: (item['jenis'] ?? '').toString(),
      tipe: (item['tipe'] ?? '').toString(),
    );
  }
}
