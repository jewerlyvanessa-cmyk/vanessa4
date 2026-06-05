import 'package:intl/intl.dart';

/// Format & parse angka untuk form Jual CS.
abstract final class JualFormUtils {
  JualFormUtils._();

  static double roundToNearest5000(double amount) {
    final modulo10000 = amount % 10000;
    if (modulo10000 == 5000) {
      return amount;
    } else if (modulo10000 < 5000) {
      return amount - modulo10000 + 5000;
    } else {
      return amount - modulo10000 + 10000;
    }
  }

  static String formatNumberWithSeparators(String value) {
    if (value.isEmpty) return value;
    final cleanValue = value
        .replaceAll(',', '')
        .replaceAll('Rp ', '')
        .replaceAll('Rp', '');
    final number = int.tryParse(cleanValue) ?? double.tryParse(cleanValue);
    if (number == null) return value;
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    return formatter.format(number);
  }

  static double parseNumberWithSeparators(String value) {
    if (value.isEmpty) return 0.0;
    final cleanValue = value
        .replaceAll(',', '')
        .replaceAll('Rp ', '')
        .replaceAll('Rp', '');
    return int.tryParse(cleanValue)?.toDouble() ??
        double.tryParse(cleanValue) ??
        0.0;
  }

  static bool isSellableStockStatus(String? raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    return s == 'ready' || s == 'available' || s == 'reserved';
  }
}
