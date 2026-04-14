import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:developer' as developer;

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
}

class UserStateNotifier extends StateNotifier<UserState> {
  static const String _userDataKey = 'user_data';

  UserStateNotifier() : super(UserState()) {
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataJson = prefs.getString(_userDataKey);

      if (userDataJson != null) {
        final userData = jsonDecode(userDataJson);
        state = UserState(
          userId: userData['userId'],
          username: userData['username'] ?? '',
          branch: userData['branch'] ?? '',
          role: userData['role'] ?? '',
          authToken: userData['authToken'] ?? '',
          roles: List<String>.from(userData['roles'] ?? []),
          branches: List<Map<String, dynamic>>.from(userData['branches'] ?? []),
        );
      }
    } catch (e) {
      // If loading fails, keep the default empty state
      developer.log('Error loading user data', error: e);
    }
  }

  Future<void> _saveUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userData = {
        'userId': state.userId,
        'username': state.username,
        'branch': state.branch,
        'role': state.role,
        'authToken': state.authToken,
        'roles': state.roles,
        'branches': state.branches,
      };
      await prefs.setString(_userDataKey, jsonEncode(userData));
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
    } catch (e) {
      developer.log('Error clearing user data', error: e);
    }
  }
}
