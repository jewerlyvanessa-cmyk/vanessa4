import 'dart:convert';

import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/modules/admin_toko/data/daily_orders_payments_repository.dart';
import 'package:vanessa3/modules/admin_toko/utils/daily_orders_payments_helpers.dart';
import 'package:vanessa3/shared_widgets/stock_status_filter_summary_header.dart';
import 'package:vanessa3/utils/business_calendar.dart';

/// Ringkasan angka untuk kartu dashboard Owner.
class OwnerDashboardSnapshot {
  const OwnerDashboardSnapshot({
    required this.salesAmount,
    required this.salesPaymentCount,
    required this.buybackAmount,
    required this.buybackPaymentCount,
    required this.stockReadyQty,
    required this.stockReadySku,
    required this.orderCount,
    this.branchCount = 0,
    this.stockBranchCount = 0,
  });

  final num salesAmount;
  final int salesPaymentCount;
  final num buybackAmount;
  final int buybackPaymentCount;
  final int stockReadyQty;
  final int stockReadySku;
  final int orderCount;
  /// Jumlah cabang toko (penjualan / buyback).
  final int branchCount;
  /// Jumlah cabang untuk agregat stok (semua tipe cabang aktif).
  final int stockBranchCount;

  static const empty = OwnerDashboardSnapshot(
    salesAmount: 0,
    salesPaymentCount: 0,
    buybackAmount: 0,
    buybackPaymentCount: 0,
    stockReadyQty: 0,
    stockReadySku: 0,
    orderCount: 0,
    branchCount: 0,
    stockBranchCount: 0,
  );
}

/// Payload lengkap dashboard (kartu + tabel order).
class OwnerDashboardData {
  const OwnerDashboardData({
    required this.dateYmd,
    required this.snapshot,
    required this.orders,
  });

  final String dateYmd;
  final OwnerDashboardSnapshot snapshot;
  final List<Map<String, dynamic>> orders;
}

class _CacheEntry {
  _CacheEntry(this.key, this.data, this.fetchedAt);

  final String key;
  final OwnerDashboardData data;
  final DateTime fetchedAt;
}

abstract final class OwnerDashboardService {
  OwnerDashboardService._();

  static const _cacheTtl = Duration(seconds: 45);
  static _CacheEntry? _cache;

  static num _toNum(dynamic v) => num.tryParse(v?.toString() ?? '') ?? 0;

  static String _cacheKey(String dateYmd, List<String> branchIds, bool globalScope) {
    if (globalScope) return '$dateYmd|global';
    final sorted = [...branchIds]..sort();
    return '$dateYmd|${sorted.join(',')}';
  }

  static void invalidateCache() => _cache = null;

  /// Muat dashboard — prefer satu API `/reports/owner-dashboard`, fallback paralel.
  static Future<OwnerDashboardData> loadDashboard({
    List<Map<String, dynamic>> branches = const [],
    required String dateYmd,
    bool forceRefresh = false,
    bool globalScope = false,
  }) async {
    final branchIds = <String>[];
    if (!globalScope) {
      for (final b in branches) {
        final id = b['branch_id']?.toString().trim() ?? '';
        if (id.isNotEmpty) branchIds.add(id);
      }
    }

    final key = _cacheKey(dateYmd, branchIds, globalScope);
    if (!forceRefresh &&
        _cache != null &&
        _cache!.key == key &&
        DateTime.now().difference(_cache!.fetchedAt) < _cacheTtl) {
      return _cache!.data;
    }

    OwnerDashboardData data;
    try {
      data = await _loadFromOwnerDashboardApi(
        branchIds: branchIds,
        dateYmd: dateYmd,
        globalScope: globalScope,
      );
    } catch (_) {
      if (globalScope) rethrow;
      data = await _loadLegacyParallel(
        branches: branches,
        dateYmd: dateYmd,
      );
    }

    _cache = _CacheEntry(key, data, DateTime.now());
    return data;
  }

