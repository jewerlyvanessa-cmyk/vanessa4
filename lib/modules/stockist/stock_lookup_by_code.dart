import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vanessa3/utils/network_config.dart';

/// Cari item di cabang [branchId] lewat `item_code` lalu fallback `search`.
Future<List<Map<String, dynamic>>> fetchStockItemsByCode({
  required String code,
  required String branchId,
  int limit = 10,
}) async {
  final trimmed = code.trim();
  if (trimmed.isEmpty) return const [];

  final baseUrl = NetworkConfig.baseUrl;
  var uri = Uri.parse('$baseUrl/items').replace(
    queryParameters: <String, String>{
      if (branchId.isNotEmpty) 'branch_id': branchId,
      'item_code': trimmed,
      'limit': '$limit',
    },
  );

  var resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
  if (resp.statusCode == 200) {
    final decoded = jsonDecode(resp.body);
    final list = (decoded is List ? decoded : const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (list.isNotEmpty) return list;
  }

  uri = Uri.parse('$baseUrl/items').replace(
    queryParameters: <String, String>{
      if (branchId.isNotEmpty) 'branch_id': branchId,
      'search': trimmed,
      'limit': '$limit',
    },
  );
  resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
  if (resp.statusCode != 200) {
    throw Exception('HTTP ${resp.statusCode}');
  }
  final decoded2 = jsonDecode(resp.body);
  return (decoded2 is List ? decoded2 : const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

/// Daftar stok inventaris cabang (sama query seperti halaman Stok gudang).
Future<List<Map<String, dynamic>>> fetchStockInventoryItems({
  required String branchId,
  int limit = 500,
}) async {
  final bid = branchId.trim();
  if (bid.isEmpty) return const [];

  final uri = Uri.parse('${NetworkConfig.baseUrl}/items').replace(
    queryParameters: <String, String>{
      'branch_id': bid,
      'stock_type': 'inventory',
      'limit': '$limit',
    },
  );
  final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
  if (resp.statusCode != 200) {
    throw Exception('HTTP ${resp.statusCode}');
  }
  final data = jsonDecode(resp.body);
  if (data is! List) return const [];
  return data
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}
