import 'dart:async';

import 'package:flutter_riverpod/legacy.dart';
import 'package:vanessa3/services/offline_sync_events.dart';
import 'package:vanessa3/services/offline_sync_service.dart';

class OfflineQueueCountNotifier extends StateNotifier<int> {
  OfflineQueueCountNotifier() : super(0) {
    unawaited(refresh());
    _sub = OfflineSyncEvents.onFlushed.listen((_) => refresh());
  }

  StreamSubscription<void>? _sub;

  Future<void> refresh() async {
    state = await OfflineSyncService.pendingCount();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final offlineQueueCountProvider =
    StateNotifierProvider<OfflineQueueCountNotifier, int>((ref) {
  return OfflineQueueCountNotifier();
});
