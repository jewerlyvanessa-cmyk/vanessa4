import 'package:flutter/foundation.dart';
import 'package:vanessa3/modules/cs/logic/jual_form_utils.dart';

/// Input form Jual untuk membangun payload POST `/orders`.
class JualOrderFormInput {
  const JualOrderFormInput({
    required this.saleType,
    required this.modeToko,
    required this.branchId,
    required this.userId,
    required this.customerId,
    required this.orderNumber,
    required this.diskonText,
    required this.namaItem,
    required this.beratText,
    required this.material,
    required this.kadar,
    required this.kategori,
    required this.jenis,
    required this.tipe,
    required this.itemCode,
    required this.qtyText,
    required this.hargaPerGramText,
    this.selectedItem,
    this.fotoUrl,
  });

  final String saleType;
  final String modeToko;
  final int? branchId;
  final int userId;
  final dynamic customerId;
  final String orderNumber;
  final String diskonText;
  final String namaItem;
  final String beratText;
  final String material;
  final String kadar;
  final String kategori;
  final String jenis;
  final String tipe;
  final String itemCode;
  final String qtyText;
  final String hargaPerGramText;
  final Map<String, dynamic>? selectedItem;
  final String? fotoUrl;
}

/// Bangun payload order jual dari state form.
abstract final class JualOrderPayloadBuilder {
  JualOrderPayloadBuilder._();

  static Map<String, dynamic> build(JualOrderFormInput input) {
    final orderData = <String, dynamic>{
      'order_type': 'jual',
      'order_number':
          input.orderNumber.isNotEmpty ? input.orderNumber : null,
      'branch_id': input.branchId,
      'user_id': input.userId,
      'mode': input.modeToko,
      'customer_id': input.customerId,
      'diskon': double.tryParse(input.diskonText) ?? 0.0,
    };

    if (input.saleType == 'from_stock') {
      orderData['item_id'] = input.selectedItem!['item_id'];
    } else {
      final itemData = <String, dynamic>{
        'name': input.namaItem,
        'weight': double.tryParse(input.beratText),
        'kategori': input.kategori,
        'jenis': input.jenis,
        'tipe': input.tipe,
        'photo_url': input.fotoUrl,
        'branch_id': input.branchId,
        'source': 'manual',
      };
      final material = input.material.trim();
      final kadar = input.kadar.trim();
      if (material.isNotEmpty) itemData['material'] = material;
      if (kadar.isNotEmpty) itemData['purity'] = kadar;

      if (input.saleType == 'qsr') {
        itemData['is_quick_registered'] = true;
        itemData['ownership'] = 'toko';
        itemData['stock_type'] = 'inventory';
        itemData['status'] = 'reserved';
      } else {
        itemData['ownership'] = 'unknown';
        itemData['stock_type'] = 'non_inventory';
        itemData['status'] = 'unregistered';
      }
      orderData['item_data'] = itemData;
    }

    final orderItems = <Map<String, dynamic>>[];
    if (input.saleType == 'from_stock' && input.selectedItem != null) {
      final item = input.selectedItem!;
      final existingPhoto =
          (item['photo_url'] ?? item['photo_produk'] ?? item['photo'] ?? '')
              .toString()
              .trim();
      final photoProduk = (input.fotoUrl?.trim().isNotEmpty ?? false)
          ? input.fotoUrl
          : (existingPhoto.isNotEmpty ? existingPhoto : null);
      debugPrint('Order item photo_produk (from_stock): $photoProduk');

      orderItems.add({
        'item_id': item['item_id'],
        'nama_item': item['name'] ?? input.namaItem,
        'kode_produk': item['kode_produk'] ?? item['item_code'],
        'weight': double.tryParse(input.beratText) ?? item['weight'],
        'qty': int.tryParse(input.qtyText) ?? 1,
        'harga_per_gram':
            JualFormUtils.parseNumberWithSeparators(input.hargaPerGramText),
        'photo_produk': photoProduk,
        'kategori': item['kategori'] ?? input.kategori,
        'jenis': item['jenis'] ?? input.jenis,
        'tipe': item['tipe'] ?? input.tipe,
      });
      final material = input.material.trim();
      final kadar = input.kadar.trim();
      if (material.isNotEmpty) orderItems.last['material'] = material;
      if (kadar.isNotEmpty) orderItems.last['purity'] = kadar;
    } else {
      debugPrint('Order item photo_produk (new item): ${input.fotoUrl}');
      orderItems.add({
        'nama_item': input.namaItem,
        'kode_produk': input.itemCode.isNotEmpty ? input.itemCode : null,
        'weight': double.tryParse(input.beratText),
        'qty': int.tryParse(input.qtyText) ?? 1,
        'harga_per_gram':
            JualFormUtils.parseNumberWithSeparators(input.hargaPerGramText),
        'photo_produk': input.fotoUrl,
        'kategori': input.kategori,
        'jenis': input.jenis,
        'tipe': input.tipe,
      });
      final material = input.material.trim();
      final kadar = input.kadar.trim();
      if (material.isNotEmpty) orderItems.last['material'] = material;
      if (kadar.isNotEmpty) orderItems.last['purity'] = kadar;
    }

    orderData['order_items'] = orderItems;
    return orderData;
  }
}
