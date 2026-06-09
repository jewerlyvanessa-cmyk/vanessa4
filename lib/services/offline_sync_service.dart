import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/network/api_client.dart';
import '../data/offline_pending_orders.dart';
import '../data/offline_queue.dart';
import 'offline_sync_events.dart';

class OfflineSyncService {
  OfflineSyncService._();

  static bool _isSyncing = false;
  static const int maxAttempts = 10;

  /// HTTP 4xx dari server — item di-drop dari antrian (tidak di-retry).
  @visibleForTesting
  static bool isPermanentClientError(int statusCode) =>
      statusCode >= 400 && statusCode < 500;

  /// HTTP 5xx — item tetap di antrian dengan attempts+1.
  @visibleForTesting
  static bool shouldRetryServerError(int statusCode) => statusCode >= 500;

  static Future<List<OfflineQueueItem>> listPending() =>
      OfflineQueue.instance.list();

  static Future<int> pendingCount() async {
    final items = await listPending();
    return items.length;
  }

  static Future<int> stuckCount() async {
    final items = await listPending();
    return items.where((i) => i.attempts >= maxAttempts).length;
  }

  static Future<void> removeItem(String id) async {
    final items = await listPending();
    await OfflineQueue.instance.replaceAll(
      items.where((i) => i.id != id).toList(),
    );
    OfflineSyncEvents.notifyFlushed();
  }

  /// Flush antrian tulis (payments, orders).
  static Future<void> syncPending() async {
    if (_isSyncing) return;
    _isSyncing = true;
    var flushedAny = false;
    try {
      final items = await OfflineQueue.instance.list();
      if (items.isEmpty) return;

      final remaining = <OfflineQueueItem>[];
      for (final item in items) {
        if (item.attempts >= maxAttempts) {
          remaining.add(item);
          continue;
        }

        try {
          if (item.method == 'POST' &&
              (item.path == '/payments' ||
                  item.path == '/orders' ||
                  item.path == '/items/stock-opname')) {
            final response = await ApiClient.post(
              item.path,
              headers: {'X-Idempotency-Key': item.idempotencyKey},
              body: jsonEncode(item.body),
            );
            if (response.statusCode >= 200 && response.statusCode < 300) {
              flushedAny = true;
              if (item.path == '/orders') {
                await OfflinePendingOrders.take(item.id);
              }
              continue;
            }
            if (shouldRetryServerError(response.statusCode)) {
              remaining.add(item.copyWith(attempts: item.attempts + 1));
              continue;
            }
            if (isPermanentClientError(response.statusCode)) {
              debugPrint(
                'OfflineSyncService: drop ${item.path} HTTP ${response.statusCode}',
              );
              await OfflinePendingOrders.take(item.id);
              continue;
            }
            remaining.add(item.copyWith(attempts: item.attempts + 1));
            continue;
          }

          remaining.add(item);
        } catch (e) {
          remaining.add(item.copyWith(attempts: item.attempts + 1));
          debugPrint('OfflineSyncService: sync failed for ${item.path}: $e');
        }
      }

      await OfflineQueue.instance.replaceAll(remaining);
      if (flushedAny) {
        OfflineSyncEvents.notifyFlushed();
      }
    } finally {
      _isSyncing = false;
    }
  }
}
