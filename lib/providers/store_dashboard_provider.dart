import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart'; // Import for NetworkConfig
import 'package:vanessa3/providers/network_provider.dart';
import 'package:vanessa3/data/offline_cache.dart';

// Model untuk Store Dashboard Data
class StoreDashboardData {
  final int todayOrders;
  final int todayPayments;
  final double todayRevenue;
  final int totalEmployees;
  final int activeEmployees;
  final List<Map<String, dynamic>> recentTransactions;
  final DateTime lastUpdated;

  StoreDashboardData({
    required this.todayOrders,
    required this.todayPayments,
    required this.todayRevenue,
    required this.totalEmployees,
    required this.activeEmployees,
    required this.recentTransactions,
    required this.lastUpdated,
  });

  factory StoreDashboardData.fromJson(Map<String, dynamic> json) {
    return StoreDashboardData(
      todayOrders: json['today_orders'] ?? 0,
      todayPayments: json['today_payments'] ?? 0,
      todayRevenue: (json['today_revenue'] ?? 0).toDouble(),
      totalEmployees: json['total_employees'] ?? 0,
      activeEmployees: json['active_employees'] ?? 0,
      recentTransactions: List<Map<String, dynamic>>.from(json['recent_transactions'] ?? []),
      lastUpdated: DateTime.parse(json['last_updated'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'today_orders': todayOrders,
      'today_payments': todayPayments,
      'today_revenue': todayRevenue,
      'total_employees': totalEmployees,
      'active_employees': activeEmployees,
      'recent_transactions': recentTransactions,
      'last_updated': lastUpdated.toIso8601String(),
    };
  }
}

// Provider untuk Store Dashboard
final storeDashboardProvider = StateNotifierProvider<StoreDashboardNotifier, AsyncValue<StoreDashboardData>>((ref) {
  return StoreDashboardNotifier(ref);
});

class StoreDashboardNotifier extends StateNotifier<AsyncValue<StoreDashboardData>> {
  final Ref _ref;
  int? _lastUserId;
  String? _lastBranch;

  StoreDashboardNotifier(this._ref) : super(const AsyncValue.loading()) {
    fetchStoreDashboardData();
  }

  // Method untuk mendengarkan perubahan user state
  void listenToUserStateChanges() {
    final userState = _ref.read(userStateProvider);
    if (_lastUserId != userState.userId || _lastBranch != userState.branch) {
      _lastUserId = userState.userId;
      _lastBranch = userState.branch;
      fetchStoreDashboardData();
    }
  }

  Future<void> fetchStoreDashboardData() async {
    state = const AsyncValue.loading();

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final userState = _ref.read(userStateProvider);
      final userId = userState.userId;
      final branchId = int.tryParse(userState.branch) ?? 1;

      final cacheKey = 'storeDashboard/v1?branch_id=$branchId&user_id=${userId ?? ''}';
      final networkState = _ref.read(networkStatusProvider);
      if (!networkState.isOnline || !networkState.isBackendReachable) {
        final cached =
            await OfflineCache.instance.getJson<Map<String, dynamic>>(cacheKey);
        if (cached != null) {
          state = AsyncValue.data(StoreDashboardData.fromJson(cached.value));
          return;
        }
      }

      final queryParams = <String, String>{
        'branch_id': branchId.toString(),
        'user_id': userId.toString(),
      };

      final uri = Uri.parse('$baseUrl/api/store/dashboard').replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: NetworkConfig.defaultHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await OfflineCache.instance.setJson(
          cacheKey,
          data,
          ttl: const Duration(minutes: 10),
        );
        final dashboardData = StoreDashboardData.fromJson(data);
        state = AsyncValue.data(dashboardData);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        state = AsyncValue.error(
          'Unauthorized access. Please login again.',
          StackTrace.current,
        );
      } else {
        // Fallback to mock data if API not available
        final mockData = StoreDashboardData(
          todayOrders: 15,
          todayPayments: 12,
          todayRevenue: 2500000.0,
          totalEmployees: 8,
          activeEmployees: 7,
          recentTransactions: [
            {'id': 1, 'type': 'sale', 'amount': 500000, 'status': 'completed'},
            {'id': 2, 'type': 'payment', 'amount': 750000, 'status': 'pending'},
          ],
          lastUpdated: DateTime.now(),
        );
        state = AsyncValue.data(mockData);
      }
    } catch (error) {
      // Fallback to cache if available, otherwise minimal empty data.
      try {
        final userState = _ref.read(userStateProvider);
        final userId = userState.userId;
        final branchId = int.tryParse(userState.branch) ?? 1;
        final cacheKey =
            'storeDashboard/v1?branch_id=$branchId&user_id=${userId ?? ''}';
        final cached =
            await OfflineCache.instance.getJson<Map<String, dynamic>>(cacheKey);
        if (cached != null) {
          state = AsyncValue.data(StoreDashboardData.fromJson(cached.value));
          return;
        }
      } catch (_) {
        // ignore cache errors
      }
      state = AsyncValue.data(
        StoreDashboardData(
          todayOrders: 0,
          todayPayments: 0,
          todayRevenue: 0.0,
          totalEmployees: 0,
          activeEmployees: 0,
          recentTransactions: const [],
          lastUpdated: DateTime.now(),
        ),
      );
    }
  }

  // Method untuk refresh data
  Future<void> refresh() async {
    await fetchStoreDashboardData();
  }

  // Method untuk update data secara real-time
  void updateData(StoreDashboardData newData) {
    state = AsyncValue.data(newData);
  }
}
