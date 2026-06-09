import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vanessa3/data/offline_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('OfflineQueueItem', () {
    test('copyWith increments attempts', () {
      final item = OfflineQueueItem(
        id: 'a',
        type: 'payment',
        method: 'POST',
        path: '/payments',
        body: {'x': 1},
        idempotencyKey: 'key',
        attempts: 2,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(item.copyWith(attempts: 3).attempts, 3);
    });

    test('toJson/fromJson roundtrip', () {
      final created = DateTime(2026, 6, 1, 12, 0);
      final item = OfflineQueueItem(
        id: 'q1',
        type: 'order',
        method: 'POST',
        path: '/orders',
        body: {'order': true},
        idempotencyKey: 'idem-1',
        attempts: 0,
        createdAt: created,
      );
      final restored = OfflineQueueItem.fromJson(item.toJson());
      expect(restored.id, 'q1');
      expect(restored.path, '/orders');
      expect(restored.createdAt, created);
    });
  });

  group('OfflineQueue', () {
    test('enqueue and list', () async {
      final q = OfflineQueue.instance;
      await q.enqueue(
        OfflineQueueItem(
          id: '1',
          type: 'payment',
          method: 'POST',
          path: '/payments',
          body: {},
          idempotencyKey: 'k1',
          attempts: 0,
          createdAt: DateTime.now(),
        ),
      );
      final items = await q.list();
      expect(items.length, 1);
      expect(items.first.path, '/payments');
    });

    test('enqueue throws when queue is full', () async {
      final q = OfflineQueue.instance;
      final now = DateTime.now();
      for (var i = 0; i < OfflineQueue.maxItems; i++) {
        await q.enqueue(
          OfflineQueueItem(
            id: 'id-$i',
            type: 'payment',
            method: 'POST',
            path: '/payments',
            body: {},
            idempotencyKey: 'k-$i',
            attempts: 0,
            createdAt: now,
          ),
        );
      }
      await expectLater(
        q.enqueue(
          OfflineQueueItem(
            id: 'overflow',
            type: 'payment',
            method: 'POST',
            path: '/payments',
            body: {},
            idempotencyKey: 'k-overflow',
            attempts: 0,
            createdAt: now,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('list drops items older than maxItemAge', () async {
      final q = OfflineQueue.instance;
      final old = DateTime.now().subtract(
        OfflineQueue.maxItemAge + const Duration(days: 1),
      );
      await q.replaceAll([
        OfflineQueueItem(
          id: 'stale',
          type: 'payment',
          method: 'POST',
          path: '/payments',
          body: {},
          idempotencyKey: 'old',
          attempts: 0,
          createdAt: old,
        ),
        OfflineQueueItem(
          id: 'fresh',
          type: 'payment',
          method: 'POST',
          path: '/payments',
          body: {},
          idempotencyKey: 'new',
          attempts: 0,
          createdAt: DateTime.now(),
        ),
      ]);
      final items = await q.list();
      expect(items.length, 1);
      expect(items.first.id, 'fresh');
    });
  });
}
