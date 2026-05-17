import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';

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
      final uri = Uri.parse('${NetworkConfig.baseUrl}/workshop-orders').replace(
        queryParameters: <String, String>{
          'branch_id': branch,
          'status': 'completed',
        },
      );
      final res = await http.get(uri, headers: NetworkConfig.defaultHeaders);
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
