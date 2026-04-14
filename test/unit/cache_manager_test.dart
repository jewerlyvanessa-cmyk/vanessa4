import 'package:flutter_test/flutter_test.dart';
import 'package:vanessa3/utils/cache_manager.dart';

void main() {
  group('CacheManager', () {
    late CacheManager cacheManager;

    setUp(() {
      cacheManager = CacheManager();
    });

    test('should store and retrieve data', () {
      cacheManager.set('key', 'value');
      expect(cacheManager.get('key'), 'value');
    });

    test('should check if key exists', () {
      cacheManager.set('key', 'value');
      expect(cacheManager.contains('key'), true);
      expect(cacheManager.contains('nonexistent'), false);
    });

    test('should clear all data', () {
      cacheManager.set('key', 'value');
      cacheManager.clear();
      expect(cacheManager.contains('key'), false);
    });
  });
}
