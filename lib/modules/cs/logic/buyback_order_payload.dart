/// Input form buyback untuk dibangun menjadi payload POST /orders.
class BuybackOrderFormInput {
  const BuybackOrderFormInput({
    required this.orderNumber,
    required this.notaLama,
    required this.nomorNota,
    required this.customerId,
    required this.branchId,
    required this.userId,
    required this.selectedItemId,
    required this.namaItem,
    required this.berat,
    required this.material,
    required this.kadar,
    required this.hargaPerGram,
    required this.kategori,
    required this.jenis,
    required this.notaJual,
    required this.selectedTipeBarang,
    required this.tipe,
    required this.kodeProduk,
    required this.qty,
    required this.hargaBeli,
    required this.fotoUrl,
    required this.kondisiFisik,
    required this.penyesuaianBerat,
    required this.nilaiUntungRugi,
    required this.notaJualStatus,
    required this.potonganKondisi,
    required this.nilaiResale,
    required this.untungRugi,
    required this.catatanKondisi,
  });

  final String orderNumber;
  final String notaLama;
  final String nomorNota;
  final dynamic customerId;
  final int branchId;
  final int userId;
  final dynamic selectedItemId;
  final String namaItem;
  final String berat;
  final String material;
  final String kadar;
  final String hargaPerGram;
  final String kategori;
  final String jenis;
  final String notaJual;
  final String? selectedTipeBarang;
  final String tipe;
  final String kodeProduk;
  final int qty;
  final double hargaBeli;
  final String fotoUrl;
  final String kondisiFisik;
  final String penyesuaianBerat;
  final String nilaiUntungRugi;
  final String notaJualStatus;
  final String potonganKondisi;
  final String nilaiResale;
  final String untungRugi;
  final String catatanKondisi;
}

abstract final class BuybackOrderPayloadBuilder {
  BuybackOrderPayloadBuilder._();

  static Map<String, dynamic> build(BuybackOrderFormInput input) {
    final subtotal = input.hargaBeli * input.qty;
    return {
      'order_type': 'buyback',
      'order_number': input.orderNumber.isNotEmpty ? input.orderNumber : null,
      'nota_lama': input.notaLama.isEmpty ? null : input.notaLama,
      'reference_order_number': input.nomorNota.isEmpty
          ? (input.notaLama.isEmpty ? null : input.notaLama)
          : input.nomorNota,
      'customer_id': input.customerId,
      'branch_id': input.branchId,
      'user_id': input.userId,
      'mode': 'TOKO',
      'diskon': 0,
      'order_items': [
        {
          'item_id': input.selectedItemId,
          'nama_item': input.namaItem,
          'weight': double.tryParse(input.berat) ?? 0,
          'material': input.material,
          'purity': input.kadar,
          'harga_per_gram': double.tryParse(input.hargaPerGram) ?? 0,
          'kategori': input.kategori,
          'jenis': input.jenis,
          'tipe': input.notaJualStatus == 'TIDAK_ADA'
              ? (input.selectedTipeBarang ?? '')
              : input.tipe,
          'kode_produk': input.kodeProduk,
          'qty': input.qty,
          'subtotal': subtotal,
          'total': subtotal,
          'diskon': 0,
          'photo_produk': input.fotoUrl,
          'kondisi_barang': {
            'kondisi_fisik': input.kondisiFisik,
            'berat_akhir': double.tryParse(input.berat),
            'penyesuaian_berat': double.tryParse(input.penyesuaianBerat) ?? 0,
            'harga_per_gram': double.tryParse(input.hargaPerGram) ?? 0,
            'nilai_untung_rugi': input.nilaiUntungRugi,
            'nota_jual': input.nomorNota.isEmpty ? input.notaLama : input.nomorNota,
            'nota_jual_status': input.notaJualStatus,
            'potongan_kondisi': double.tryParse(input.potonganKondisi) ?? 0,
            'nilai_resale': double.tryParse(input.nilaiResale) ?? 0,
            'harga_beli': input.hargaBeli,
            'untung_rugi': input.untungRugi,
            'catatan_kondisi': input.catatanKondisi,
          },
        },
      ],
    };
  }
}
