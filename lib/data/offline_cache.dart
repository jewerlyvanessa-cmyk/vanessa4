import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class OfflineCacheEntry<T> {
  final T value;
  final DateTime updatedAt;
  final Duration ttl;

  const OfflineCacheEntry({
    required this.value,
    required this.updatedAt,
    required this.ttl,
  });

  bool get isExpired => DateTime.now().isAfter(updatedAt.add(ttl));
}

/// Lightweight JSON cache backed by SharedPreferences.
///
/// This is intentionally simple (key-value + timestamp + TTL) to support
/// "read cache when offline, refresh when online" without adding heavy deps.
class OfflineCache {
  OfflineCache._();

  static final OfflineCache instance = OfflineCache._();

  static const String _ns = 'offline_cache/';

  Future<void> setJson(
    String key,
    Object jsonValue, {
    Duration ttl = const Duration(minutes: 10),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final payload = jsonEncode({
      'updatedAtMs': nowMs,
      'ttlSeconds': ttl.inSeconds,
      'value': jsonValue,
    });
    await prefs.setString('$_ns$key', payload);
  }

  Future<OfflineCacheEntry<T>?> getJson<T>(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_ns$key');
    if (raw == null || raw.isEmpty) return null;

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;

    final updatedAtMs = decoded['updatedAtMs'];
    final ttlSeconds = decoded['ttlSeconds'];
    final value = decoded['value'];

    if (updatedAtMs is! int || ttlSeconds is! int) return null;

    return OfflineCacheEntry<T>(
      value: value as T,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
      ttl: Duration(seconds: ttlSeconds),
    );
  }

  Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_ns$key');
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_ns)).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}

