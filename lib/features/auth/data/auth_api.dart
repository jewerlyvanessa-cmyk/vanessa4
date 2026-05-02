import 'dart:convert';

import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/core/network/api_exceptions.dart';

class AuthApi {
  const AuthApi();

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final res = await ApiClient.post(
      '/login',
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode != 200) {
      throw ApiException(
        'Login failed',
        statusCode: res.statusCode,
        cause: res.body,
      );
    }
    return ApiClient.decodeJsonObject(res);
  }
}

