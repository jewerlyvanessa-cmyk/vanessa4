import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart'; // Import for NetworkConfig
import 'package:vanessa3/providers/network_provider.dart';
import 'package:vanessa3/data/offline_cache.dart';
import 'package:vanessa3/core/state/user_state.dart';
import 'package:vanessa3/utils/agent_ndjson.dart';

/// Aktifkan log NDJSON hanya bila perlu debug (`--dart-define=ORDER_TODAY_NDJSON=true`).
const bool _kOrderTodayNdjson = bool.fromEnvironment(
  'ORDER_TODAY_NDJSON',
  defaultValue: false,
);

void _otNdjson({
  required String hypothesisId,
  required String location,
  required String message,
  Map<String, Object?> data = const {},
  String runId = 'order-today',
}) {
  if (!_kOrderTodayNdjson) return;
  agentDebugNdjson(
    hypothesisId: hypothesisId,
    location: location,
    message: message,
    data: data,
    runId: runId,
  );
}

AsyncValue<OrderTodayStats> _statsLoadingFrom(AsyncValue<OrderTodayStats> cur) {
  if (cur is AsyncData<OrderTodayStats>) {
    return const AsyncValue<OrderTodayStats>.loading().copyWithPrevious(
      AsyncData(cur.value),
      isRefresh: true,
    );
  }
  return const AsyncValue.loading();
}

AsyncValue<List<Map<String, dynamic>>> _todayOrdersLoadingFrom(
  AsyncValue<List<Map<String, dynamic>>> cur,
) {
  if (cur is AsyncData<List<Map<String, dynamic>>>) {
    return const AsyncValue<List<Map<String, dynamic>>>.loading()
        .copyWithPrevious(AsyncData(cur.value), isRefresh: true);
  }
  return const AsyncValue.loading();
}

/// Tanggal kalender lokal perangkat (sama dengan filter "hari ini" di backend WIB).
String _localCalendarDateKey() =>
    DateFormat('yyyy-MM-dd').format(DateTime.now());

/// CS: order hari ini hanya yang dibuat user itu. Role lain: semua order cabang tersebut.
bool _orderTodayOwnUserOnlyScope(UserState s) {
  return s.role.trim().toLowerCase() == 'cs';
}

bool _orderTodayAllBranchesScope(UserState s) {
  return s.role.trim().toLowerCase() == 'manajer';
}

List<int> _orderTodayBranchIds(UserState s) {
  final active = activeBranchIdFromUserState(s);
  if (!_orderTodayAllBranchesScope(s)) {
    return active == null ? const <int>[] : <int>[active];
  }
  final ids = <int>{};
  for (final b in s.branches) {
    final bid = int.tryParse((b['branch_id'] ?? '').toString());
    if (bid != null && bid > 0) ids.add(bid);
  }
  if (ids.isEmpty && active != null) ids.add(active);
  final out = ids.toList()..sort();
  return out;
}

String _orderTodayScopeCacheSegment(UserState s) {
  if (_orderTodayOwnUserOnlyScope(s) && s.userId != null) {
    return 'own_${s.userId}';
  }
  return 'branch';
}

/// Cabang aktif dari [UserState.branch] — tidak ada fallback ke cabang lain.
int? activeBranchIdFromUserState(UserState s) {
  final v = int.tryParse(s.branch.trim());
  if (v == null || v <= 0) return null;
  return v;
}

// Model untuk Order Today
class OrderTodayStats {
  final int totalOrders;
  final int completedOrders;
  final int pendingOrders;
  final Map<String, int> ordersByType;
  final Map<String, int> ordersByMode;
  final Map<String, int> ordersByStatus;
  final double totalRevenue;
  final Map<String, double> revenueByTypeCompleted;
  final double revenueJualCompleted;
  final double expenseBuybackCompleted;
  final DateTime date;

  OrderTodayStats({
    required this.totalOrders,
    required this.completedOrders,
    required this.pendingOrders,
    required this.ordersByType,
    required this.ordersByMode,
    required this.ordersByStatus,
    required this.totalRevenue,
    required this.revenueByTypeCompleted,
    required this.revenueJualCompleted,
    required this.expenseBuybackCompleted,
    required this.date,
  });

