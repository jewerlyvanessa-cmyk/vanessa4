import 'dart:convert';

import 'package:vanessa3/core/network/api_client.dart';

/// Lookup order jual lama untuk buyback (nota atau order_id dari QR).
abstract final class BuybackOrderLookup {
  BuybackOrderLookup._();

  static Map<String, dynamic>? _decodeOrderMap(String body) {
    if (body.trim().isEmpty || body.trim() == 'null') return null;
    final decoded = jsonDecode(body);
    if (decoded == null) return null;
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  static Future<Map<String, dynamic>?> fetchByNotaOrOrderId(
    String rawNota,
  ) async {
    final nota = rawNota.replaceAll(RegExp(r'[\r\n\t]+'), '').trim();
    if (nota.isEmpty) return null;

    var response = await ApiClient.get(
      '/orders',
      query: {'order_number': nota},
    );
    var order = response.statusCode == 200
        ? _decodeOrderMap(response.body)
        : null;

    if (order == null && RegExp(r'^\d+$').hasMatch(nota)) {
      response = await ApiClient.get('/orders', query: {'order_id': nota});
      if (response.statusCode == 200) {
        order = _decodeOrderMap(response.body);
      }
    }

    return order;
  }

  static bool isEligibleForBuyback(Map<String, dynamic> order) {
    return order['order_type'] == 'jual' && order['status'] == 'completed';
  }
}
