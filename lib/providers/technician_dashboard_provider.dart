import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/main.dart'; // Import for userStateProvider
import 'package:vanessa3/utils/network_config.dart'; // Import for NetworkConfig

// Model untuk Technician Dashboard Data
class TechnicianDashboardData {
  final int pendingWorkOrders;
  final int inProgressWorkOrders;
  final int completedWorkOrders;
  final List<Map<String, dynamic>> recentAssignments;
  final DateTime lastUpdated;

  TechnicianDashboardData({
    required this.pendingWorkOrders,
    required this.inProgressWorkOrders,
    required this.completedWorkOrders,
    required this.recentAssignments,
    required this.lastUpdated,
  });

  factory TechnicianDashboardData.fromJson(Map<String, dynamic> json) {
    return TechnicianDashboardData(
      pendingWorkOrders: json['pending_work_orders'] ?? 0,
      inProgressWorkOrders: json['in_progress_work_orders'] ?? 0,
      completedWorkOrders: json['completed_work_orders'] ?? 0,
      recentAssignments: List<Map<String, dynamic>>.from(json['recent_assignments'] ?? []),
      lastUpdated: DateTime.parse(json['last_updated'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pending_work_orders': pendingWorkOrders,
      'in_progress_work_orders': inProgressWorkOrders,
      'completed_work_orders': completedWorkOrders,
      'recent_assignments': recentAssignments,
      'last_updated': lastUpdated.toIso8601String(),
    };
  }
}

// Provider untuk Technician Dashboard
final technicianDashboardProvider = StateNotifierProvider<TechnicianDashboardNotifier, AsyncValue<TechnicianDashboardData>>((ref) {
  return TechnicianDashboardNotifier(ref);
});

class TechnicianDashboardNotifier extends StateNotifier<AsyncValue<TechnicianDashboardData>> {
  final Ref _ref;
  int? _lastUserId;
  String? _lastBranch;

  TechnicianDashboardNotifier(this._ref) : super(const AsyncValue.loading()) {
    fetchTechnicianDashboardData();
  }

  // Method untuk mendengarkan perubahan user state
  void listenToUserStateChanges() {
    final userState = _ref.read(userStateProvider);
    if (_lastUserId != userState.userId || _lastBranch != userState.branch) {
      _lastUserId = userState.userId;
      _lastBranch = userState.branch;
      // Delay the fetch to avoid modifying provider during build
      Future.microtask(() => fetchTechnicianDashboardData());
    }
  }

  Future<void> fetchTechnicianDashboardData() async {
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

      final uri = Uri.parse('$baseUrl/api/technician/dashboard').replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: NetworkConfig.defaultHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final dashboardData = TechnicianDashboardData.fromJson(data);
        state = AsyncValue.data(dashboardData);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        state = AsyncValue.error(
          'Unauthorized access. Please login again.',
          StackTrace.current,
        );
      } else {
        // Fallback to mock data if API not available
        final mockData = TechnicianDashboardData(
          pendingWorkOrders: 5,
          inProgressWorkOrders: 2,
          completedWorkOrders: 8,
          recentAssignments: [
            {'id': 1, 'title': 'Perbaikan Emas Putus', 'status': 'pending'},
            {'id': 2, 'title': 'Polesan Cincin', 'status': 'in_progress'},
          ],
          lastUpdated: DateTime.now(),
        );
        state = AsyncValue.data(mockData);
      }
    } catch (error) {
      // Fallback to mock data on error
      final mockData = TechnicianDashboardData(
        pendingWorkOrders: 0,
        inProgressWorkOrders: 0,
        completedWorkOrders: 0,
        recentAssignments: [],
        lastUpdated: DateTime.now(),
      );
      state = AsyncValue.data(mockData);
    }
  }

  // Method untuk refresh data
  Future<void> refresh() async {
    await fetchTechnicianDashboardData();
  }

  // Method untuk update data secara real-time
  void updateData(TechnicianDashboardData newData) {
    state = AsyncValue.data(newData);
  }
}