  factory OrderTodayStats.fromJson(Map<String, dynamic> json) {
    final rbt = json['revenue_by_type_completed'];
    final revenueMap = <String, double>{};
    if (rbt is Map) {
      for (final e in rbt.entries) {
        final k = e.key.toString();
        final v = e.value;
        final d = v is num
            ? v.toDouble()
            : double.tryParse(v.toString()) ?? 0.0;
        revenueMap[k] = d;
      }
    }
    final obmRaw = json['orders_by_mode'];
    final ordersByMode = <String, int>{'toko': 0, 'online': 0};
    if (obmRaw is Map) {
      for (final e in obmRaw.entries) {
        final k = e.key.toString().toLowerCase();
        final v = e.value;
        final add = v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0;
        ordersByMode[k] = (ordersByMode[k] ?? 0) + add;
      }
    }
    return OrderTodayStats(
      totalOrders: json['total_orders'] ?? 0,
      completedOrders: json['completed_orders'] ?? 0,
      pendingOrders: json['pending_orders'] ?? 0,
      ordersByType: Map<String, int>.from(json['orders_by_type'] ?? {}),
      ordersByMode: ordersByMode,
      ordersByStatus: Map<String, int>.from(json['orders_by_status'] ?? {}),
      totalRevenue: (json['total_revenue'] ?? 0).toDouble(),
      revenueByTypeCompleted: revenueMap,
      revenueJualCompleted: (json['revenue_jual_completed'] ?? 0).toDouble(),
      expenseBuybackCompleted: (json['expense_buyback_completed'] ?? 0)
          .toDouble(),
      date: DateTime.parse(json['date'] ?? DateTime.now().toIso8601String()),
    );
  }
}

// Provider untuk Order Today Stats
final orderTodayStatsProvider =
    StateNotifierProvider<OrderTodayStatsNotifier, AsyncValue<OrderTodayStats>>(
      (ref) {
        return OrderTodayStatsNotifier(ref);
      },
    );

