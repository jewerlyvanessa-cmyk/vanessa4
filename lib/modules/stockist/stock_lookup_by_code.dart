import 'dart:convert';

import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/shared_widgets/stock_status_filter_summary_header.dart';

/// Cari item di cabang [branchId] lewat `item_code` lalu fallback `search`.
Future<List<Map<String, dynamic>>> fetchStockItemsByCode({
  required String code,
  required String branchId,
  int limit = 10,
}) async {
  final trimmed = code.trim();
  if (trimmed.isEmpty) return const [];

  final baseQuery = <String, String>{
    if (branchId.isNotEmpty) 'branch_id': branchId,
    'limit': '$limit',
  };

  var resp = await ApiClient.get(
    '/items',
    query: {...baseQuery, 'item_code': trimmed},
  );
  if (resp.statusCode == 200) {
    final decoded = jsonDecode(resp.body);
    final list = (decoded is List ? decoded : const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (list.isNotEmpty) return list;
  }

  resp = await ApiClient.get(
    '/items',
    query: {...baseQuery, 'search': trimmed},
  );
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
  final resp = await ApiClient.get(
    '/items',
    query: <String, String>{
      'branch_id': bid,
      'limit': '$limit',
      if (statusTrim.isNotEmpty) 'status': statusTrim,
      if (startTrim.isNotEmpty) 'start_date': startTrim,
      if (endTrim.isNotEmpty) 'end_date': endTrim,
    },
  );
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

/// Daftar stok layak jual (ready/available/reserved) untuk cache offline CS.
Future<List<Map<String, dynamic>>> fetchSellableStockItems({
  required String branchId,
  int limit = 500,
}) async {
  final bid = branchId.trim();
  if (bid.isEmpty) return const [];

  final resp = await ApiClient.get(
    '/items',
    query: <String, String>{
      'branch_id': bid,
      'sellable_only': 'true',
      'limit': '$limit',
    },
  );
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

/// Hanya item inventaris siap etalase (status ready, qty > 0).
bool stockItemIsReadyForLabelReprint(dynamic item) =>
    stockItemVisibleForStatusFilter(item, 'ready');
