import 'package:flutter_test/flutter_test.dart';
import 'package:vanessa3/core/state/user_state.dart';

void main() {
  group('UserState.workshopSessionBlockReason', () {
    test('null when userId and branch are set', () {
      final s = UserState(userId: 1, branch: '2');
      expect(s.workshopSessionBlockReason, isNull);
    });

    test('blocks when userId is null', () {
      final s = UserState(userId: null, branch: '1');
      expect(s.workshopSessionBlockReason, isNotNull);
      expect(s.workshopSessionBlockReason, contains('login'));
    });

    test('blocks when branch is empty', () {
      final s = UserState(userId: 1, branch: '');
      expect(s.workshopSessionBlockReason, isNotNull);
      expect(s.workshopSessionBlockReason, contains('Cabang'));
    });
  });
}
