import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import '../../../utils/network_config.dart';

class BranchApiService {
  final String baseUrl;

  BranchApiService({required this.baseUrl});

  static List<Map<String, dynamic>> _decodeBranchList(String body) {
    final decoded = json.decode(body);
    if (decoded is List) {
      return decoded
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    if (decoded is Map && decoded['error'] != null) {
      throw Exception(decoded['error'].toString());
    }
    throw Exception('Respons cabang tidak valid (bukan daftar JSON).');
  }

  /// GET daftar cabang: coba `/branches` lalu `/api/branches` (proxy/prod sering hanya `/api`).
  Future<List<Map<String, dynamic>>> fetchBranches() async {
    final headers = NetworkConfig.defaultHeaders;
    Object? lastError;

    for (final path in const ['/branches', '/api/branches']) {
      try {
        final response = await http.get(
          Uri.parse('$baseUrl$path'),
          headers: headers,
        );
        if (response.statusCode == 200) {
          return _decodeBranchList(response.body);
        }
        if (response.statusCode == 404) {
          lastError = 'HTTP 404 $path';
          continue;
        }
        throw Exception(
          'Gagal memuat cabang (${response.statusCode}) $path: ${response.body}',
        );
      } catch (e) {
        lastError = e;
        if (path == '/api/branches') {
          throw Exception('Error fetching branches: $e');
        }
      }
    }
    throw Exception('Error fetching branches: $lastError');
  }

  Future<Map<String, dynamic>?> fetchBranchById(String branchId) async {
    try {
      for (final prefix in const ['/branches/', '/api/branches/']) {
        final response = await http.get(
          Uri.parse('$baseUrl$prefix$branchId'),
          headers: NetworkConfig.defaultHeaders,
        );
        if (response.statusCode == 200) {
          return json.decode(response.body) as Map<String, dynamic>;
        }
        if (response.statusCode != 404) {
          throw Exception('Failed to load branch: ${response.statusCode}');
        }
      }
      return null;
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
    final response = await http.delete(
      Uri.parse('$baseUrl/branches/$branchId'),
      headers: NetworkConfig.defaultHeaders,
    );

    if (response.statusCode == 200) return true;

    // Prefer backend-provided error message when present.
    final body = response.body.trim();
    if (body.isNotEmpty) {
      try {
        final decoded = json.decode(body);
        if (decoded is Map && decoded['error'] != null) {
          throw Exception(decoded['error'].toString());
        }
      } catch (_) {
        // Not JSON; fall through to show raw body.
      }
      throw Exception(body);
    }

    throw Exception('HTTP ${response.statusCode}');
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

  /// Upload file logo cabang (field multipart: `logo`). Mengembalikan path relatif, mis. `/uploads/...`.
  Future<String> uploadBranchLogo(String branchId, XFile file) async {
    final token = NetworkConfig.authToken;
    if (token == null || token.isEmpty) {
      throw Exception('Tidak ada token autentikasi');
    }
    final uri = Uri.parse('$baseUrl/branches/$branchId/logo');
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer $token';
    final bytes = await file.readAsBytes();
    final mime = file.mimeType ?? 'image/jpeg';
    req.files.add(
      http.MultipartFile.fromBytes(
        'logo',
        bytes,
        filename: file.name.isNotEmpty ? file.name : 'logo.jpg',
        contentType: MediaType.parse(mime),
      ),
    );
    final streamed = await req.send().timeout(NetworkConfig.connectionTimeout);
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode == 200) {
      final decoded = json.decode(resp.body);
      if (decoded is Map && decoded['logo_url'] != null) {
        return decoded['logo_url'].toString();
      }
      throw Exception('Respons server tidak valid');
    }
    String msg = 'HTTP ${resp.statusCode}';
    try {
      final decoded = json.decode(resp.body);
      if (decoded is Map && decoded['error'] != null) {
        msg = decoded['error'].toString();
      }
    } catch (_) {
      if (resp.body.isNotEmpty) msg = resp.body;
    }
    throw Exception(msg);
  }

  Future<void> deleteBranchLogo(String branchId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/branches/$branchId/logo'),
      headers: {
        'Accept': 'application/json',
        if (NetworkConfig.authToken != null && NetworkConfig.authToken!.isNotEmpty)
          'Authorization': 'Bearer ${NetworkConfig.authToken}',
      },
    ).timeout(NetworkConfig.connectionTimeout);
    if (response.statusCode != 200) {
      String msg = 'HTTP ${response.statusCode}';
      try {
        final decoded = json.decode(response.body);
        if (decoded is Map && decoded['error'] != null) {
          msg = decoded['error'].toString();
        }
      } catch (_) {
        if (response.body.isNotEmpty) msg = response.body;
      }
      throw Exception(msg);
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
