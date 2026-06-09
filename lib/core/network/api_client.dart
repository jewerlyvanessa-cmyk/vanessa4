import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../utils/network_config.dart';
import '../../utils/app_error_reporter.dart';
import 'api_exceptions.dart';

/// Thin wrapper around `package:http` with:
/// - baseUrl from `NetworkConfig`
/// - default headers (including Authorization when present)
/// - consistent timeout
/// - centralized 401/403 handling
class ApiClient {
  ApiClient._();

  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 1);

  static Duration get _timeout => NetworkConfig.connectionTimeout;

  static Uri _uri(String pathOrUrl, [Map<String, String>? query]) {
    final uri = Uri.parse(pathOrUrl);
    if (uri.hasScheme) {
      return query == null ? uri : uri.replace(queryParameters: query);
    }
    final base = Uri.parse(NetworkConfig.baseUrl);
    final normalizedPath = pathOrUrl.startsWith('/') ? pathOrUrl : '/$pathOrUrl';
    final merged = base.replace(path: '${base.path}$normalizedPath');
    return query == null ? merged : merged.replace(queryParameters: query);
  }

  static Future<http.Response> get(
    String pathOrUrl, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    return _send(() => http.get(_uri(pathOrUrl, query), headers: _headers(headers)));
  }

  static Future<http.Response> post(
    String pathOrUrl, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Object? body,
  }) async {
    return _send(
      () => http.post(
        _uri(pathOrUrl, query),
        headers: _headers(headers),
        body: body,
      ),
    );
  }

  static Future<http.Response> put(
    String pathOrUrl, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Object? body,
  }) async {
    return _send(
      () => http.put(
        _uri(pathOrUrl, query),
        headers: _headers(headers),
        body: body,
      ),
    );
  }

  static Future<http.Response> patch(
    String pathOrUrl, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Object? body,
  }) async {
    return _send(
      () => http.patch(
        _uri(pathOrUrl, query),
        headers: _headers(headers),
        body: body,
      ),
    );
  }

  static Future<http.Response> delete(
    String pathOrUrl, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    return _send(
      () => http.delete(
        _uri(pathOrUrl, query),
        headers: _headers(headers),
      ),
    );
  }

  /// Multipart POST — auth + timeout + 401/403 sama seperti request JSON.
  static Future<http.Response> postMultipart(
    String pathOrUrl, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Map<String, String>? fields,
    required List<http.MultipartFile> files,
  }) async {
    return _send(() async {
      final request = http.MultipartRequest('POST', _uri(pathOrUrl, query));
      if (fields != null) {
        request.fields.addAll(fields);
      }
      request.files.addAll(files);
      request.headers.addAll(_multipartHeaders(headers));
      final streamed = await request.send().timeout(_timeout);
      return http.Response.fromStream(streamed);
    });
  }

  static Map<String, String> _headers(Map<String, String>? extra) {
    return <String, String>{...NetworkConfig.defaultHeaders, ...?extra};
  }

  /// Jangan set Content-Type manual — boundary multipart di-set oleh package:http.
  static Map<String, String> _multipartHeaders(Map<String, String>? extra) {
    final merged = _headers(extra);
    merged.remove('Content-Type');
    return merged;
  }

  static String _errorMessageFromResponse(http.Response response) {
    final body = response.body.trim();
    if (body.isEmpty) return 'HTTP ${response.statusCode}';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error']?.toString().trim();
        final details = decoded['details']?.toString().trim();
        final detail = decoded['detail']?.toString().trim();
        final parts = <String>[];
        if (error != null && error.isNotEmpty) parts.add(error);
        if (details != null && details.isNotEmpty) parts.add(details);
        if (detail != null && detail.isNotEmpty) parts.add(detail);
        if (parts.isNotEmpty) {
          return '${parts.join(' - ')} (HTTP ${response.statusCode})';
        }
      }
    } catch (_) {
      // Not JSON; fall back to raw body
    }
    return '$body (HTTP ${response.statusCode})';
  }

  static bool _isRetryableNetworkError(Object e) {
    return e is TimeoutException || e is http.ClientException;
  }

  static Future<http.Response> _send(Future<http.Response> Function() request) async {
    Object? lastError;
    StackTrace? lastStack;

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      http.Response response;
      try {
        response = await request().timeout(_timeout);
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        if (attempt < _maxRetries && _isRetryableNetworkError(e)) {
          assert(() {
            debugPrint(
              'ApiClient retry ${attempt + 1}/$_maxRetries: $e',
            );
            return true;
          }());
          await Future<void>.delayed(_retryDelay * (attempt + 1));
          continue;
        }
        AppErrorReporter.report(e, stackTrace: st, context: 'ApiClient.network');
        rethrow;
      }

      if (response.statusCode == 401) {
        NetworkConfig.setAuthToken(null);
        NetworkConfig.notifyUnauthorized();
        throw UnauthorizedException(_errorMessageFromResponse(response));
      }
      if (response.statusCode == 403) {
        throw ForbiddenException(_errorMessageFromResponse(response));
      }
      return response;
    }

    AppErrorReporter.report(
      lastError ?? StateError('ApiClient retry exhausted'),
      stackTrace: lastStack,
      context: 'ApiClient.network',
    );
    throw lastError ?? StateError('ApiClient retry exhausted');
  }

  static Map<String, dynamic> decodeJsonObject(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Expected JSON object', statusCode: response.statusCode);
    }
    return decoded;
  }
}

