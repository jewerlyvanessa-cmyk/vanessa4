import 'package:vanessa3/utils/network_config.dart';

import '../data/auth_api.dart';

class AuthRepository {
  final AuthApi _api;

  const AuthRepository({AuthApi api = const AuthApi()}) : _api = api;

  /// Returns normalized login map expected by the existing UI code.
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final data = await _api.login(username: username, password: password);

      final token = (data['token'] ?? '').toString();
      if (token.isEmpty) {
        NetworkConfig.setAuthToken(null);
        return {
          'success': false,
          'error': 'Login gagal: token kosong',
          'role': '',
          'mainModule': '',
          'branch': '',
        };
      }
      NetworkConfig.setAuthToken(token);

      return {
        'success': data['success'] ?? true,
        'user_id': data['user_id'],
        'username': data['username'] ?? '',
        'role': data['role'] ?? '',
        'mainModule': data['mainModule'] ?? '',
        'branch': data['branch'] ?? '',
        'roles': data['roles'] ?? [],
        'branches': data['branches'] ?? [],
        'token': token,
      };
    } catch (e) {
      NetworkConfig.setAuthToken(null);
      return {
        'success': false,
        'error': 'Login gagal: $e',
        'role': '',
        'mainModule': '',
        'branch': '',
      };
    }
  }
}

