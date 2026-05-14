import 'package:flutter_riverpod/legacy.dart';

import '../core/state/user_state.dart' as core_state;

final userStateProvider =
    StateNotifierProvider<core_state.UserStateNotifier, core_state.UserState>((
  ref,
) {
  return core_state.UserStateNotifier();
});
