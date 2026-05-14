import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/core/state/user_state.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';

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
    final recentRaw = json['recent_assignments'];
    final recent = <Map<String, dynamic>>[];
    if (recentRaw is List) {
      for (final e in recentRaw) {
        if (e is Map<String, dynamic>) {
          recent.add(e);
        } else if (e is Map) {
          recent.add(Map<String, dynamic>.from(e));
        }
      }
    }
    return TechnicianDashboardData(
      pendingWorkOrders: _asInt(json['pending_work_orders']),
      inProgressWorkOrders: _asInt(json['in_progress_work_orders']),
      completedWorkOrders: _asInt(json['completed_work_orders']),
      recentAssignments: recent,
      lastUpdated: DateTime.tryParse(
            json['last_updated']?.toString() ?? '',
          ) ??
          DateTime.now(),
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
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
final technicianDashboardProvider =
    StateNotifierProvider<TechnicianDashboardNotifier, AsyncValue<TechnicianDashboardData>>((ref) {
  return TechnicianDashboardNotifier(ref);
});

class TechnicianDashboardNotifier extends StateNotifier<AsyncValue<TechnicianDashboardData>> {
  TechnicianDashboardNotifier(this._ref) : super(const AsyncValue.loading()) {
    _ref.listen<UserState>(
      userStateProvider,
      (previous, next) {
        final block = next.workshopSessionBlockReason;
        if (block != null) {
          state = AsyncValue.error(block, StackTrace.current);
          return;
        }
        if (previous != null &&
            previous.userId == next.userId &&
            previous.branch == next.branch) {
          return;
        }
        Future.microtask(() => fetchTechnicianDashboardData());
      },
      fireImmediately: true,
    );
  }

  final Ref _ref;

  /// Dipanggil dari UI lama; refresh sudah ditangani [userStateProvider.listen].
  void listenToUserStateChanges() {
    Future.microtask(() => fetchTechnicianDashboardData());
  }

  Future<void> fetchTechnicianDashboardData() async {
    final userState = _ref.read(userStateProvider);
    final block = userState.workshopSessionBlockReason;
    if (block != null) {
      state = AsyncValue.error(block, StackTrace.current);
      return;
    }

    state = const AsyncValue.loading();

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final userId = userState.userId!;
      final branchId = int.tryParse(userState.branch.trim());
      if (branchId == null || branchId <= 0) {
        state = AsyncValue.error(
          'ID cabang tidak valid.',
          StackTrace.current,
        );
        return;
      }

      final queryParams = <String, String>{
        'branch_id': branchId.toString(),
        'user_id': userId.toString(),
      };

      final uri = Uri.parse('$baseUrl/api/technician/dashboard').replace(queryParameters: queryParams);

      final response = await http
          .get(
            uri,
            headers: NetworkConfig.defaultHeaders,
          )
          .timeout(NetworkConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          state = AsyncValue.error(
            'Format respons dashboard tidak valid.',
            StackTrace.current,
          );
          return;
        }
        final data = Map<String, dynamic>.from(decoded);
        final dashboardData = TechnicianDashboardData.fromJson(data);
        state = AsyncValue.data(dashboardData);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        state = AsyncValue.error(
          'Unauthorized access. Please login again.',
          StackTrace.current,
        );
      } else {
        state = AsyncValue.error(
          'Failed to load technician dashboard (${response.statusCode})',
          StackTrace.current,
        );
      }
    } on TimeoutException {
      state = AsyncValue.error(
        'Server tidak merespons (timeout). Periksa jaringan atau coba lagi.',
        StackTrace.current,
      );
    } catch (error) {
      state = AsyncValue.error(
        'Failed to load technician dashboard: $error',
        StackTrace.current,
      );
    }
  }

  Future<void> refresh() async {
    await fetchTechnicianDashboardData();
  }

  void updateData(TechnicianDashboardData newData) {
    state = AsyncValue.data(newData);
  }
}
