import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/providers/user_state_provider.dart';

/// Order `done_workshop` di cabang workshop — menunggu aksi Kirim ke Toko.
final workshopReturnPendingCountProvider =
    StateNotifierProvider<WorkshopReturnPendingCountNotifier, int>((ref) {
  return WorkshopReturnPendingCountNotifier(ref);
});

class WorkshopReturnPendingCountNotifier extends StateNotifier<int> {
  WorkshopReturnPendingCountNotifier(this._ref) : super(0) {
    refresh();
  }

  final Ref _ref;

  Future<void> refresh() async {
    final user = _ref.read(userStateProvider);
    final branch = user.branch.trim();
    if (branch.isEmpty) {
      state = 0;
      return;
    }
    try {
      final res = await ApiClient.get(
        '/workshop-orders',
        query: <String, String>{
          'branch_id': branch,
          'status': 'completed',
        },
      );
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      if (data is! List) return;
      var n = 0;
      for (final e in data) {
        if (e is! Map) continue;
        final st = (e['status'] ?? '').toString().trim().toLowerCase();
        if (st == 'done_workshop') n++;
      }
      state = n;
    } catch (_) {
      // keep last count
    }
  }
}
