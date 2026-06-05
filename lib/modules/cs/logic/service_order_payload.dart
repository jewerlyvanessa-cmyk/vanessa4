/// Input form service untuk dibangun menjadi payload POST /orders.
class ServiceOrderFormInput {
  const ServiceOrderFormInput({
    required this.modeToko,
    required this.orderNumber,
    required this.branchId,
    required this.userId,
    required this.customerId,
    required this.namaItem,
    required this.generatedKodeProduk,
    required this.weightVal,
    required this.totalBiayaVal,
    required this.uangMukaVal,
    required this.fotoUrl,
    required this.jenisBarang,
    required this.jenisService,
    required this.material,
    required this.kadar,
    required this.notaLama,
    required this.kelengkapan,
    required this.keterangan,
    required this.estimasiSelesai,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.pickupBranchId,
  });

  final String modeToko;
  final String orderNumber;
  final int branchId;
  final int userId;
  final int customerId;
  final String namaItem;
  final String generatedKodeProduk;
  final double weightVal;
  final double totalBiayaVal;
  final double uangMukaVal;
  final String fotoUrl;
  final String jenisBarang;
  final String jenisService;
  final String material;
  final String kadar;
  final String notaLama;
  final Map<String, bool> kelengkapan;
  final String keterangan;
  final String estimasiSelesai;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final int? pickupBranchId;
}

abstract final class ServiceOrderPayloadBuilder {
  ServiceOrderPayloadBuilder._();

  static Map<String, dynamic> build(ServiceOrderFormInput input) {
    final orderData = <String, dynamic>{
      'order_type': 'service',
      'status': 'pending',
      'order_number':
          input.orderNumber.isNotEmpty ? input.orderNumber : null,
      'branch_id': input.branchId,
      'user_id': input.userId,
      'mode': input.modeToko.toLowerCase(),
      'customer_id': input.customerId,
      'service_estimated_total': input.totalBiayaVal,
      'service_dp_amount': input.uangMukaVal,
      'diskon': 0,
      'order_items': [
        {
          'nama_item': input.namaItem,
          'kode_produk': input.generatedKodeProduk,
          'weight': input.weightVal,
          'qty': 1,
          'harga_per_gram': 0,
          'manual_total': input.totalBiayaVal,
          'photo_produk': input.fotoUrl,
          'kategori': 'service',
          'jenis': input.jenisBarang,
          'tipe': input.jenisService,
          'material': input.material,
          'purity': input.kadar,
        },
      ],
      'nota_lama': input.notaLama,
      'reference_order_number':
          input.notaLama.isEmpty ? null : input.notaLama,
      'kelengkapan': input.kelengkapan,
      'keterangan': input.keterangan,
      'estimasi_selesai': input.estimasiSelesai,
      'customer_name': input.customerName,
      'customer_phone': input.customerPhone,
      'customer_address': input.customerAddress,
    };

    if (input.pickupBranchId != null &&
        input.pickupBranchId != input.branchId) {
      orderData['pickup_branch_id'] = input.pickupBranchId;
    }

    return orderData;
  }

  static Map<String, dynamic> buildFakturOverlay({
    required Map<String, dynamic> orderData,
    required double uangMukaVal,
  }) {
    final fakturOverlay = <String, dynamic>{...orderData};
    final itemsReq = orderData['order_items'];
    if (itemsReq is List && itemsReq.isNotEmpty && itemsReq.first is Map) {
      final first = Map<String, dynamic>.from(itemsReq.first as Map);
      final tipe = first['tipe']?.toString().trim();
      if (tipe != null && tipe.isNotEmpty) {
        fakturOverlay['jenis_service'] = tipe;
      }
    }
    if (uangMukaVal > 0) {
      fakturOverlay['service_dp_amount'] = uangMukaVal;
    }
    return fakturOverlay;
  }
}
