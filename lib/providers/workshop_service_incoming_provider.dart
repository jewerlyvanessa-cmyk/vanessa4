import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';

/// Jumlah order service/custom menunggu persetujuan admin workshop.
final workshopServiceIncomingCountProvider =
    StateNotifierProvider<WorkshopServiceIncomingCountNotifier, int>((ref) {
  return WorkshopServiceIncomingCountNotifier(ref);
});

class WorkshopServiceIncomingCountNotifier extends StateNotifier<int> {
  WorkshopServiceIncomingCountNotifier(this._ref) : super(0) {
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
      final uri = Uri.parse(
        '${NetworkConfig.baseUrl}/api/workshop/service-incoming?branch_id=${Uri.encodeQueryComponent(branch)}',
      );
      final res = await http.get(uri, headers: NetworkConfig.defaultHeaders);
      if (res.statusCode != 200) {
        return;
      }
      final data = jsonDecode(res.body);
      if (data is List) {
        state = data.length;
      }
    } catch (_) {
      // keep last count
    }
  }
}
