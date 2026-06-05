/// Snapshot field form buyback setelah pilih item dari order jual lama.
class BuybackItemFormSnapshot {
  const BuybackItemFormSnapshot({
    required this.selectedItem,
    required this.notaJual,
    required this.namaItem,
    required this.berat,
    required this.material,
    required this.kadar,
    required this.kategori,
    required this.jenis,
    required this.tipe,
    required this.selectedTipeBarang,
    required this.quantity,
    required this.hargaBeli,
    required this.hargaPerGram,
    required this.kodeProduk,
  });

  final Map<String, dynamic> selectedItem;
  final String notaJual;
  final String namaItem;
  final String berat;
  final String material;
  final String kadar;
  final String kategori;
  final String jenis;
  final String tipe;
  final String? selectedTipeBarang;
  final String quantity;
  final String hargaBeli;
  final String hargaPerGram;
  final String kodeProduk;

  static BuybackItemFormSnapshot fromOrderItem(
    Map<String, dynamic> item, {
    required String nomorNota,
  }) {
    final namaItem =
        item['nama_item'] ?? item['item_name'] ?? item['name'] ?? '';
    final berat = (item['weight'] ?? item['item_weight'] ?? 0).toString();
    final material =
        ((item['material'] ?? '').toString().trim().isNotEmpty
                ? item['material']
                : item['item_material'] ?? '')
            .toString();
    final kadar =
        ((item['purity'] ?? '').toString().trim().isNotEmpty
                ? item['purity']
                : item['item_purity'] ?? '')
            .toString();
    final kategori = item['kategori'] ?? item['item_kategori'] ?? '';
    final jenis = item['jenis'] ?? item['item_jenis'] ?? '';
    final tipe = item['tipe'] ?? item['item_tipe'] ?? '';
    final selectedTipeBarang = item['tipe'] ?? item['item_tipe'];
    final quantity = (item['qty'] ?? item['quantity'] ?? 1).toString();
    final hargaBeli =
        (item['total'] ?? item['harga_per_gram'] ?? item['harga_beli'] ?? 0)
            .toString();
    final hargaPerGram = (item['harga_per_gram'] ?? 0).toString();
    final kodeProduk = item['kode_produk'] ?? item['item_kode'] ?? '';

    return BuybackItemFormSnapshot(
      selectedItem: item,
      notaJual: nomorNota.isNotEmpty ? 'ADA' : 'TIDAK_ADA',
      namaItem: namaItem.toString(),
      berat: berat,
      material: material,
      kadar: kadar,
      kategori: kategori.toString(),
      jenis: jenis.toString(),
      tipe: tipe.toString(),
      selectedTipeBarang: selectedTipeBarang?.toString(),
      quantity: quantity,
      hargaBeli: hargaBeli,
      hargaPerGram: hargaPerGram.toString(),
      kodeProduk: kodeProduk.toString(),
    );
  }
}
