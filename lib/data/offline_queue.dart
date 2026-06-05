import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class OfflineQueueItem {
  final String id;
  final String type; // e.g. 'payment'
  final String method; // 'POST'
  final String path; // e.g. '/payments'
  final Map<String, dynamic> body;
  final String idempotencyKey;
  final int attempts;
  final DateTime createdAt;

  const OfflineQueueItem({
    required this.id,
    required this.type,
    required this.method,
    required this.path,
    required this.body,
    required this.idempotencyKey,
    required this.attempts,
    required this.createdAt,
  });

  OfflineQueueItem copyWith({int? attempts}) {
    return OfflineQueueItem(
      id: id,
      type: type,
      method: method,
      path: path,
      body: body,
      idempotencyKey: idempotencyKey,
      attempts: attempts ?? this.attempts,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'method': method,
        'path': path,
        'body': body,
        'idempotencyKey': idempotencyKey,
        'attempts': attempts,
        'createdAt': createdAt.toIso8601String(),
      };

  static OfflineQueueItem fromJson(Map<String, dynamic> json) {
    return OfflineQueueItem(
      id: json['id'] as String,
      type: json['type'] as String,
      method: json['method'] as String,
      path: json['path'] as String,
      body: Map<String, dynamic>.from(json['body'] as Map),
      idempotencyKey: json['idempotencyKey'] as String,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class OfflineQueue {
  OfflineQueue._();

  static final OfflineQueue instance = OfflineQueue._();
  static const String _key = 'offline_queue/v1';
  static const int maxItems = 100;
  static const Duration maxItemAge = Duration(days: 7);

  String newIdempotencyKey() {
    final r = Random.secure();
    final rand = List<int>.generate(8, (_) => r.nextInt(256));
    final hex = rand.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${DateTime.now().millisecondsSinceEpoch}-$hex';
  }

  Future<List<OfflineQueueItem>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final now = DateTime.now();
    final items = decoded
        .whereType<Map>()
        .map((m) => OfflineQueueItem.fromJson(Map<String, dynamic>.from(m)))
        .where(
          (e) => now.difference(e.createdAt) <= maxItemAge,
        )
        .toList();
    if (items.length > maxItems) {
      items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return items.sublist(items.length - maxItems);
    }
    return items;
  }

  Future<void> _save(List<OfflineQueueItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> enqueue(OfflineQueueItem item) async {
    final items = await list();
    if (items.length >= maxItems) {
      throw StateError(
        'Antrian offline penuh ($maxItems item). Sync atau kosongkan antrian.',
      );
    }
    await _save([...items, item]);
  }

  Future<void> replaceAll(List<OfflineQueueItem> items) async {
    await _save(items);
  }
}

