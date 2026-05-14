import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart'; // Import for NetworkConfig
import 'package:vanessa3/providers/network_provider.dart';
import 'package:vanessa3/data/offline_cache.dart';

// Model untuk System Dashboard Data
class SystemDashboardData {
  final int totalUsers;
  final int activeUsers;
  final int totalBranches;
  final int activeBranches;
  final int totalOrders;
  final double totalRevenue;
  final List<Map<String, dynamic>> recentActivities;
  final DateTime lastUpdated;

  SystemDashboardData({
    required this.totalUsers,
    required this.activeUsers,
    required this.totalBranches,
    required this.activeBranches,
    required this.totalOrders,
    required this.totalRevenue,
    required this.recentActivities,
    required this.lastUpdated,
  });

  factory SystemDashboardData.fromJson(Map<String, dynamic> json) {
    return SystemDashboardData(
      totalUsers: json['total_users'] ?? 0,
      activeUsers: json['active_users'] ?? 0,
      totalBranches: json['total_branches'] ?? 0,
      activeBranches: json['active_branches'] ?? 0,
      totalOrders: json['total_orders'] ?? 0,
      totalRevenue: (json['total_revenue'] ?? 0).toDouble(),
      recentActivities: List<Map<String, dynamic>>.from(json['recent_activities'] ?? []),
      lastUpdated: DateTime.parse(json['last_updated'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_users': totalUsers,
      'active_users': activeUsers,
      'total_branches': totalBranches,
      'active_branches': activeBranches,
      'total_orders': totalOrders,
      'total_revenue': totalRevenue,
      'recent_activities': recentActivities,
      'last_updated': lastUpdated.toIso8601String(),
    };
  }
}

// Provider untuk System Dashboard
final systemDashboardProvider = StateNotifierProvider<SystemDashboardNotifier, AsyncValue<SystemDashboardData>>((ref) {
  return SystemDashboardNotifier(ref);
});

class SystemDashboardNotifier extends StateNotifier<AsyncValue<SystemDashboardData>> {
  final Ref _ref;
  int? _lastUserId;
  String? _lastBranch;

  SystemDashboardNotifier(this._ref) : super(const AsyncValue.loading()) {
    fetchSystemDashboardData();
  }

  // Method untuk mendengarkan perubahan user state
  void listenToUserStateChanges() {
    final userState = _ref.read(userStateProvider);
    if (_lastUserId != userState.userId || _lastBranch != userState.branch) {
      _lastUserId = userState.userId;
      _lastBranch = userState.branch;
      // Delay the fetch to avoid modifying provider during build
      Future.microtask(() => fetchSystemDashboardData());
    }
  }

  Future<void> fetchSystemDashboardData() async {
    state = const AsyncValue.loading();

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final userState = _ref.read(userStateProvider);
      final userId = userState.userId;

      final cacheKey = 'systemDashboard/v1?user_id=${userId ?? ''}';
      final networkState = _ref.read(networkStatusProvider);
      if (!networkState.isOnline || !networkState.isBackendReachable) {
        final cached =
            await OfflineCache.instance.getJson<Map<String, dynamic>>(cacheKey);
        if (cached != null) {
          state = AsyncValue.data(SystemDashboardData.fromJson(cached.value));
          return;
        }
      }

      final queryParams = <String, String>{
        'user_id': userId.toString(),
      };

      final uri = Uri.parse('$baseUrl/api/system/dashboard').replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: NetworkConfig.defaultHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await OfflineCache.instance.setJson(
          cacheKey,
          data,
          ttl: const Duration(minutes: 15),
        );
        final dashboardData = SystemDashboardData.fromJson(data);
        state = AsyncValue.data(dashboardData);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        state = AsyncValue.error(
          'Unauthorized access. Please login again.',
          StackTrace.current,
        );
      } else {
        // Fallback to mock data if API not available
        final mockData = SystemDashboardData(
          totalUsers: 25,
          activeUsers: 20,
          totalBranches: 4,
          activeBranches: 4,
          totalOrders: 150,
          totalRevenue: 50000000.0,
          recentActivities: [
            {'id': 1, 'type': 'user_login', 'description': 'User logged in', 'timestamp': DateTime.now().toIso8601String()},
            {'id': 2, 'type': 'order_created', 'description': 'New order created', 'timestamp': DateTime.now().toIso8601String()},
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
        final cacheKey = 'systemDashboard/v1?user_id=${userId ?? ''}';
        final cached =
            await OfflineCache.instance.getJson<Map<String, dynamic>>(cacheKey);
        if (cached != null) {
          state = AsyncValue.data(SystemDashboardData.fromJson(cached.value));
          return;
        }
      } catch (_) {
        // ignore cache errors
      }
      state = AsyncValue.data(
        SystemDashboardData(
          totalUsers: 0,
          activeUsers: 0,
          totalBranches: 0,
          activeBranches: 0,
          totalOrders: 0,
          totalRevenue: 0.0,
          recentActivities: const [],
          lastUpdated: DateTime.now(),
        ),
      );
    }
  }

  // Method untuk refresh data
  Future<void> refresh() async {
    await fetchSystemDashboardData();
  }

  // Method untuk update data secara real-time
  void updateData(SystemDashboardData newData) {
    state = AsyncValue.data(newData);
  }
}
