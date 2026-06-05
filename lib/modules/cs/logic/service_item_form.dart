/// Snapshot field item service setelah pilih dari order jual lama.
class ServiceItemFormSnapshot {
  const ServiceItemFormSnapshot({
    required this.namaItem,
    required this.berat,
    required this.material,
    required this.kadar,
  });

  final String namaItem;
  final String berat;
  final String material;
  final String kadar;

  static ServiceItemFormSnapshot fromOrderItem(Map<String, dynamic> item) {
    final namaItem =
        item['nama_item'] ?? item['item_name'] ?? item['name'] ?? '';
    final berat = (item['weight'] ?? item['item_weight'] ?? 0).toString();
    final material =
        (item['material'] != null && item['material'].toString().isNotEmpty)
            ? item['material']
            : (item['item_material'] ?? '');
    final kadar =
        (item['purity'] != null && item['purity'].toString().isNotEmpty)
            ? item['purity']
            : (item['item_purity'] ?? '');

    return ServiceItemFormSnapshot(
      namaItem: namaItem.toString(),
      berat: berat,
      material: material.toString(),
      kadar: kadar.toString(),
    );
  }
}
