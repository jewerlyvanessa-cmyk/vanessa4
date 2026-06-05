import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Payload faktur / order CS yang menunggu sinkronisasi.
class OfflinePendingOrders {
  OfflinePendingOrders._();

  static const String _key = 'offline_pending_orders/v1';

  static Future<void> save({
    required String queueItemId,
    required Map<String, dynamic> fakturData,
    required Map<String, dynamic> orderPayload,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readMap(prefs);
    all[queueItemId] = {
      'fakturData': fakturData,
      'orderPayload': orderPayload,
      'savedAt': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_key, jsonEncode(all));
  }

  static Future<Map<String, dynamic>?> take(String queueItemId) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readMap(prefs);
    final entry = all.remove(queueItemId);
    if (entry == null) return null;
    await prefs.setString(_key, jsonEncode(all));
    if (entry is! Map) return null;
    return Map<String, dynamic>.from(entry);
  }

  static Future<int> count() async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readMap(prefs);
    return all.length;
  }

  static Future<Map<String, dynamic>> _readMap(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return Map<String, dynamic>.from(decoded);
  }
}
