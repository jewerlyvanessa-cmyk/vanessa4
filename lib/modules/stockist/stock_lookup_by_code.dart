import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vanessa3/shared_widgets/stock_status_filter_summary_header.dart';
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

/// Daftar stok cabang aktif (sama query seperti halaman Stok stockist / admin toko).
/// [status] opsional, mis. `ready` — disaring juga di klien (ready + qty > 0).
/// [startDate]/[endDate] format `yyyy-MM-dd`, filter `created_at` item (API).
Future<List<Map<String, dynamic>>> fetchStockInventoryItems({
  required String branchId,
  int limit = 500,
  String? status,
  String? startDate,
  String? endDate,
}) async {
  final bid = branchId.trim();
  if (bid.isEmpty) return const [];

  final statusTrim = status?.trim() ?? '';
  final startTrim = startDate?.trim() ?? '';
  final endTrim = endDate?.trim() ?? '';
  final uri = Uri.parse('${NetworkConfig.baseUrl}/items').replace(
    queryParameters: <String, String>{
      'branch_id': bid,
      'limit': '$limit',
      if (statusTrim.isNotEmpty) 'status': statusTrim,
      if (startTrim.isNotEmpty) 'start_date': startTrim,
      if (endTrim.isNotEmpty) 'end_date': endTrim,
    },
  );
  final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
  if (resp.statusCode != 200) {
    throw Exception('HTTP ${resp.statusCode}');
  }
  final data = jsonDecode(resp.body);
  if (data is! List) return const [];
  var list = data
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  if (statusTrim == 'ready') {
    list = list
        .where((it) => stockItemVisibleForStatusFilter(it, 'ready'))
        .toList();
  }
  return list;
}

/// Hanya item inventaris siap etalase (status ready, qty > 0).
bool stockItemIsReadyForLabelReprint(dynamic item) =>
    stockItemVisibleForStatusFilter(item, 'ready');
