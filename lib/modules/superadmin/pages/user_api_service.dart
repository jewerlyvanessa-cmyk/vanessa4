import 'dart:convert';
import '../../../core/network/api_client.dart';

class UserApiService {
  final String baseUrl;
  UserApiService({required this.baseUrl});

  Future<List<Map<String, dynamic>>> fetchUsers() async {
    final response = await ApiClient.get('/users');
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception(
        'Failed to load users (HTTP ${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<List<Map<String, dynamic>>> fetchBranches() async {
    final response = await ApiClient.get('/branches');
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception(
        'Failed to load branches (HTTP ${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<bool> addUser(Map<String, dynamic> user) async {
    final response = await ApiClient.post('/users', body: json.encode(user));
    return response.statusCode == 201;
  }

  Future<bool> updateUser(String id, Map<String, dynamic> user) async {
    final response = await ApiClient.put('/users/$id', body: json.encode(user));
    return response.statusCode == 200;
  }

  Future<bool> deleteUser(String id) async {
    final response = await ApiClient.delete('/users/$id');
    return response.statusCode == 200;
  }

  Future<bool> updateUserPassword(String id, String newPassword) async {
    final response = await ApiClient.patch(
      '/users/$id/password',
      body: json.encode({'password': newPassword}),
    );
    return response.statusCode == 200;
  }

  Future<bool> updateUserStatus(String id, String status) async {
    final response = await ApiClient.patch(
      '/users/$id/status',
      body: json.encode({'status': status}),
    );
    return response.statusCode == 200;
  }

  Future<bool> addUserBranchRole(String userId, Map<String, dynamic> branchRole) async {
    final response = await ApiClient.post(
      '/user-branch-roles',
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
    final response = await ApiClient.delete(
      '/user-branch-roles/$userId/$branchId/$role',
    );
    return response.statusCode == 200;
  }

  Future<List<Map<String, dynamic>>> fetchUserBranchRoles(String userId) async {
    final response = await ApiClient.get('/user-branch-roles/$userId');
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception(
        'Failed to load user branch roles (HTTP ${response.statusCode}): ${response.body}',
      );
    }
  }
}
