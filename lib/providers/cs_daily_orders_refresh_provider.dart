import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Counter naik setelah order CS berhasil dibuat/diubah relevan;
/// [DailyOrdersPaymentsPage] mendengarkan untuk memuat ulang `/orders/daily`.
class CsDailyOrdersListRevisionNotifier extends StateNotifier<int> {
  CsDailyOrdersListRevisionNotifier() : super(0);

  void bump() => state = state + 1;
}

final csDailyOrdersListRevisionProvider =
    StateNotifierProvider<CsDailyOrdersListRevisionNotifier, int>((ref) {
  return CsDailyOrdersListRevisionNotifier();
});

void bumpCsDailyOrdersListRevision(WidgetRef ref) {
  ref.read(csDailyOrdersListRevisionProvider.notifier).bump();
}
