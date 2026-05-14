import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vanessa3/utils/faktur_print.dart' show fakturDpFromPayloadSync;
import 'package:vanessa3/utils/network_config.dart';

bool _metadataLooksPresent(Map<String, dynamic> order) {
  final raw = order['metadata'];
  if (raw == null) return false;
  if (raw is Map) return raw.isNotEmpty;
  if (raw is String) {
    final s = raw.trim();
    if (s.isEmpty || s == '{}' || s.toLowerCase() == 'null') return false;
    try {
      final d = jsonDecode(s);
      if (d is Map) return d.isNotEmpty;
    } catch (_) {
      return true;
    }
    return true;
  }
  return true;
}

bool _itemsListUsableForFaktur(dynamic items) {
  if (items is! List || items.isEmpty) return false;
  for (final e in items) {
    if (e is! Map) return false;
  }
  return true;
}

/// True bila payload order (mis. dari snapshot harian yang sudah digabung item)
/// cukup lengkap untuk [FakturPage] tanpa GET `/orders?order_number=`.
///
/// Service/custom: butuh metadata atau sinyal DP di payload agar tidak kehilangan
/// field faktur yang hanya ada di detail order.
bool orderPayloadSkipsDetailFetchForFaktur(Map<String, dynamic> order) {
  final oid = order['order_id']?.toString().trim();
  if (oid == null || oid.isEmpty) return false;
  if (!_itemsListUsableForFaktur(order['items'])) return false;

  final t = (order['order_type'] ?? '').toString().trim().toLowerCase();
  if (t == 'service' || t == 'custom') {
    if (_metadataLooksPresent(order)) return true;
    if (fakturDpFromPayloadSync(order) > 0) return true;
    return false;
  }
  return true;
}

/// Gabungkan detail order penuh bila perlu; selalu mengembalikan salinan Map.
Future<Map<String, dynamic>> loadOrderDataForFakturPage(
  Map<String, dynamic> order,
) async {
  final base = Map<String, dynamic>.from(order);
  if (orderPayloadSkipsDetailFetchForFaktur(base)) return base;

  final orderNumber = (base['order_number'] ?? '').toString().trim();
  if (orderNumber.isEmpty) return base;

  try {
    final uri = Uri.parse(
      '${NetworkConfig.baseUrl}/orders',
    ).replace(queryParameters: {'order_number': orderNumber});
    final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
    if (resp.statusCode == 200) {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return decoded;
    }
  } catch (_) {}

  return base;
}
