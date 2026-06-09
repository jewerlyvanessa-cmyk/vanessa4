import 'package:flutter_test/flutter_test.dart';
import 'package:vanessa3/services/offline_sync_service.dart';

void main() {
  group('OfflineSyncService policy', () {
    test('4xx is permanent client error (drop from queue)', () {
      expect(OfflineSyncService.isPermanentClientError(400), isTrue);
      expect(OfflineSyncService.isPermanentClientError(404), isTrue);
      expect(OfflineSyncService.isPermanentClientError(422), isTrue);
      expect(OfflineSyncService.isPermanentClientError(399), isFalse);
      expect(OfflineSyncService.isPermanentClientError(500), isFalse);
    });

    test('5xx should retry', () {
      expect(OfflineSyncService.shouldRetryServerError(500), isTrue);
      expect(OfflineSyncService.shouldRetryServerError(503), isTrue);
      expect(OfflineSyncService.shouldRetryServerError(499), isFalse);
      expect(OfflineSyncService.shouldRetryServerError(400), isFalse);
    });
  });
}
