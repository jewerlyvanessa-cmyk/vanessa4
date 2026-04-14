import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../utils/network_config.dart';

class UserApiService {
  final String baseUrl;
  UserApiService({required this.baseUrl});

  Future<List<Map<String, dynamic>>> fetchUsers() async {
    final response = await http.get(
      Uri.parse('$baseUrl/users'),
      headers: NetworkConfig.defaultHeaders,
    );
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load users');
    }
  }

  Future<List<Map<String, dynamic>>> fetchBranches() async {
    final response = await http.get(
      Uri.parse('$baseUrl/branches'),
      headers: NetworkConfig.defaultHeaders,
    );
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load branches');
    }
  }

  Future<bool> addUser(Map<String, dynamic> user) async {
    final response = await http.post(
      Uri.parse('$baseUrl/users'),
      headers: NetworkConfig.defaultHeaders,
      body: json.encode(user),
    );
    return response.statusCode == 201;
  }

  Future<bool> updateUser(String id, Map<String, dynamic> user) async {
    final response = await http.put(
      Uri.parse('$baseUrl/users/$id'),
      headers: NetworkConfig.defaultHeaders,
      body: json.encode(user),
    );
    return response.statusCode == 200;
  }

  Future<bool> deleteUser(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/users/$id'),
      headers: NetworkConfig.defaultHeaders,
    );
    return response.statusCode == 200;
  }

  Future<bool> addUserBranchRole(String userId, Map<String, dynamic> branchRole) async {
    final response = await http.post(
      Uri.parse('$baseUrl/user-branch-roles'),
      headers: NetworkConfig.defaultHeaders,
      body: json.encode({
        'user_id': userId,
        'branch_id': branchRole['branch_id'],
        'role': branchRole['role'],
        'is_primary': branchRole['is_primary'] ?? false,
      }),
    );
    return response.statusCode == 201;
  }

  Future<bool> removeUserBranchRole(String userId, String branchId, String role) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/user-branch-roles/$userId/$branchId/$role'),
      headers: NetworkConfig.defaultHeaders,
    );
    return response.statusCode == 200;
  }

  Future<List<Map<String, dynamic>>> fetchUserBranchRoles(String userId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/user-branch-roles/$userId'),
      headers: NetworkConfig.defaultHeaders,
    );
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load user branch roles');
    }
  }
}