class OrderTodayStatsNotifier
    extends StateNotifier<AsyncValue<OrderTodayStats>> {
  final Ref _ref;
  int? _lastUserId;
  String? _lastBranch;
  String _lastRole = '';
  String _lastAuthToken = '';

  OrderTodayStatsNotifier(this._ref) : super(const AsyncValue.loading()) {
    // Check if user is already logged in and load data
    _checkAndFetch();
  }

  void _checkAndFetch() {
    final userState = _ref.read(userStateProvider);
    if (userState.authToken.trim().isEmpty) {
      state = const AsyncValue.loading();
      return;
    }
    if (userState.branch.isNotEmpty) {
      fetchOrderTodayStats();
    } else {
      state = const AsyncValue.loading();
    }
  }

  // Method untuk mendengarkan perubahan user state
  void listenToUserStateChanges() {
    final userState = _ref.read(userStateProvider);
    if (_lastUserId != userState.userId ||
        _lastBranch != userState.branch ||
        _lastRole != userState.role ||
        _lastAuthToken != userState.authToken) {
      _lastUserId = userState.userId;
      _lastBranch = userState.branch;
      _lastRole = userState.role;
      _lastAuthToken = userState.authToken;
      _checkAndFetch();
    }
  }

  Future<void> fetchOrderTodayStats() async {
    state = _statsLoadingFrom(state);

    try {
      final userState = _ref.read(userStateProvider);
      if (userState.authToken.trim().isEmpty) {
        state = const AsyncValue.loading();
        return;
      }
      final userId = userState.userId;
      final branchIds = _orderTodayBranchIds(userState);
      if (branchIds.isEmpty) {
        _otNdjson(
          hypothesisId: 'OT3',
          location: 'order_today_provider.dart:fetchOrderTodayStats:no_branch',
          message: 'branchId null',
          data: <String, Object?>{'branchRaw': userState.branch},
        );
        state = AsyncValue.error(
          Exception(
            'Cabang aktif belum valid. Pilih cabang (kasir / admin toko / lainnya) lalu coba lagi.',
          ),
          StackTrace.current,
        );
        return;
      }
      final dateKey = _localCalendarDateKey();
      final scopeSeg = _orderTodayScopeCacheSegment(userState);

      final cacheKey = branchIds.length == 1
          ? 'orderTodayStats/v2?branch_id=${branchIds.first}&scope=$scopeSeg&date=$dateKey'
          : 'orderTodayStats/v2?branch_ids=${branchIds.join(',')}&scope=$scopeSeg&date=$dateKey';

      final networkState = _ref.read(networkStatusProvider);
      if (!networkState.isOnline || !networkState.isBackendReachable) {
        final cached = await OfflineCache.instance
            .getJson<Map<String, dynamic>>(cacheKey);
        if (cached != null) {
          _otNdjson(
            hypothesisId: 'OT4',
            location:
                'order_today_provider.dart:fetchOrderTodayStats:cache_hit',
            message: 'stats offline cache hit',
            data: <String, Object?>{
              'total_orders': cached.value['total_orders'],
            },
          );
          state = AsyncValue.data(OrderTodayStats.fromJson(cached.value));
          return;
        }
      }

      // Use real API call instead of mock data
      final baseUrl = NetworkConfig.baseUrl; // Use NetworkConfig for proper URL

      _otNdjson(
        hypothesisId: 'OT2',
        location: 'order_today_provider.dart:fetchOrderTodayStats:request',
        message: 'fetch stats request',
        data: <String, Object?>{
          'role': userState.role.trim().toLowerCase(),
          'userId': userId,
          'branchRaw': userState.branch,
          'branchIds': branchIds,
          'dateKey': dateKey,
          'scopeSeg': scopeSeg,
          'csScoped': _orderTodayOwnUserOnlyScope(userState),
          'online': '${networkState.isOnline}',
          'backendReachable': '${networkState.isBackendReachable}',
          'baseUrl': baseUrl,
          'hasAuthHeader':
              NetworkConfig.defaultHeaders['Authorization']
                  ?.toString()
                  .trim()
                  .isNotEmpty ==
              true,
        },
      );

      Map<String, dynamic> mergedJson = <String, dynamic>{
        'total_orders': 0,
        'completed_orders': 0,
        'pending_orders': 0,
        'orders_by_type': <String, int>{},
        'orders_by_mode': <String, int>{'toko': 0, 'online': 0},
        'orders_by_status': <String, int>{},
        'total_revenue': 0.0,
        'revenue_by_type_completed': <String, double>{},
        'revenue_jual_completed': 0.0,
        'expense_buyback_completed': 0.0,
        'date': DateTime.now().toIso8601String(),
      };

      final client = http.Client();
      try {
        for (final bid in branchIds) {
          final queryParams = <String, String>{
            'branch_id': bid.toString(),
            'date': dateKey,
          };
          if (_orderTodayOwnUserOnlyScope(userState) && userId != null) {
            queryParams['user_id'] = userId.toString();
          }

          final uri = Uri.parse(
            '$baseUrl/api/dashboard/order-today',
          ).replace(queryParameters: queryParams);

          final response = await client
              .get(uri, headers: NetworkConfig.defaultHeaders)
              .timeout(NetworkConfig.connectionTimeout);

          if (response.statusCode != 200) {
            throw Exception(
              'Failed to load order stats: ${response.statusCode}',
            );
          }

          final data = jsonDecode(response.body) as Map<String, dynamic>;

          mergedJson['total_orders'] =
              (mergedJson['total_orders'] as int) +
              ((data['total_orders'] ?? 0) as int);
          mergedJson['completed_orders'] =
              (mergedJson['completed_orders'] as int) +
              ((data['completed_orders'] ?? 0) as int);
          mergedJson['pending_orders'] =
              (mergedJson['pending_orders'] as int) +
              ((data['pending_orders'] ?? 0) as int);
          mergedJson['total_revenue'] =
              (mergedJson['total_revenue'] as double) +
              ((data['total_revenue'] ?? 0) as num).toDouble();
          mergedJson['revenue_jual_completed'] =
              (mergedJson['revenue_jual_completed'] as double) +
              ((data['revenue_jual_completed'] ?? 0) as num).toDouble();
          mergedJson['expense_buyback_completed'] =
              (mergedJson['expense_buyback_completed'] as double) +
              ((data['expense_buyback_completed'] ?? 0) as num).toDouble();

          final obt = data['orders_by_type'];
          if (obt is Map) {
            final tgt = mergedJson['orders_by_type'] as Map<String, int>;
            for (final e in obt.entries) {
              final k = e.key.toString();
              final v = e.value;
              tgt[k] = (tgt[k] ?? 0) + (v is num ? v.toInt() : 0);
            }
          }
          final obm = data['orders_by_mode'];
          if (obm is Map) {
            final tgt = mergedJson['orders_by_mode'] as Map<String, int>;
            for (final e in obm.entries) {
              final k = e.key.toString().toLowerCase();
              final v = e.value;
              tgt[k] = (tgt[k] ?? 0) + (v is num ? v.toInt() : 0);
            }
          }
          final obs = data['orders_by_status'];
          if (obs is Map) {
            final tgt = mergedJson['orders_by_status'] as Map<String, int>;
            for (final e in obs.entries) {
              final k = e.key.toString();
              final v = e.value;
              tgt[k] = (tgt[k] ?? 0) + (v is num ? v.toInt() : 0);
            }
          }
          final rbt = data['revenue_by_type_completed'];
          if (rbt is Map) {
            final tgt =
                mergedJson['revenue_by_type_completed'] as Map<String, double>;
            for (final e in rbt.entries) {
              final k = e.key.toString();
              final v = e.value;
              final d = v is num
                  ? v.toDouble()
                  : double.tryParse(v.toString()) ?? 0.0;
              tgt[k] = (tgt[k] ?? 0.0) + d;
            }
          }
        }
      } finally {
        client.close();
      }

      _otNdjson(
        hypothesisId: 'OT2',
        location: 'order_today_provider.dart:fetchOrderTodayStats:ok',
        message: 'stats response 200',
        data: <String, Object?>{
          'total_orders': mergedJson['total_orders'],
          'pending': mergedJson['pending_orders'],
          'branchesMerged': branchIds.length,
        },
      );

      await OfflineCache.instance.setJson(
        cacheKey,
        mergedJson,
        ttl: const Duration(minutes: 5),
      );
      state = AsyncValue.data(OrderTodayStats.fromJson(mergedJson));
    } catch (error, stackTrace) {
      // Fallback to cache if request failed.
      try {
        final userState = _ref.read(userStateProvider);
        final branchIds = _orderTodayBranchIds(userState);
        if (branchIds.isNotEmpty) {
          final dateKey = _localCalendarDateKey();
          final scopeSeg = _orderTodayScopeCacheSegment(userState);
          final cacheKey = branchIds.length == 1
              ? 'orderTodayStats/v2?branch_id=${branchIds.first}&scope=$scopeSeg&date=$dateKey'
              : 'orderTodayStats/v2?branch_ids=${branchIds.join(',')}&scope=$scopeSeg&date=$dateKey';
          final cached = await OfflineCache.instance
              .getJson<Map<String, dynamic>>(cacheKey);
          if (cached != null) {
            state = AsyncValue.data(OrderTodayStats.fromJson(cached.value));
            return;
          }
        }
      } catch (_) {
        // ignore cache errors
      }
      _otNdjson(
        hypothesisId: 'OT1',
        location: 'order_today_provider.dart:fetchOrderTodayStats:error',
        message: 'stats fetch failed',
        data: <String, Object?>{
          'err': error.toString().length > 200
              ? error.toString().substring(0, 200)
              : error.toString(),
        },
      );
      state = AsyncValue.error(error, stackTrace);
    }
  }

  // Method untuk refresh data
  Future<void> refresh() async {
    await fetchOrderTodayStats();
  }

  // Method untuk update stats secara real-time (dipanggil dari WebSocket)
  void updateStats(OrderTodayStats newStats) {
    state = AsyncValue.data(newStats);
  }
}

