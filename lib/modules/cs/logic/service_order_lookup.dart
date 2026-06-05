import 'package:vanessa3/modules/cs/logic/buyback_order_lookup.dart';

/// Lookup order jual lama untuk form service CS.
abstract final class ServiceOrderLookup {
  ServiceOrderLookup._();

  static Future<Map<String, dynamic>?> fetchOrder(String notaLama) {
    return BuybackOrderLookup.fetchByNotaOrOrderId(notaLama);
  }

  static bool isEligible(Map<String, dynamic> order) {
    return BuybackOrderLookup.isEligibleForBuyback(order);
  }

  static Map<String, dynamic> customerFromOrder(Map<String, dynamic> order) {
    String pickStr(dynamic a, dynamic b) {
      final s = a?.toString().trim() ?? '';
      if (s.isNotEmpty) return s;
      return b?.toString().trim() ?? '';
    }

    final custName = pickStr(order['customer_name'], order['name']);
    final custPhone = pickStr(order['customer_phone'], order['phone']);
    final custAddr = pickStr(order['customer_address'], order['address']);

    return {
      'customer_id': order['customer_id'],
      'name': custName,
      'nama': custName,
      'phone': custPhone,
      'no_hp': custPhone,
      'address': custAddr,
      'alamat': custAddr,
    };
  }
}
