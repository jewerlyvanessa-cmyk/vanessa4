import 'dart:async';

import 'package:flutter_riverpod/legacy.dart';
import 'package:vanessa3/services/offline_sync_events.dart';
import 'package:vanessa3/services/offline_sync_service.dart';

class OfflineQueueStats {
  const OfflineQueueStats({required this.pending, required this.stuck});

  final int pending;
  final int stuck;
}

class OfflineQueueCountNotifier extends StateNotifier<OfflineQueueStats> {
  OfflineQueueCountNotifier() : super(const OfflineQueueStats(pending: 0, stuck: 0)) {
    unawaited(refresh());
    _sub = OfflineSyncEvents.onFlushed.listen((_) => refresh());
  }

  StreamSubscription<void>? _sub;

  Future<void> refresh() async {
    final items = await OfflineSyncService.listPending();
    final stuck =
        items.where((i) => i.attempts >= OfflineSyncService.maxAttempts).length;
    state = OfflineQueueStats(pending: items.length, stuck: stuck);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final offlineQueueCountProvider =
    StateNotifierProvider<OfflineQueueCountNotifier, OfflineQueueStats>((ref) {
  return OfflineQueueCountNotifier();
});
