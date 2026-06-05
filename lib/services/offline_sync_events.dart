import 'dart:async';

/// Event setelah antrian offline berhasil disinkronkan (minimal satu item).
class OfflineSyncEvents {
  OfflineSyncEvents._();

  static final _controller = StreamController<void>.broadcast();

  static Stream<void> get onFlushed => _controller.stream;

  static void notifyFlushed() {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }
}
