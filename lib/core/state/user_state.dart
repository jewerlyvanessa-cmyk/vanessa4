import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:developer' as developer;
import '../../utils/network_config.dart';

class UserState {
  final int? userId;
  final String role;
  final String branch;
  final String username;
  final String authToken;
  final List<String> roles;
  final List<Map<String, dynamic>> branches;

  UserState({
    this.userId,
    this.role = '',
    this.branch = '',
    this.username = '',
    this.authToken = '',
    this.roles = const [],
    this.branches = const [],
  });

  UserState copyWith({
    int? userId,
    String? role,
    String? branch,
    String? username,
    String? authToken,
    List<String>? roles,
    List<Map<String, dynamic>>? branches,
  }) {
    return UserState(
      userId: userId ?? this.userId,
      role: role ?? this.role,
      branch: branch ?? this.branch,
      username: username ?? this.username,
      authToken: authToken ?? this.authToken,
      roles: roles ?? this.roles,
      branches: branches ?? this.branches,
    );
  }

  /// When non-null, workshop / tukang API calls must not run (avoids `null` user id on the wire).
  String? get workshopSessionBlockReason {
    if (userId == null) {
      return 'Sesi tidak valid. Silakan login ulang.';
    }
    if (branch.isEmpty) {
      return 'Cabang belum dipilih. Gunakan menu ganti cabang.';
    }
    return null;
  }
}

class UserStateNotifier extends StateNotifier<UserState> {
  static const String _userDataKey = 'user_data';
  static const String _authTokenKey = 'auth_token';
  static const String _apiBaseUrlKey = 'api_base_url';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  UserStateNotifier() : super(UserState()) {
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataJson = prefs.getString(_userDataKey);

      if (userDataJson != null) {
        // If API base URL changed (e.g. prod -> local), invalidate the stored token.
        final savedBaseUrl = prefs.getString(_apiBaseUrlKey) ?? '';
        final currentBaseUrl = NetworkConfig.baseUrl;

        final userData = Map<String, dynamic>.from(
          jsonDecode(userDataJson) as Map,
        );
        String authToken = '';
        try {
          authToken = await _secureStorage.read(key: _authTokenKey) ?? '';
        } catch (e) {
          authToken = '';
        }
        // Migrasi sekali: token lama di prefs (tidak aman) → secure storage, lalu hapus dari prefs.
        final legacy = userData['authToken'];
        if (authToken.isEmpty &&
            legacy != null &&
            legacy.toString().trim().isNotEmpty) {
          authToken = legacy.toString();
          try {
            await _secureStorage.write(key: _authTokenKey, value: authToken);
          } catch (_) {}
          userData.remove('authToken');
          await prefs.setString(_userDataKey, jsonEncode(userData));
        }

        if (savedBaseUrl.isNotEmpty && savedBaseUrl != currentBaseUrl) {
          authToken = '';
        }

        final rawUserId = userData['userId'];
        final parsedUserId = rawUserId is int
            ? rawUserId
            : int.tryParse(rawUserId?.toString() ?? '');

        state = UserState(
          userId: parsedUserId,
          username: userData['username'] ?? '',
          branch: userData['branch'] ?? '',
          role: userData['role'] ?? '',
          authToken: authToken,
          roles: List<String>.from(userData['roles'] ?? []),
          branches: List<Map<String, dynamic>>.from(userData['branches'] ?? []),
        );
        NetworkConfig.setAuthToken(authToken.isEmpty ? null : authToken);

        // Persist current baseUrl for next boot.
        await prefs.setString(_apiBaseUrlKey, currentBaseUrl);

        // If we invalidated token due to baseUrl change, make sure it is cleared from storage too.
        if (authToken.isEmpty) {
          try {
            await _secureStorage.delete(key: _authTokenKey);
          } catch (_) {}
        }
      }
    } catch (e) {
      // If loading fails, keep the default empty state
      developer.log('Error loading user data', error: e);
    }
  }

  Future<void> _saveUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // JWT hanya di FlutterSecureStorage — jangan simpan di SharedPreferences (plaintext).
      final userData = {
        'userId': state.userId,
        'username': state.username,
        'branch': state.branch,
        'role': state.role,
        'roles': state.roles,
        'branches': state.branches,
      };
      await prefs.setString(_userDataKey, jsonEncode(userData));
      await prefs.setString(_apiBaseUrlKey, NetworkConfig.baseUrl);
      if (state.authToken.isNotEmpty) {
        await _secureStorage.write(key: _authTokenKey, value: state.authToken);
      } else {
        await _secureStorage.delete(key: _authTokenKey);
      }
    } catch (e) {
      developer.log('Error saving user data', error: e);
    }
  }

  void setUsername(String username) {
    state = state.copyWith(username: username);
    _saveUserData();
  }

  void setRole(String role) {
    state = state.copyWith(role: role);
    _saveUserData();
  }

  void setBranch(String branch) {
    state = state.copyWith(branch: branch);
    _saveUserData();
  }

  void setRoles(List<String> roles) {
    state = state.copyWith(roles: roles);
    _saveUserData();
  }

  void setBranches(List<Map<String, dynamic>> branches) {
    state = state.copyWith(branches: branches);
    _saveUserData();
  }

  void setUserData({
    required int? userId,
    required String username,
    required String branch,
    required String role,
    String authToken = '',
    required List<String> roles,
    required List<Map<String, dynamic>> branches,
  }) {
    state = state.copyWith(
      userId: userId,
      username: username,
      branch: branch,
      role: role,
      authToken: authToken,
      roles: roles,
      branches: branches,
    );
    NetworkConfig.setAuthToken(authToken.isEmpty ? null : authToken);
    _saveUserData();
  }

  void logout() {
    state = UserState(); // Reset to initial empty state
    _clearUserData();
  }

  Future<void> _clearUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userDataKey);
      await prefs.remove(_apiBaseUrlKey);
      await _secureStorage.delete(key: _authTokenKey);
      NetworkConfig.setAuthToken(null);
    } catch (e) {
      developer.log('Error clearing user data', error: e);
    }
  }
}
