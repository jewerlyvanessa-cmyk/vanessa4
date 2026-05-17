import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../core/network/api_client.dart';
import '../utils/network_config.dart';

class UnauthorizedApiException implements Exception {
  final String message;
  UnauthorizedApiException([
    this.message = 'Session expired. Please login again.',
  ]);

  @override
  String toString() => message;
}

class ForbiddenApiException implements Exception {
  final String message;
  ForbiddenApiException([this.message = 'Akses ditolak.']);

  @override
  String toString() => message;
}

String _responseErrorSummary(http.Response response) {
  final body = response.body.trim();
  if (body.isEmpty) return 'HTTP ${response.statusCode}';
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final error = decoded['error']?.toString().trim();
      final details = decoded['details']?.toString().trim();
      final parts = <String>[];
      if (error != null && error.isNotEmpty) parts.add(error);
      if (details != null && details.isNotEmpty) parts.add(details);
      if (parts.isNotEmpty) return parts.join(' — ');
    }
  } catch (_) {
    // fall through
  }
  return body;
}

class ApiService {
  static String get baseUrl => NetworkConfig.baseUrl;

  // Retry configuration
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 1);

  /// Generic HTTP request method with retry logic and timeout
  static Future<http.Response> _makeRequest(
    Future<http.Response> Function() request, {
    int retries = maxRetries,
    Duration? timeout,
  }) async {
    timeout ??= NetworkConfig.connectionTimeout;

    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final response = await request().timeout(timeout);
        if (response.statusCode == 401) {
          NetworkConfig.setAuthToken(null);
          NetworkConfig.notifyUnauthorized();
          throw UnauthorizedApiException();
        }
        if (response.statusCode == 403) {
          throw ForbiddenApiException(_responseErrorSummary(response));
        }
        return response;
      } on UnauthorizedApiException {
        rethrow;
      } on ForbiddenApiException {
        rethrow;
      } on TimeoutException {
        if (attempt == retries) {
          throw Exception('Request timeout after ${timeout.inSeconds} seconds');
        }
        debugPrint(
          'Request timeout, retrying... (attempt ${attempt + 1}/${retries + 1})',
        );
        await Future.delayed(retryDelay * (attempt + 1));
      } on http.ClientException catch (e) {
        if (attempt == retries) {
          throw Exception('Network error: ${e.message}');
        }
        debugPrint(
          'Network error, retrying... (attempt ${attempt + 1}/${retries + 1})',
        );
        await Future.delayed(retryDelay * (attempt + 1));
      } catch (e) {
        if (attempt == retries) {
          throw Exception('Request failed: $e');
        }
        debugPrint(
          'Request failed, retrying... (attempt ${attempt + 1}/${retries + 1})',
        );
        await Future.delayed(retryDelay * (attempt + 1));
      }
    }

    throw Exception('Request failed after $retries retries');
  }

  /// Returns a map: { 'success': bool, 'role': String? }
  static Future<Map<String, dynamic>> login(
    String username,
    String password,
  ) async {
    final url = Uri.parse('$baseUrl/login');

    try {
      final response = await _makeRequest(
        () => ApiClient.post(
          url.toString(),
          body: jsonEncode({'username': username, 'password': password}),
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token']?.toString();
        if (token != null && token.isNotEmpty) {
          NetworkConfig.setAuthToken(token);
        }
        // Kirim semua field yang relevan dari backend
        return {
          'success': data['success'] ?? true,
          'user_id': data['user_id'],
          'username': data['username'] ?? '',
          'role': data['role'] ?? '',
          'mainModule': data['mainModule'] ?? '',
          'branch': data['branch'] ?? '',
          'roles': data['roles'] ?? [],
          'branches': data['branches'] ?? [],
          'token': token ?? '',
        };
      } else {
        NetworkConfig.setAuthToken(null);
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'error': data['error'] ?? 'Login failed',
          'role': '',
          'mainModule': '',
          'branch': '',
        };
      }
    } catch (e) {
      NetworkConfig.setAuthToken(null);
      return {
        'success': false,
        'error': 'Network error: Unable to connect to server',
        'role': '',
        'mainModule': '',
        'branch': '',
      };
    }
  }

  /// Minta JWT baru untuk cabang + peran yang dipilih (harus ada di user_branch_roles).
  static Future<Map<String, dynamic>> switchSessionContext({
    required String branchId,
    required String role,
  }) async {
    final url = Uri.parse('$baseUrl/api/auth/switch-context');
    final response = await _makeRequest(
      () => http.post(
        url,
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({
          'branch_id': branchId,
          'role': role.trim().toLowerCase(),
        }),
      ),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'switch-context failed: ${response.statusCode} ${_responseErrorSummary(response)}',
      );
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw Exception('switch-context: invalid response');
    }
    final token = data['token']?.toString();
    if (token != null && token.isNotEmpty) {
      NetworkConfig.setAuthToken(token);
    }
    return data;
  }

  /// Fetch all customers
  static Future<List<Map<String, dynamic>>> getCustomers() async {
    final url = Uri.parse('$baseUrl/api/customers');

    try {
      final response = await _makeRequest(
        () => http.get(url, headers: NetworkConfig.defaultHeaders),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data
            .map((customer) => customer as Map<String, dynamic>)
            .toList();
      } else {
        throw Exception('Failed to fetch customers: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching customers: $e');
      throw Exception('Failed to fetch customers: $e');
    }
  }

  /// Add a new customer
  static Future<bool> addCustomer(Map<String, dynamic> customer) async {
    final url = Uri.parse('$baseUrl/api/customers');

    try {
      final response = await _makeRequest(
        () => http.post(
          url,
          headers: NetworkConfig.defaultHeaders,
          body: jsonEncode(customer),
        ),
      );

      return response.statusCode == 201;
    } catch (e) {
      debugPrint('Error adding customer: $e');
      throw Exception('Failed to add customer: $e');
    }
  }

  /// Update an existing customer
  static Future<bool> updateCustomer(
    int id,
    Map<String, dynamic> customer,
  ) async {
    final url = Uri.parse('$baseUrl/api/customers/$id');

    try {
      final response = await _makeRequest(
        () => http.put(
          url,
          headers: NetworkConfig.defaultHeaders,
          body: jsonEncode(customer),
        ),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error updating customer: $e');
      throw Exception('Failed to update customer: $e');
    }
  }

  /// Delete a customer
  static Future<bool> deleteCustomer(int id) async {
    final url = Uri.parse('$baseUrl/api/customers/$id');

    try {
      final response = await _makeRequest(
        () => http.delete(url, headers: NetworkConfig.defaultHeaders),
      );

      return response.statusCode == 204;
    } catch (e) {
      debugPrint('Error deleting customer: $e');
      throw Exception('Failed to delete customer: $e');
    }
  }

  /// Antrian kerja workshop di cabang. [assignedTechnicianId] hanya untuk filter
  /// pekerjaan milik tukang (user_id / metadata assignment) — dipakai halaman Update Progress.
  static Future<List<Map<String, dynamic>>> getWorkQueue(
    String branchId, {
    String? assignedTechnicianId,
    bool unassignedOnly = false,
  }) async {
    final qp = <String, String>{'branch_id': branchId};
    final aid = assignedTechnicianId?.trim() ?? '';
    if (aid.isNotEmpty) {
      qp['technician_id'] = aid;
    }
    if (unassignedOnly) {
      qp['unassigned_only'] = '1';
    }
    final url = Uri.parse(
      '$baseUrl/api/workshop/work-queue',
    ).replace(queryParameters: qp);

    try {
      final response = await _makeRequest(
        () => http.get(url, headers: NetworkConfig.defaultHeaders),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((item) => item as Map<String, dynamic>).toList();
      } else {
        throw Exception('Failed to fetch work queue: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching work queue: $e');
      throw Exception('Failed to fetch work queue: $e');
    }
  }

  /// Get material stock for workshop
  static Future<List<Map<String, dynamic>>> getMaterialStock(
    String branchId,
  ) async {
    final url = Uri.parse(
      '$baseUrl/api/workshop/material-stock?branch_id=$branchId',
    );

    try {
      final response = await _makeRequest(
        () => http.get(url, headers: NetworkConfig.defaultHeaders),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((item) => item as Map<String, dynamic>).toList();
      } else {
        throw Exception(
          'Failed to fetch material stock: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('getMaterialStock failed: $e');
      throw Exception('Failed to fetch material stock: $e');
    }
  }

  /// Get workshop reports
  static Future<Map<String, dynamic>> getWorkshopReports(
    String branchId, {
    String period = 'month',
  }) async {
    final url = Uri.parse(
      '$baseUrl/api/workshop/reports?branch_id=$branchId&period=$period',
    );

    try {
      final response = await _makeRequest(
        () => http.get(url, headers: NetworkConfig.defaultHeaders),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception(
          'Failed to fetch workshop reports: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Error fetching workshop reports: $e');
      throw Exception('Failed to fetch workshop reports: $e');
    }
  }

  /// GET /api/orders/ready-for-pickup-list — daftar service/custom siap ambil (sudah diterima admin toko).
  static Future<List<Map<String, dynamic>>> getReadyForPickupList(
    String branchId,
  ) async {
    final url = Uri.parse('$baseUrl/api/orders/ready-for-pickup-list').replace(
      queryParameters: <String, String>{'branch_id': branchId},
    );
    final response = await _makeRequest(
      () => http.get(url, headers: NetworkConfig.defaultHeaders),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    var msg = 'HTTP ${response.statusCode}';
    try {
      final d = jsonDecode(response.body);
      if (d is Map && d['error'] != null) msg = d['error'].toString();
    } catch (_) {}
    throw Exception('Gagal memuat daftar siap ambil: $msg');
  }

  /// POST /api/orders/confirm-workshop-store-receipt — admin toko konfirmasi terima dari workshop.
  static Future<bool> confirmWorkshopStoreReceipt({
    required int orderId,
    required String branchId,
  }) async {
    final url = Uri.parse(
      '$baseUrl/api/orders/confirm-workshop-store-receipt',
    );
    final response = await _makeRequest(
      () => http.post(
        url,
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({
          'order_id': orderId,
          'branch_id': int.tryParse(branchId) ?? branchId,
        }),
      ),
    );
    if (response.statusCode == 200) return true;
    String msg = response.body;
    try {
      final d = jsonDecode(response.body);
      if (d is Map && d['error'] != null) msg = d['error'].toString();
    } catch (_) {}
    throw Exception('Gagal konfirmasi terima: $msg');
  }

  /// GET /technicians — daftar tukang aktif di cabang (admin workshop).
  static Future<List<Map<String, dynamic>>> getTechnicians(String branchId) async {
    final url = Uri.parse('$baseUrl/technicians').replace(
      queryParameters: <String, String>{'branch_id': branchId},
    );
    final response = await _makeRequest(
      () => http.get(url, headers: NetworkConfig.defaultHeaders),
    );
    if (response.statusCode != 200) {
      throw Exception('Gagal memuat daftar tukang: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// PUT /workshop-orders/:id/assign-technician — admin workshop menugaskan tukang.
  static Future<bool> assignWorkshopTechnician({
    required int orderId,
    required String branchId,
    required int technicianId,
    bool startImmediately = false,
  }) async {
    final url = Uri.parse('$baseUrl/workshop-orders/$orderId/assign-technician');
    final response = await _makeRequest(
      () => http.put(
        url,
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({
          'branch_id': int.tryParse(branchId) ?? branchId,
          'technician_id': technicianId,
          'start_immediately': startImmediately,
        }),
      ),
    );
    if (response.statusCode == 200) return true;
    var msg = 'HTTP ${response.statusCode}';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] != null) {
        msg = decoded['error'].toString();
      }
    } catch (_) {}
    throw Exception(msg);
  }

  /// Update work progress
  static Future<bool> updateWorkProgress(
    int orderId,
    String status,
    String technicianId, {
    String notes = '',
    required String branchId,
  }) async {
    final url = Uri.parse('$baseUrl/api/workshop/update-progress');

    try {
      final response = await _makeRequest(
        () => http.post(
          url,
          headers: NetworkConfig.defaultHeaders,
          body: jsonEncode({
            'order_id': orderId,
            'status': status,
            'technician_id': technicianId,
            'notes': notes,
            'branch_id': branchId,
          }),
        ),
      );

      if (response.statusCode == 200) return true;

      var msg = 'HTTP ${response.statusCode}';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final d = decoded['details']?.toString().trim();
          final e = decoded['error']?.toString().trim();
          if (d != null && d.isNotEmpty) {
            msg = d;
          } else if (e != null && e.isNotEmpty) {
            msg = e;
          }
        }
      } catch (_) {}
      throw Exception(msg);
    } catch (e) {
      debugPrint('Error updating work progress: $e');
      if (e is Exception) rethrow;
      throw Exception('Failed to update work progress: $e');
    }
  }

  /// GET /api/workshop/order-cost-breakdown — riwayat & revisi terakhir
  static Future<Map<String, dynamic>> getOrderCostBreakdown(
    int orderId,
    String branchId,
  ) async {
    final url = Uri.parse('$baseUrl/api/workshop/order-cost-breakdown').replace(
      queryParameters: <String, String>{
        'order_id': orderId.toString(),
        'branch_id': branchId,
      },
    );
    final response = await _makeRequest(
      () => http.get(url, headers: NetworkConfig.defaultHeaders),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw Exception('Invalid cost breakdown response');
    }
    throw Exception(
      'Gagal memuat biaya: ${response.statusCode} ${response.body}',
    );
  }

  /// POST /api/workshop/order-cost-breakdown — simpan revisi + sinkron orders.total (backend)
  static Future<Map<String, dynamic>> submitOrderCostBreakdown({
    required int orderId,
    required String branchId,
    required double materialCost,
    required double laborCost,
    required double otherCost,
    String notes = '',
  }) async {
    final url = Uri.parse('$baseUrl/api/workshop/order-cost-breakdown');
    final response = await _makeRequest(
      () => http.post(
        url,
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({
          'order_id': orderId,
          'branch_id': int.tryParse(branchId) ?? branchId,
          'material_cost': materialCost,
          'labor_cost': laborCost,
          'other_cost': otherCost,
          'notes': notes,
        }),
      ),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw Exception('Invalid submit response');
    }
    String msg = response.body;
    try {
      final d = jsonDecode(response.body);
      if (d is Map && d['error'] != null) msg = d['error'].toString();
    } catch (_) {}
    throw Exception('Gagal simpan biaya (${response.statusCode}): $msg');
  }

  /// Update material stock
  static Future<bool> updateMaterialStock(
    int itemId,
    double quantity,
    String technicianId, {
    String notes = '',
  }) async {
    final url = Uri.parse('$baseUrl/api/workshop/update-stock');

    try {
      final response = await _makeRequest(
        () => http.post(
          url,
          headers: NetworkConfig.defaultHeaders,
          body: jsonEncode({
            'item_id': itemId,
            'quantity': quantity,
            'technician_id': technicianId,
            'notes': notes,
          }),
        ),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error updating material stock: $e');
      throw Exception('Failed to update material stock: $e');
    }
  }

  /// Get work history for technician
  static Future<List<Map<String, dynamic>>> getWorkHistory(
    String technicianId,
    String branchId, {
    String period = 'all',
  }) async {
    final url = Uri.parse(
      '$baseUrl/api/workshop/work-history?technician_id=$technicianId&branch_id=$branchId&period=$period',
    );

    try {
      final response = await _makeRequest(
        () => http.get(url, headers: NetworkConfig.defaultHeaders),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((item) => item as Map<String, dynamic>).toList();
      } else {
        throw Exception('Failed to fetch work history: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching work history: $e');
      throw Exception('Failed to fetch work history: $e');
    }
  }

  /// Get technician reports
  static Future<Map<String, dynamic>> getTechnicianReports(
    String technicianId,
    String branchId, {
    String period = 'today',
  }) async {
    final url = Uri.parse(
      '$baseUrl/api/workshop/technician-reports?technician_id=$technicianId&branch_id=$branchId&period=$period',
    );

    try {
      final response = await _makeRequest(
        () => http.get(url, headers: NetworkConfig.defaultHeaders),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception(
          'Failed to fetch technician reports: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Error fetching technician reports: $e');
      throw Exception('Failed to fetch technician reports: $e');
    }
  }
}
