import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../utils/network_config.dart';

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
        return response;
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
    final urlsToTry = [baseUrl, ...NetworkConfig.getAlternativeBaseUrls()];

    for (final currentBaseUrl in urlsToTry) {
      final url = Uri.parse('$currentBaseUrl/login');

      try {
        debugPrint('Trying login with URL: $currentBaseUrl');

        final response = await http
            .post(
              url,
              headers: NetworkConfig.defaultHeaders,
              body: jsonEncode({'username': username, 'password': password}),
            )
            .timeout(NetworkConfig.connectionTimeout);

        debugPrint('Raw login response: ${response.body}');

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
        debugPrint('Login failed with URL $currentBaseUrl: $e');
        // Continue to next URL if this one fails
        continue;
      }
    }

    // If all URLs failed
    debugPrint('Login failed with all URLs');
    NetworkConfig.setAuthToken(null);
    return {
      'success': false,
      'error': 'Network error: Unable to connect to server',
      'role': '',
      'mainModule': '',
      'branch': '',
    };
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

  /// Get work queue for technician
  static Future<List<Map<String, dynamic>>> getWorkQueue(
    String technicianId,
    String branchId,
  ) async {
    final url = Uri.parse(
      '$baseUrl/api/workshop/work-queue?technician_id=$technicianId&branch_id=$branchId',
    );

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
    final urlsToTry = [baseUrl, ...NetworkConfig.getAlternativeBaseUrls()];

    for (final currentBaseUrl in urlsToTry) {
      final url = Uri.parse(
        '$currentBaseUrl/api/workshop/material-stock?branch_id=$branchId',
      );

      try {
        debugPrint('Trying getMaterialStock with URL: $currentBaseUrl');

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
        debugPrint('getMaterialStock failed with URL $currentBaseUrl: $e');
        // Continue to next URL if this one fails
        continue;
      }
    }

    // If all URLs failed
    debugPrint('getMaterialStock failed with all URLs');
    throw Exception('Failed to fetch material stock: Network error');
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

  /// Update work progress
  static Future<bool> updateWorkProgress(
    int orderId,
    String status,
    String technicianId, {
    String notes = '',
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
          }),
        ),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error updating work progress: $e');
      throw Exception('Failed to update work progress: $e');
    }
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
    String period = 'month',
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
