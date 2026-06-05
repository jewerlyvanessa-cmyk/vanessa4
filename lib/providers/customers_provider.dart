import 'dart:convert';

import 'package:flutter_riverpod/legacy.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/core/network/api_exceptions.dart';
import 'package:vanessa3/utils/logger.dart';

final customersProvider =
    StateNotifierProvider<CustomersNotifier, CustomersState>(
  (ref) => CustomersNotifier(),
);

class CustomersState {
  final List<Map<String, dynamic>> customers;
  final bool isLoading;
  final String? error;

  /// Cabang terakhir yang dipakai saat `fetchCustomers(branchId: …)` (untuk refresh CRUD).
  final String? filterBranchId;

  /// Sudah pernah selesai fetch minimal sekali (cegah loop saat daftar kosong).
  final bool hasLoaded;

  const CustomersState({
    required this.customers,
    this.isLoading = false,
    this.error,
    this.filterBranchId,
    this.hasLoaded = false,
  });

  CustomersState copyWith({
    List<Map<String, dynamic>>? customers,
    bool? isLoading,
    String? error,
    String? filterBranchId,
    bool clearFilterBranchId = false,
    bool? hasLoaded,
    bool clearError = false,
  }) {
    return CustomersState(
      customers: customers ?? this.customers,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      filterBranchId: clearFilterBranchId
          ? null
          : (filterBranchId ?? this.filterBranchId),
      hasLoaded: hasLoaded ?? this.hasLoaded,
    );
  }
}

class CustomersNotifier extends StateNotifier<CustomersState> {
  CustomersNotifier() : super(const CustomersState(customers: []));

  Future<void> fetchCustomers({String? branchId, bool silent = false}) async {
    final branchChanged =
        branchId != null &&
        branchId.toString().trim().isNotEmpty &&
        branchId.toString() != (state.filterBranchId ?? '');
    final showFullScreenLoading =
        !silent && (!state.hasLoaded || branchChanged);

    state = state.copyWith(
      isLoading: showFullScreenLoading,
      clearError: true,
      filterBranchId: branchId,
      clearFilterBranchId: branchId == null,
      hasLoaded: branchChanged ? false : state.hasLoaded,
    );

    final query = branchId != null && branchId.toString().trim().isNotEmpty
        ? {'branch_id': branchId.toString()}
        : null;
    Logger.logInfo('DEBUG: Fetching customers from /api/customers');
    try {
      final response = await ApiClient.get('/api/customers', query: query);
      Logger.logInfo('DEBUG: Response status: ${response.statusCode}');
      Logger.logInfo('DEBUG: Response body length: ${response.body.length}');
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        Logger.logInfo('DEBUG: Response data type: ${responseData.runtimeType}');
        if (responseData is List) {
          state = state.copyWith(
            customers: List<Map<String, dynamic>>.from(responseData),
            isLoading: false,
            hasLoaded: true,
          );
          Logger.logInfo(
            'DEBUG: Successfully loaded ${responseData.length} customers',
          );
        } else {
          state = state.copyWith(
            isLoading: false,
            hasLoaded: true,
            error: 'Format data pelanggan tidak valid',
          );
          Logger.logInfo('DEBUG: Invalid data format');
        }
      } else {
        state = state.copyWith(
          isLoading: false,
          hasLoaded: true,
          error: 'Failed to load customers: ${response.statusCode}',
        );
        Logger.logInfo(
          'DEBUG: Failed to load customers: ${response.statusCode}',
        );
      }
    } catch (error) {
      if (error is UnauthorizedException || error is ForbiddenException) {
        state = state.copyWith(
          isLoading: false,
          hasLoaded: true,
          error: error.toString(),
        );
        return;
      }
      Logger.logInfo('DEBUG: Error fetching customers: $error');
      state = state.copyWith(
        customers: [],
        isLoading: false,
        hasLoaded: true,
        error: 'Network error occurred: $error',
      );
    }
  }

  Future<bool> addCustomer({
    required String name,
    String? phone,
    String? email,
    String? address,
    String? branchId,
  }) async {
    try {
      final phoneTrim = phone?.trim() ?? '';
      final body = <String, dynamic>{
        'name': name.trim(),
        'phone': phoneTrim.isEmpty ? null : phoneTrim,
        'address': (address == null || address.trim().isEmpty)
            ? null
            : address.trim(),
      };
      final emailTrim = email?.trim();
      if (emailTrim != null && emailTrim.isNotEmpty) {
        body['email'] = emailTrim;
      }
      final branch = branchId?.trim();
      if (branch != null && branch.isNotEmpty) {
        body['branch_id'] = branch;
      }

      final response = await ApiClient.post(
        '/api/customers',
        body: json.encode(body),
      );
      if (response.statusCode == 201) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          await fetchCustomers(branchId: state.filterBranchId, silent: true);
          return true;
        }
        state = state.copyWith(
          error:
              responseData['message']?.toString() ?? 'Gagal menambah pelanggan',
        );
        return false;
      }
      Map<String, dynamic>? responseData;
      try {
        responseData = json.decode(response.body) as Map<String, dynamic>?;
      } catch (_) {}
      state = state.copyWith(
        error:
            responseData?['message']?.toString() ??
            'Gagal menambah pelanggan (${response.statusCode})',
      );
      return false;
    } catch (error) {
      state = state.copyWith(error: 'Kesalahan jaringan: $error');
      return false;
    }
  }

  Future<bool> editCustomer(
    String id,
    String name,
    String email,
    String phone,
    String address,
  ) async {
    try {
      final response = await ApiClient.patch(
        '/api/customers/$id',
        body: json.encode({
          'name': name,
          'email': email.trim().isEmpty ? null : email.trim(),
          'phone': phone.trim().isEmpty ? null : phone.trim(),
          'address': address.trim().isEmpty ? null : address.trim(),
        }),
      );
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          await fetchCustomers(branchId: state.filterBranchId, silent: true);
          return true;
        } else {
          state = state.copyWith(
            error: responseData['message'] ?? 'Failed to update customer',
          );
          return false;
        }
      } else {
        final responseData = json.decode(response.body);
        state = state.copyWith(
          error: responseData['message'] ?? 'Failed to update customer',
        );
        return false;
      }
    } catch (error) {
      state = state.copyWith(error: 'Network error occurred');
      return false;
    }
  }

  Future<void> deleteCustomer(String id) async {
    try {
      final response = await ApiClient.delete('/api/customers/$id');
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          await fetchCustomers(branchId: state.filterBranchId, silent: true);
        } else {
          state = state.copyWith(
            error: responseData['message'] ?? 'Failed to delete customer',
          );
        }
      } else {
        final responseData = json.decode(response.body);
        state = state.copyWith(
          error: responseData['message'] ?? 'Failed to delete customer',
        );
      }
    } catch (error) {
      state = state.copyWith(error: 'Network error occurred');
    }
  }
}
