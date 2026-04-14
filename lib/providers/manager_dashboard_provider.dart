import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/main.dart'; // Import for userStateProvider
import 'package:vanessa3/utils/network_config.dart'; // Import for NetworkConfig

// Model untuk Manager Dashboard Data
class ManagerDashboardData {
  final double monthlyRevenue;
  final double monthlyTarget;
  final int monthlyOrders;
  final double performancePercentage;
  final List<Map<String, dynamic>> branchPerformance;
  final List<Map<String, dynamic>> topProducts;
  final DateTime lastUpdated;

  ManagerDashboardData({
    required this.monthlyRevenue,
    required this.monthlyTarget,
    required this.monthlyOrders,
    required this.performancePercentage,
    required this.branchPerformance,
    required this.topProducts,
    required this.lastUpdated,
  });

  factory ManagerDashboardData.fromJson(Map<String, dynamic> json) {
    return ManagerDashboardData(
      monthlyRevenue: (json['monthly_revenue'] ?? 0).toDouble(),
      monthlyTarget: (json['monthly_target'] ?? 0).toDouble(),
      monthlyOrders: json['monthly_orders'] ?? 0,
      performancePercentage: (json['performance_percentage'] ?? 0).toDouble(),
      branchPerformance: List<Map<String, dynamic>>.from(json['branch_performance'] ?? []),
      topProducts: List<Map<String, dynamic>>.from(json['top_products'] ?? []),
      lastUpdated: DateTime.parse(json['last_updated'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'monthly_revenue': monthlyRevenue,
      'monthly_target': monthlyTarget,
      'monthly_orders': monthlyOrders,
      'performance_percentage': performancePercentage,
      'branch_performance': branchPerformance,
      'top_products': topProducts,
      'last_updated': lastUpdated.toIso8601String(),
    };
  }
}

// Provider untuk Manager Dashboard
final managerDashboardProvider = StateNotifierProvider<ManagerDashboardNotifier, AsyncValue<ManagerDashboardData>>((ref) {
  return ManagerDashboardNotifier(ref);
});

class ManagerDashboardNotifier extends StateNotifier<AsyncValue<ManagerDashboardData>> {
  final Ref _ref;
  int? _lastUserId;
  String? _lastBranch;

  ManagerDashboardNotifier(this._ref) : super(const AsyncValue.loading()) {
    fetchManagerDashboardData();
  }

  // Method untuk mendengarkan perubahan user state
  void listenToUserStateChanges() {
    final userState = _ref.read(userStateProvider);
    if (_lastUserId != userState.userId || _lastBranch != userState.branch) {
      _lastUserId = userState.userId;
      _lastBranch = userState.branch;
      fetchManagerDashboardData();
    }
  }

  Future<void> fetchManagerDashboardData() async {
    state = const AsyncValue.loading();

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final userState = _ref.read(userStateProvider);
      final userId = userState.userId;
      final branchId = int.tryParse(userState.branch) ?? 1;

      final queryParams = <String, String>{
        'branch_id': branchId.toString(),
        'user_id': userId.toString(),
      };

      final uri = Uri.parse('$baseUrl/api/manager/dashboard').replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final dashboardData = ManagerDashboardData.fromJson(data);
        state = AsyncValue.data(dashboardData);
      } else {
        // Fallback to mock data if API not available
        final mockData = ManagerDashboardData(
          monthlyRevenue: 15000000.0,
          monthlyTarget: 20000000.0,
          monthlyOrders: 120,
          performancePercentage: 75.0,
          branchPerformance: [
            {'branch': 'Toko Brangkal', 'revenue': 8000000, 'orders': 60},
            {'branch': 'Workshop Kendalsari', 'revenue': 5000000, 'orders': 40},
            {'branch': 'Toko Pohjejer', 'revenue': 2000000, 'orders': 20},
          ],
          topProducts: [
            {'name': 'Cincin Emas', 'sales': 25},
            {'name': 'Kalung Emas', 'sales': 18},
            {'name': 'Anting Emas', 'sales': 15},
          ],
          lastUpdated: DateTime.now(),
        );
        state = AsyncValue.data(mockData);
      }
    } catch (error) {
      // Fallback to mock data on error
      final mockData = ManagerDashboardData(
        monthlyRevenue: 0.0,
        monthlyTarget: 0.0,
        monthlyOrders: 0,
        performancePercentage: 0.0,
        branchPerformance: [],
        topProducts: [],
        lastUpdated: DateTime.now(),
      );
      state = AsyncValue.data(mockData);
    }
  }

  // Method untuk refresh data
  Future<void> refresh() async {
    await fetchManagerDashboardData();
  }

  // Method untuk update data secara real-time
  void updateData(ManagerDashboardData newData) {
    state = AsyncValue.data(newData);
  }
}
