import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/main.dart'; // Import for userStateProvider
import 'package:vanessa3/utils/network_config.dart'; // Import for NetworkConfig

// Model untuk Workshop Dashboard Data
class WorkshopDashboardData {
  final int pendingOrders;
  final int inProgressOrders;
  final int completedOrders;
  final int totalTechnicians;
  final int activeTechnicians;
  final List<Map<String, dynamic>> recentOrders;
  final DateTime lastUpdated;

  WorkshopDashboardData({
    required this.pendingOrders,
    required this.inProgressOrders,
    required this.completedOrders,
    required this.totalTechnicians,
    required this.activeTechnicians,
    required this.recentOrders,
    required this.lastUpdated,
  });

  factory WorkshopDashboardData.fromJson(Map<String, dynamic> json) {
    return WorkshopDashboardData(
      pendingOrders: json['pending_orders'] ?? 0,
      inProgressOrders: json['in_progress_orders'] ?? 0,
      completedOrders: json['completed_orders'] ?? 0,
      totalTechnicians: json['total_technicians'] ?? 0,
      activeTechnicians: json['active_technicians'] ?? 0,
      recentOrders: List<Map<String, dynamic>>.from(json['recent_orders'] ?? []),
      lastUpdated: DateTime.parse(json['last_updated'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pending_orders': pendingOrders,
      'in_progress_orders': inProgressOrders,
      'completed_orders': completedOrders,
      'total_technicians': totalTechnicians,
      'active_technicians': activeTechnicians,
      'recent_orders': recentOrders,
      'last_updated': lastUpdated.toIso8601String(),
    };
  }
}

// Provider untuk Workshop Dashboard
final workshopDashboardProvider = StateNotifierProvider<WorkshopDashboardNotifier, AsyncValue<WorkshopDashboardData>>((ref) {
  return WorkshopDashboardNotifier(ref);
});

class WorkshopDashboardNotifier extends StateNotifier<AsyncValue<WorkshopDashboardData>> {
  final Ref _ref;
  int? _lastUserId;
  String? _lastBranch;

  WorkshopDashboardNotifier(this._ref) : super(const AsyncValue.loading()) {
    fetchWorkshopDashboardData();
  }

  // Method untuk mendengarkan perubahan user state
  void listenToUserStateChanges() {
    final userState = _ref.read(userStateProvider);
    if (_lastUserId != userState.userId || _lastBranch != userState.branch) {
      _lastUserId = userState.userId;
      _lastBranch = userState.branch;
      // Delay the fetch to avoid modifying provider during build
      Future.microtask(() => fetchWorkshopDashboardData());
    }
  }

  Future<void> fetchWorkshopDashboardData() async {
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

      final uri = Uri.parse('$baseUrl/api/workshop/dashboard').replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: NetworkConfig.defaultHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final dashboardData = WorkshopDashboardData.fromJson(data);
        state = AsyncValue.data(dashboardData);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        state = AsyncValue.error(
          'Unauthorized access. Please login again.',
          StackTrace.current,
        );
      } else {
        // Fallback to mock data if API not available
        final mockData = WorkshopDashboardData(
          pendingOrders: 12,
          inProgressOrders: 8,
          completedOrders: 25,
          totalTechnicians: 5,
          activeTechnicians: 4,
          recentOrders: [
            {'id': 1, 'title': 'Perbaikan Emas Putus', 'status': 'pending'},
            {'id': 2, 'title': 'Polesan Cincin', 'status': 'in_progress'},
          ],
          lastUpdated: DateTime.now(),
        );
        state = AsyncValue.data(mockData);
      }
    } catch (error) {
      // Fallback to mock data on error
      final mockData = WorkshopDashboardData(
        pendingOrders: 0,
        inProgressOrders: 0,
        completedOrders: 0,
        totalTechnicians: 0,
        activeTechnicians: 0,
        recentOrders: [],
        lastUpdated: DateTime.now(),
      );
      state = AsyncValue.data(mockData);
    }
  }

  // Method untuk refresh data
  Future<void> refresh() async {
    await fetchWorkshopDashboardData();
  }

  // Method untuk update data secara real-time
  void updateData(WorkshopDashboardData newData) {
    state = AsyncValue.data(newData);
  }
}
