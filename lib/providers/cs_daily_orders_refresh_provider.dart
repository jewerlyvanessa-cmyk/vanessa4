import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Counter naik setelah order berhasil dibuat/diubah;
/// [DailyOrdersPaymentsPage] & dashboard order-today mendengarkan untuk reload.
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

/// Alias — dipanggil setelah order baru agar Order Today / Order & Payments refresh.
void bumpDailyOrdersListRevision(WidgetRef ref) =>
    bumpCsDailyOrdersListRevision(ref);
