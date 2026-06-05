/// Input form custom untuk dibangun menjadi payload POST /orders.
class CustomOrderFormInput {
  const CustomOrderFormInput({
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
    required this.material,
    required this.kadar,
    required this.spesifikasi,
    required this.asalMaterial,
    required this.materialTambahan,
    required this.asalTambahan,
    required this.estimasiWaktu,
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
  final String? fotoUrl;
  final String jenisBarang;
  final String material;
  final String kadar;
  final String spesifikasi;
  final String asalMaterial;
  final String materialTambahan;
  final String asalTambahan;
  final String estimasiWaktu;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final int? pickupBranchId;
}

abstract final class CustomOrderPayloadBuilder {
  CustomOrderPayloadBuilder._();

  static Map<String, dynamic> build(CustomOrderFormInput input) {
    final orderData = <String, dynamic>{
      'order_type': 'custom',
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
          'kategori': 'custom',
          'jenis': input.jenisBarang,
          'tipe': 'custom',
          'material': input.material,
          'purity': input.kadar,
        },
      ],
      'spesifikasi': input.spesifikasi,
      'asal_material': input.asalMaterial,
      'material_tambahan': input.materialTambahan,
      'asal_tambahan': input.asalTambahan,
      'estimasi_waktu': input.estimasiWaktu,
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
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    required double uangMukaVal,
  }) {
    final fakturOverlay = <String, dynamic>{
      ...orderData,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_address': customerAddress,
    };
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
