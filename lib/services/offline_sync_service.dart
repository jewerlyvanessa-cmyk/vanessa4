import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/network/api_client.dart';
import '../data/offline_queue.dart';

class OfflineSyncService {
  OfflineSyncService._();

  static bool _isSyncing = false;
  static const int _maxAttempts = 10;

  /// Best-effort flush of queued write operations.
  ///
  /// Current scope: only supports POST `/payments` items.
  static Future<void> syncPending() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final items = await OfflineQueue.instance.list();
      if (items.isEmpty) return;

      final remaining = <OfflineQueueItem>[];
      for (final item in items) {
        if (item.attempts >= _maxAttempts) {
          remaining.add(item);
          continue;
        }

        try {
          if (item.method == 'POST' && item.path == '/payments') {
            await ApiClient.post(
              item.path,
              headers: {'X-Idempotency-Key': item.idempotencyKey},
              body: jsonEncode(item.body),
            );
            continue; // success -> drop from queue
          }

          remaining.add(item);
        } catch (e) {
          remaining.add(item.copyWith(attempts: item.attempts + 1));
          debugPrint('OfflineSyncService: sync failed for ${item.path}: $e');
        }
      }

      await OfflineQueue.instance.replaceAll(remaining);
    } finally {
      _isSyncing = false;
    }
  }
}