// Provider untuk list order hari ini
final todayOrdersProvider =
    StateNotifierProvider<
      TodayOrdersNotifier,
      AsyncValue<List<Map<String, dynamic>>>
    >((ref) {
      return TodayOrdersNotifier(ref);
    });

class TodayOrdersNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  int? _lastUserId;
  String? _lastBranch;
  String _lastRole = '';
  String _lastAuthToken = '';

  TodayOrdersNotifier(this._ref) : super(const AsyncValue.loading()) {
    // Check if user is already logged in and load data
    _checkAndFetch();
  }

  void _checkAndFetch() {
    final userState = _ref.read(userStateProvider);
    if (userState.authToken.trim().isEmpty) {
      state = const AsyncValue.loading();
      return;
    }
    if (userState.branch.isNotEmpty) {
      fetchTodayOrders();
    } else {
      state = const AsyncValue.loading();
    }
  }

  // Method untuk mendengarkan perubahan user state
  void listenToUserStateChanges() {
    final userState = _ref.read(userStateProvider);
    if (_lastUserId != userState.userId ||
        _lastBranch != userState.branch ||
        _lastRole != userState.role ||
        _lastAuthToken != userState.authToken) {
      _lastUserId = userState.userId;
      _lastBranch = userState.branch;
      _lastRole = userState.role;
      _lastAuthToken = userState.authToken;
      _checkAndFetch();
    }
  }

  Future<void> fetchTodayOrders() async {
    state = _todayOrdersLoadingFrom(state);

    try {
      final userState = _ref.read(userStateProvider);
      if (userState.authToken.trim().isEmpty) {
        state = const AsyncValue.loading();
        return;
      }
      final userId = userState.userId;
      final branchIds = _orderTodayBranchIds(userState);
      if (branchIds.isEmpty) {
        _otNdjson(
          hypothesisId: 'OT3',
          location: 'order_today_provider.dart:fetchTodayOrders:no_branch',
          message: 'branchId null',
          data: <String, Object?>{'branchRaw': userState.branch},
        );
        state = AsyncValue.error(
          Exception(
            'Cabang aktif belum valid. Pilih cabang (kasir / admin toko / lainnya) lalu coba lagi.',
          ),
          StackTrace.current,
        );
        return;
      }
      final todayKey = _localCalendarDateKey();
      final scopeSeg = _orderTodayScopeCacheSegment(userState);

      // v5: scope branch vs own (CS) — backend juga memaksa dari JWT.
      final cacheKey = branchIds.length == 1
          ? 'todayOrders/v5?branch_id=${branchIds.first}&scope=$scopeSeg&date=$todayKey'
          : 'todayOrders/v5?branch_ids=${branchIds.join(',')}&scope=$scopeSeg&date=$todayKey';

      final networkState = _ref.read(networkStatusProvider);
      if (!networkState.isOnline || !networkState.isBackendReachable) {
        final cached = await OfflineCache.instance.getJson<List<dynamic>>(
          cacheKey,
        );
        if (cached != null) {
          final list = (cached.value)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _otNdjson(
            hypothesisId: 'OT4',
            location: 'order_today_provider.dart:fetchTodayOrders:cache_hit',
            message: 'today orders offline cache hit',
            data: <String, Object?>{'listLen': list.length},
          );
          state = AsyncValue.data(list);
          return;
        }
      }

      // Use real API call instead of mock data
      final baseUrl = NetworkConfig.baseUrl; // Use NetworkConfig for proper URL

      _otNdjson(
        hypothesisId: 'OT2',
        location: 'order_today_provider.dart:fetchTodayOrders:request',
        message: 'fetch orders/daily',
        data: <String, Object?>{
          'role': userState.role.trim().toLowerCase(),
          'userId': userId,
          'branchRaw': userState.branch,
          'branchIds': branchIds,
          'dateKey': todayKey,
          'scopeSeg': scopeSeg,
          'csScoped': _orderTodayOwnUserOnlyScope(userState),
          'online': '${networkState.isOnline}',
          'backendReachable': '${networkState.isBackendReachable}',
          'baseUrl': baseUrl,
          'hasAuthHeader':
              NetworkConfig.defaultHeaders['Authorization']
                  ?.toString()
                  .trim()
                  .isNotEmpty ==
              true,
        },
      );

      final mergedOrders = <Map<String, dynamic>>[];
      var mergedRawCount = 0;
      final dailyClient = http.Client();
      try {
        for (final bid in branchIds) {
          // Build query parameters
          final queryParams = <String, String>{
            'branch_id': bid.toString(),
            'date': todayKey, // ensure server uses the same "today" boundary
          };

          if (_orderTodayOwnUserOnlyScope(userState) && userId != null) {
            queryParams['user_id'] = userId.toString();
          }

          http.Response response;
          var usedPath = '/api/orders/daily';
          var uri = Uri.parse(
            '$baseUrl/api/orders/daily',
          ).replace(queryParameters: queryParams);
          response = await dailyClient
              .get(uri, headers: NetworkConfig.defaultHeaders)
              .timeout(NetworkConfig.connectionTimeout);
          // Backend lama / proxy: coba path tanpa prefix /api.
          if (response.statusCode == 404) {
            usedPath = '/orders/daily';
            uri = Uri.parse(
              '$baseUrl/orders/daily',
            ).replace(queryParameters: queryParams);
            response = await dailyClient
                .get(uri, headers: NetworkConfig.defaultHeaders)
                .timeout(NetworkConfig.connectionTimeout);
          }

          if (response.statusCode != 200) {
            _otNdjson(
              hypothesisId: 'OT1',
              location: 'order_today_provider.dart:fetchTodayOrders:http_fail',
              message: 'orders/daily non-200',
              data: <String, Object?>{
                'statusCode': response.statusCode,
                'usedPath': usedPath,
                'branchId': bid,
                'responseLen': response.body.length,
              },
            );
            throw Exception(
              'Failed to load today orders: ${response.statusCode}',
            );
          }

          final decoded = jsonDecode(response.body);
          if (decoded is! List) {
            _otNdjson(
              hypothesisId: 'OT5',
              location: 'order_today_provider.dart:fetchTodayOrders:bad_shape',
              message: 'orders/daily: body is not JSON array',
              data: <String, Object?>{
                'runtimeType': '${decoded.runtimeType}',
                'branchId': bid,
              },
            );
            throw Exception(
              'orders/daily: expected JSON array, got ${decoded.runtimeType}',
            );
          }

          final rawOrders = decoded
              .map((dynamic order) => Map<String, dynamic>.from(order as Map))
              .toList();
          mergedRawCount += rawOrders.length;

          // Check if response already includes item details (from updated /orders/daily endpoint)
          final hasItemDetails =
              rawOrders.isNotEmpty && rawOrders.first.containsKey('nama_item');

          if (hasItemDetails) {
            mergedOrders.addAll(_groupOrdersWithItems(rawOrders));
          } else {
            // Legacy behavior: fetch order items separately
            final ordersWithItems = await _fetchOrderItemsForOrders(
              rawOrders,
              baseUrl,
              queryParams,
            );
            mergedOrders.addAll(ordersWithItems);
          }
        }
      } finally {
        dailyClient.close();
      }

      _otNdjson(
        hypothesisId: 'OT2',
        location: 'order_today_provider.dart:fetchTodayOrders:ok_merged',
        message: 'orders/daily 200 (merged branches)',
        data: <String, Object?>{
          'branchesMerged': branchIds.length,
          'mergedRawCount': mergedRawCount,
          'mergedOrderCount': mergedOrders.length,
        },
      );

      await OfflineCache.instance.setJson(
        cacheKey,
        mergedOrders,
        ttl: const Duration(minutes: 5),
      );
      state = AsyncValue.data(mergedOrders);
    } catch (error, stackTrace) {
      // Fallback to cache if request failed.
      try {
        final userState = _ref.read(userStateProvider);
        final branchIds = _orderTodayBranchIds(userState);
        if (branchIds.isNotEmpty) {
          final fallbackDate = _localCalendarDateKey();
          final scopeSeg = _orderTodayScopeCacheSegment(userState);
          final cacheKey = branchIds.length == 1
              ? 'todayOrders/v5?branch_id=${branchIds.first}&scope=$scopeSeg&date=$fallbackDate'
              : 'todayOrders/v5?branch_ids=${branchIds.join(',')}&scope=$scopeSeg&date=$fallbackDate';
          final cached = await OfflineCache.instance.getJson<List<dynamic>>(
            cacheKey,
          );
          if (cached != null) {
            final list = (cached.value)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            state = AsyncValue.data(list);
            return;
          }
        }
      } catch (_) {
        // ignore cache errors
      }
      _otNdjson(
        hypothesisId: 'OT1',
        location: 'order_today_provider.dart:fetchTodayOrders:error',
        message: 'today orders fetch failed',
        data: <String, Object?>{
          'err': error.toString().length > 200
              ? error.toString().substring(0, 200)
              : error.toString(),
        },
      );
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchOrderItemsForOrders(
    List<Map<String, dynamic>> orders,
    String baseUrl,
    Map<String, String> queryParams,
  ) async {
    try {
      // Fetch all order items
      final orderItemsUri = Uri.parse(
        '$baseUrl/order-items',
      ).replace(queryParameters: queryParams);
      final client = http.Client();
      final orderItemsResponse = await client
          .get(orderItemsUri, headers: NetworkConfig.defaultHeaders)
          .timeout(NetworkConfig.connectionTimeout);
      client.close();

      if (orderItemsResponse.statusCode == 200) {
        final List<dynamic> orderItemsData = jsonDecode(
          orderItemsResponse.body,
        );

        // Group order items by order_id
        final Map<String, List<Map<String, dynamic>>> itemsByOrderId = {};
        for (var item in orderItemsData) {
          final orderId = item['order_id'].toString();
          if (!itemsByOrderId.containsKey(orderId)) {
            itemsByOrderId[orderId] = [];
          }
          itemsByOrderId[orderId]!.add(Map<String, dynamic>.from(item));
        }

        // Attach items to each order
        return orders.map((order) {
          final orderId = order['order_id'].toString();
          final orderItems = itemsByOrderId[orderId] ?? [];
          return {...order, 'items': orderItems};
        }).toList();
      } else {
        // If order-items endpoint fails, return orders without items
        return orders.map((order) => {...order, 'items': []}).toList();
      }
    } catch (error) {
      // If fetching order items fails, return orders without items
      return orders.map((order) => {...order, 'items': []}).toList();
    }
  }

  List<Map<String, dynamic>> _groupOrdersWithItems(
    List<Map<String, dynamic>> rawData,
  ) {
    // Group data by order_id since JOIN causes duplication
    final Map<String, Map<String, dynamic>> ordersMap = {};

    for (var row in rawData) {
      final orderId = row['order_id'].toString();

      if (!ordersMap.containsKey(orderId)) {
        // Prefer `orders.jumlah` (rounded, after discount). Fallback to rounding `orders.total`.
        final rawJumlah = row['jumlah'];
        final rawTotal = row['total'];
        num? fallbackJumlah;
        if (rawJumlah == null && rawTotal != null) {
          final t = double.tryParse(rawTotal.toString());
          if (t != null) {
            fallbackJumlah = ((t / 5000).ceil() * 5000);
          }
        }

        // Create order entry (exclude item-specific fields)
        ordersMap[orderId] = {
          'order_id': row['order_id'],
          'order_number': row['order_number'],
          'order_type': row['order_type'],
          'customer_id': row['customer_id'],
          'customer_name': row['customer_name'],
          'customer_phone': row['customer_phone'],
          'customer_address': row['customer_address'],
          'branch_id': row['branch_id'],
          'user_id': row['user_id'],
          'status': row['status'],
          'total': row['total'],
          'jumlah': rawJumlah ?? fallbackJumlah,
          'diskon': row['diskon'],
          'mode': row['mode'],
          'created_at': row['created_at'],
          'updated_at': row['updated_at'],
          'items': [],
        };
      }

      // Add item if it exists (check if nama_item is not null)
      if (row['nama_item'] != null) {
        final item = {
          'order_item_id': row['order_item_id'],
          'nama_item': row['nama_item'],
          'kode_produk': row['kode_produk'] ?? row['item_kode'],
          'weight': row['weight'] ?? row['item_weight'],
          'qty': row['qty'],
          'harga_per_gram': row['harga_per_gram'],
          // Source-of-truth from backend (order_items.total)
          'total': row['item_total'] ?? row['total'],
          'material': row['material'] ?? row['item_material'],
          'purity': row['purity'] ?? row['item_purity'],
          'kategori': row['kategori'] ?? row['item_kategori'],
          'jenis': row['jenis'] ?? row['item_jenis'],
          'tipe': row['tipe'] ?? row['item_tipe'],
          'item_id': row['item_id'],
          'photo_produk': row['photo_produk'],
        };

        ordersMap[orderId]!['items'].add(item);
      }
    }

    return ordersMap.values.toList();
  }

  Future<void> refresh() async {
    await fetchTodayOrders();
  }
}
