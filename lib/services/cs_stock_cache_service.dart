import 'dart:convert';

import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/data/offline_cache.dart';
import 'package:vanessa3/modules/stockist/stock_lookup_by_code.dart';
import 'package:vanessa3/utils/network_config.dart';

/// Cache stok layak jual untuk form CS (baca offline setelah prefetch).
abstract final class CsStockCacheService {
  CsStockCacheService._();

  static const Duration _ttl = Duration(minutes: 30);

  static String _cacheKey(String branchId) =>
      'csSellableStock/v1?branch=${branchId.trim()}';

  static bool isSellableStatus(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    return s == 'ready' || s == 'available' || s == 'reserved';
  }

  static String _itemCode(Map<String, dynamic> item) =>
      (item['kode_produk'] ?? item['item_code'] ?? '').toString().trim();

  /// Muat ulang cache dari API (abaikan error — best effort).
  static Future<int> prefetchSellable(String branchId) async {
    final bid = branchId.trim();
    if (bid.isEmpty) return 0;
    try {
      final items = await fetchSellableStockItems(branchId: bid, limit: 500);
      await OfflineCache.instance.setJson(
        _cacheKey(bid),
        items,
        ttl: _ttl,
      );
      return items.length;
    } catch (_) {
      return 0;
    }
  }

  static Future<List<Map<String, dynamic>>> _readCache(String branchId) async {
    final cached =
        await OfflineCache.instance.getJson<List<dynamic>>(_cacheKey(branchId));
    if (cached == null || cached.isExpired) return const [];
    return cached.value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((it) => isSellableStatus(it['status']?.toString()))
        .toList();
  }

  static Future<void> _mergeIntoCache(
    String branchId,
    Iterable<Map<String, dynamic>> items,
  ) async {
    final bid = branchId.trim();
    if (bid.isEmpty || items.isEmpty) return;
    final existing = await _readCache(bid);
    final byCode = <String, Map<String, dynamic>>{};
    for (final it in existing) {
      final c = _itemCode(it).toLowerCase();
      if (c.isNotEmpty) byCode[c] = it;
    }
    for (final it in items) {
      if (!isSellableStatus(it['status']?.toString())) continue;
      final c = _itemCode(it).toLowerCase();
      if (c.isNotEmpty) byCode[c] = Map<String, dynamic>.from(it);
    }
    await OfflineCache.instance.setJson(
      _cacheKey(bid),
      byCode.values.toList(),
      ttl: _ttl,
    );
  }

  static List<Map<String, dynamic>> _searchInList(
    List<Map<String, dynamic>> items,
    String query, {
    int limit = 10,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <Map<String, dynamic>>[];
    for (final it in items) {
      final code = _itemCode(it).toLowerCase();
      final name = (it['name'] ?? '').toString().toLowerCase();
      if (code.contains(q) || name.contains(q)) {
        out.add(it);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  /// Cari stok untuk autocomplete — online API dengan fallback cache.
  static Future<List<Map<String, dynamic>>> searchItems({
    required String branchId,
    required String query,
    required bool online,
    bool sellableOnly = true,
    int limit = 10,
  }) async {
    final bid = branchId.trim();
    final q = query.trim();
    if (bid.isEmpty || q.isEmpty) return const [];

    if (online) {
      try {
        final uri = Uri.parse('${NetworkConfig.baseUrl}/items').replace(
          queryParameters: <String, String>{
            'branch_id': bid,
            'search': q,
            'limit': '$limit',
            if (sellableOnly) 'sellable_only': 'true',
          },
        );
        final resp = await ApiClient.get(uri.toString());
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          if (data is List) {
            final list = data
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            await _mergeIntoCache(bid, list);
            return list;
          }
        }
      } catch (_) {
        // fallback cache di bawah
      }
    }

    return _searchInList(await _readCache(bid), q, limit: limit);
  }

  /// Resolve kode stok (scan/ketik) — online dulu, lalu cache.
  static Future<List<Map<String, dynamic>>> lookupByCode({
    required String branchId,
    required String code,
    required bool online,
  }) async {
    final bid = branchId.trim();
    final normalized = code.trim().toLowerCase();
    if (bid.isEmpty || normalized.isEmpty) return const [];

    if (online) {
      try {
        final list = await fetchStockItemsByCode(
          code: code,
          branchId: bid,
          limit: 5,
        );
        final sellable = list
            .where((it) => isSellableStatus(it['status']?.toString()))
            .toList();
        if (sellable.isNotEmpty) {
          await _mergeIntoCache(bid, sellable);
          return sellable;
        }

        final sellableOnly = await fetchSellableStockItems(
          branchId: bid,
          limit: 500,
        );
        final exact = sellableOnly
            .where((it) => _itemCode(it).toLowerCase() == normalized)
            .toList();
        if (exact.isNotEmpty) {
          await _mergeIntoCache(bid, exact);
          return exact;
        }

        final searched = await searchItems(
          branchId: bid,
          query: code,
          online: true,
          sellableOnly: true,
          limit: 5,
        );
        if (searched.isNotEmpty) {
          return searched;
        }
      } catch (_) {
        // fallback cache
      }
    }

    final cached = await _readCache(bid);
    final exact = cached
        .where((it) => _itemCode(it).toLowerCase() == normalized)
        .toList();
    if (exact.isNotEmpty) return exact;
    return _searchInList(cached, code, limit: 5);
  }

  static Future<int?> cachedItemCount(String branchId) async {
    final items = await _readCache(branchId);
    return items.isEmpty ? null : items.length;
  }
}