  static Future<OwnerDashboardData> _loadFromOwnerDashboardApi({
    required List<String> branchIds,
    required String dateYmd,
    bool globalScope = false,
  }) async {
    final query = <String, String>{'date': dateYmd};
    if (globalScope) {
      query['scope'] = 'global';
    } else if (branchIds.isNotEmpty) {
      query['branch_ids'] = branchIds.join(',');
    }

    final resp = await ApiClient.get('/reports/owner-dashboard', query: query);
    if (resp.statusCode != 200) {
      throw Exception('owner-dashboard ${resp.statusCode}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('owner-dashboard: invalid JSON');
    }

    final summary = decoded['summary'];
    final snap = summary is Map
        ? OwnerDashboardSnapshot(
            salesAmount: _toNum(summary['sales_amount']),
            salesPaymentCount:
                _toNum(summary['sales_payment_count']).toInt(),
            buybackAmount: _toNum(summary['buyback_amount']),
            buybackPaymentCount:
                _toNum(summary['buyback_payment_count']).toInt(),
            stockReadyQty: _toNum(summary['stock_ready_qty']).toInt(),
            stockReadySku: _toNum(summary['stock_ready_sku']).toInt(),
            orderCount: _toNum(summary['order_count']).toInt(),
            branchCount: _toNum(summary['branch_count']).toInt(),
            stockBranchCount: _toNum(
              summary['stock_branch_count'] ?? summary['branch_count'],
            ).toInt(),
          )
        : OwnerDashboardSnapshot.empty;

    final ordersRaw = decoded['orders'];
    final orders = <Map<String, dynamic>>[];
    if (ordersRaw is List) {
      for (final row in ordersRaw) {
        if (row is Map) {
          orders.add(Map<String, dynamic>.from(row));
        }
      }
    }

    return OwnerDashboardData(
      dateYmd: (decoded['date'] ?? dateYmd).toString(),
      snapshot: snap,
      orders: orders,
    );
  }

  /// Fallback jika endpoint belum di-deploy (paralel per cabang, tanpa duplikasi order).
  static Future<OwnerDashboardData> _loadLegacyParallel({
    required List<Map<String, dynamic>> branches,
    required String dateYmd,
  }) async {
    final branchIds = <String>[];
    for (final b in branches) {
      final id = b['branch_id']?.toString().trim() ?? '';
      if (id.isNotEmpty) branchIds.add(id);
    }

    if (branchIds.isEmpty) {
      return OwnerDashboardData(
        dateYmd: dateYmd,
        snapshot: OwnerDashboardSnapshot.empty,
        orders: const [],
      );
    }

    final parts = await Future.wait(
      branchIds.map((id) => _loadBranchLegacy(id, branches, dateYmd)),
    );

    var snap = OwnerDashboardSnapshot.empty;
    final orders = <Map<String, dynamic>>[];

    for (final p in parts) {
      snap = OwnerDashboardSnapshot(
        salesAmount: snap.salesAmount + p.snapshot.salesAmount,
        salesPaymentCount: snap.salesPaymentCount + p.snapshot.salesPaymentCount,
        buybackAmount: snap.buybackAmount + p.snapshot.buybackAmount,
        buybackPaymentCount:
            snap.buybackPaymentCount + p.snapshot.buybackPaymentCount,
        stockReadyQty: snap.stockReadyQty + p.snapshot.stockReadyQty,
        stockReadySku: snap.stockReadySku + p.snapshot.stockReadySku,
        orderCount: snap.orderCount + p.snapshot.orderCount,
        branchCount: branchIds.length,
        stockBranchCount: branchIds.length,
      );
      orders.addAll(p.orders);
    }

    orders.sort((a, b) {
      final ta = a['created_at']?.toString() ?? '';
      final tb = b['created_at']?.toString() ?? '';
      return tb.compareTo(ta);
    });

    return OwnerDashboardData(
      dateYmd: dateYmd,
      snapshot: snap,
      orders: orders,
    );
  }

  static Future<({OwnerDashboardSnapshot snapshot, List<Map<String, dynamic>> orders})>
      _loadBranchLegacy(
    String branchId,
    List<Map<String, dynamic>> branches,
    String dateYmd,
  ) async {
    String branchName = 'Cabang $branchId';
    for (final b in branches) {
      if (b['branch_id']?.toString() == branchId) {
        branchName = (b['name'] ?? branchName).toString();
        break;
      }
    }

    try {
      final results = await Future.wait([
        _fetchBranchPaymentSummary(branchId: branchId, dateYmd: dateYmd),
        _fetchBranchPaymentSummary(
          branchId: branchId,
          dateYmd: dateYmd,
          orderType: 'buyback',
        ),
        _readyStockTotalsForBranch(branchId),
        DailyOrdersPaymentsRepository.fetchOrdersDailyList(
          branchId: branchId,
          dateYmd: dateYmd,
        ),
      ]);

      final sales = results[0] as Map<String, dynamic>;
      final bb = results[1] as Map<String, dynamic>;
      final stock = results[2] as ({int qty, int sku});
      final list = results[3] as List<dynamic>;

      final orders = <Map<String, dynamic>>[];
      for (final row in list) {
        if (row is! Map) continue;
        final m = Map<String, dynamic>.from(row);
        m['branch_name'] = branchName;
        m['branch_id'] = branchId;
        orders.add(m);
      }

      return (
        snapshot: OwnerDashboardSnapshot(
          salesAmount: _toNum(sales['total_amount']),
          salesPaymentCount: _toNum(sales['total_payments']).toInt(),
          buybackAmount: _toNum(bb['total_amount']),
          buybackPaymentCount: _toNum(bb['total_payments']).toInt(),
          stockReadyQty: stock.qty,
          stockReadySku: stock.sku,
          orderCount: dedupeOrdersById(list).length,
        ),
        orders: orders,
      );
    } catch (_) {
      return (
        snapshot: OwnerDashboardSnapshot.empty,
        orders: <Map<String, dynamic>>[],
      );
    }
  }

  static Future<Map<String, dynamic>> _fetchBranchPaymentSummary({
    required String branchId,
    required String dateYmd,
    String? orderType,
  }) async {
    final qp = <String, String>{
      'branch_id': branchId,
      'date': dateYmd,
    };
    final ot = orderType?.trim();
    if (ot != null && ot.isNotEmpty) {
      qp['order_type'] = ot;
    }
    final resp = await ApiClient.get('/payments/daily-summary', query: qp);
    if (resp.statusCode != 200) return {};
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) return {};
    final summary = decoded['summary'];
    return summary is Map ? Map<String, dynamic>.from(summary) : {};
  }

