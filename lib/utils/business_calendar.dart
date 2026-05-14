import 'package:intl/intl.dart';

/// Kalender & tanggal **bisnis WIB = GMT+7** (selaras backend `Asia/Jakarta` / `ORDER_CALENDAR_TIMEZONE`).
/// Indonesia barat tidak memakai DST — offset +7 dari UTC tetap.
abstract final class BusinessCalendar {
  static const int _offsetHours = 7;

  /// Waktu saat ini di GMT+7 (dari UTC; tidak mengikuti zona perangkat).
  static DateTime get nowWib {
    final utc = DateTime.now().toUtc();
    return utc.add(const Duration(hours: _offsetHours));
  }

  /// Tanggal kalender WIB `yyyy-MM-dd` — sama kunci yang dipakai API order/pembayaran harian.
  static String todayYmd() => DateFormat('yyyy-MM-dd').format(nowWib);

  /// Nilai awal date picker: hari kalender WIB (jam 00:00.000, tanggal saja).
  static DateTime todayWibDateOnly() {
    final n = nowWib;
    return DateTime(n.year, n.month, n.day);
  }
}
