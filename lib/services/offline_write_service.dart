import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/core/network/api_exceptions.dart';
import 'package:vanessa3/data/offline_queue.dart';

/// Hasil operasi tulis: online langsung atau masuk antrian offline.
class OfflineWriteOutcome {
  const OfflineWriteOutcome._({
    required this.online,
    required this.queuedOffline,
    this.response,
    this.idempotencyKey,
    this.queueItemId,
  });

  final bool online;
  final bool queuedOffline;
  final http.Response? response;
  final String? idempotencyKey;
  final String? queueItemId;

  bool get ok => online && response != null && response!.statusCode < 400;

  factory OfflineWriteOutcome.online(http.Response response, String key) {
    return OfflineWriteOutcome._(
      online: true,
      queuedOffline: false,
      response: response,
      idempotencyKey: key,
    );
  }

  factory OfflineWriteOutcome.queued(String key, String queueItemId) {
    return OfflineWriteOutcome._(
      online: false,
      queuedOffline: true,
      idempotencyKey: key,
      queueItemId: queueItemId,
    );
  }
}

class OfflineWriteService {
  OfflineWriteService._();

  /// Error jaringan / server sementara — layak diantrikan offline.
  static bool shouldQueueError(Object error) {
    if (error is TimeoutException) return true;
    if (error is SocketException) return true;
    if (error is http.ClientException) return true;
    if (error is ApiException) {
      final code = error.statusCode;
      return code != null && code >= 500;
    }
    final msg = error.toString().toLowerCase();
    return msg.contains('socket') ||
        msg.contains('timeout') ||
        msg.contains('connection') ||
        msg.contains('failed host lookup') ||
        msg.contains('network is unreachable');
  }

  static Future<OfflineWriteOutcome> postJson({
    required String path,
    required Map<String, dynamic> body,
    required String queueType,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? OfflineQueue.instance.newIdempotencyKey();
    try {
      final response = await ApiClient.post(
        path,
        headers: {'X-Idempotency-Key': key},
        body: jsonEncode(body),
      );
      if (response.statusCode >= 500) {
        throw ApiException(
          'Server error',
          statusCode: response.statusCode,
        );
      }
      return OfflineWriteOutcome.online(response, key);
    } catch (e) {
      if (!shouldQueueError(e)) rethrow;
      debugPrint('OfflineWriteService: queue $path — $e');
      final itemId = DateTime.now().microsecondsSinceEpoch.toString();
      await OfflineQueue.instance.enqueue(
        OfflineQueueItem(
          id: itemId,
          type: queueType,
          method: 'POST',
          path: path,
          body: body,
          idempotencyKey: key,
          attempts: 0,
          createdAt: DateTime.now(),
        ),
      );
      return OfflineWriteOutcome.queued(key, itemId);
    }
  }
}