  static Future<({int qty, int sku})> _readyStockTotalsForBranch(
    String branchId,
  ) async {
    final resp = await ApiClient.get(
      '/items',
      query: {
        'branch_id': branchId,
        'status': 'ready',
        'in_stock_only': '1',
        'limit': '1000',
      },
    );
    if (resp.statusCode != 200) return (qty: 0, sku: 0);
    final decoded = jsonDecode(resp.body);
    if (decoded is! List) return (qty: 0, sku: 0);

    final visible = <dynamic>[];
    for (final row in decoded) {
      if (row is! Map) continue;
      final item = Map<String, dynamic>.from(row);
      if (stockItemVisibleForStatusFilter(item, 'ready')) {
        visible.add(item);
      }
    }

    return (qty: stockListSumQuantity(visible), sku: visible.length);
  }

  /// Ringkasan kartu — default lintas semua cabang aktif (`scope=global`).
  static Future<OwnerDashboardSnapshot> loadSummary({
    String? dateYmd,
    bool forceRefresh = false,
    bool globalScope = true,
  }) async {
    final d = await loadDashboard(
      dateYmd: dateYmd ?? BusinessCalendar.todayYmd(),
      forceRefresh: forceRefresh,
      globalScope: globalScope,
    );
    return d.snapshot;
  }

  @Deprecated('Use loadSummary or loadDashboard')
  static Future<OwnerDashboardSnapshot> loadSnapshot({
    required List<Map<String, dynamic>> branches,
    String? dateYmd,
  }) async {
    final d = await loadDashboard(
      branches: branches,
      dateYmd: dateYmd ?? BusinessCalendar.todayYmd(),
    );
    return d.snapshot;
  }

  @Deprecated('Use loadDashboard')
  static Future<List<Map<String, dynamic>>> loadGlobalOrders({
    required List<Map<String, dynamic>> branches,
    required String dateYmd,
  }) async {
    final d = await loadDashboard(branches: branches, dateYmd: dateYmd);
    return d.orders;
  }
}
