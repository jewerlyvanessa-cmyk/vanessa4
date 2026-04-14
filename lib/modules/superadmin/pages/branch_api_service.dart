import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../utils/network_config.dart';

class BranchApiService {
  final String baseUrl;

  BranchApiService({required this.baseUrl});

  Future<List<Map<String, dynamic>>> fetchBranches() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/branches'),
        headers: NetworkConfig.defaultHeaders,
      );
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to load branches: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching branches: $e');
    }
  }

  Future<Map<String, dynamic>?> fetchBranchById(String branchId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/branches/$branchId'),
        headers: NetworkConfig.defaultHeaders,
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to load branch: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching branch: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchBranchUsers(String branchId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/branches/$branchId/users'),
        headers: NetworkConfig.defaultHeaders,
      );
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to load branch users: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching branch users: $e');
    }
  }

  Future<Map<String, dynamic>> fetchBranchStatistics(String branchId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/branches/$branchId/statistics'),
        headers: NetworkConfig.defaultHeaders,
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load branch statistics: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching branch statistics: $e');
    }
  }

  Future<bool> createBranch(Map<String, dynamic> branch) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/branches'),
        headers: NetworkConfig.defaultHeaders,
        body: json.encode(branch),
      );
      return response.statusCode == 201;
    } catch (e) {
      throw Exception('Error creating branch: $e');
    }
  }

  Future<bool> updateBranch(String branchId, Map<String, dynamic> branch) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/branches/$branchId'),
        headers: NetworkConfig.defaultHeaders,
        body: json.encode(branch),
      );
      return response.statusCode == 200;
    } catch (e) {
      throw Exception('Error updating branch: $e');
    }
  }

  Future<bool> updateBranchStatus(String branchId, String status) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/branches/$branchId/status'),
        headers: NetworkConfig.defaultHeaders,
        body: json.encode({'status': status}),
      );
      return response.statusCode == 200;
    } catch (e) {
      throw Exception('Error updating branch status: $e');
    }
  }

  Future<bool> deleteBranch(String branchId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/branches/$branchId'),
        headers: NetworkConfig.defaultHeaders,
      );
      return response.statusCode == 200;
    } catch (e) {
      throw Exception('Error deleting branch: $e');
    }
  }

  Future<List<Map<String, dynamic>>> searchBranches(String query, {String? status}) async {
    try {
      final queryParams = <String, String>{};
      if (query.isNotEmpty) queryParams['search'] = query;
      if (status != null) queryParams['status'] = status;

      final uri = Uri.parse('$baseUrl/branches').replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: NetworkConfig.defaultHeaders);

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to search branches: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error searching branches: $e');
    }
  }

  Future<String> exportBranches({String format = 'csv'}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/branches/export?format=$format'),
        headers: NetworkConfig.defaultHeaders,
      );
      if (response.statusCode == 200) {
        return response.body;
      } else {
        throw Exception('Failed to export branches: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error exporting branches: $e');
    }
  }

  Future<bool?> validateBranchCode(String code, {String? excludeBranchId}) async {
    try {
      final queryParams = <String, String>{'code': code};
      if (excludeBranchId != null) queryParams['exclude'] = excludeBranchId;

      final uri = Uri.parse('$baseUrl/branches/validation/code').replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: NetworkConfig.defaultHeaders);

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        return result['valid'] ?? false;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }
}
