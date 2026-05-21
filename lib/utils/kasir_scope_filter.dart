/// Filter & ringkasan ulang untuk modul kasir (cabang aktif + user login).
/// Dipakai setelah API agar UI tetap benar jika backend/cache production belum terbarui.
library;

num _amount(dynamic raw) {
  if (raw is num) return raw;
  return num.tryParse(raw?.toString() ?? '') ?? 0;
}

bool kasirPaymentBelongsToUser(Map<String, dynamic> tx, int userId) {
  final vb = tx['validated_by'];
  if (vb == null) return false;
  return int.tryParse(vb.toString()) == userId;
}

List<Map<String, dynamic>> filterKasirPaymentsForUser(
  Iterable<dynamic> raw,
  int userId,
) {
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .where((tx) => kasirPaymentBelongsToUser(tx, userId))
      .toList();
}

bool kasirOperationalBelongsToUser(Map<String, dynamic> entry, int userId) {
  final uid = entry['user_id'];
  if (uid == null) return false;
  return int.tryParse(uid.toString()) == userId;
}

List<Map<String, dynamic>> filterKasirOperationalForUser(
  Iterable<dynamic> raw,
  int userId,
) {
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .where((e) => kasirOperationalBelongsToUser(e, userId))
      .toList();
}

/// Ringkasan selaras backend `/payments/daily-summary`.
Map<String, dynamic> summarizeKasirPaymentTransactions(
  List<Map<String, dynamic>> txs,
) {
  var income = 0.0;
  var expense = 0.0;
  var cashPayments = 0;
  var transferPayments = 0;
  var qrisPayments = 0;
  var ewalletPayments = 0;
  var cashAmount = 0.0;
  var transferAmount = 0.0;
  var qrisAmount = 0.0;
  var ewalletAmount = 0.0;

  for (final tx in txs) {
    final amount = _amount(tx['amount']).toDouble();
    final orderType =
        (tx['order_type'] ?? '').toString().trim().toLowerCase();
    final method =
        (tx['payment_method'] ?? tx['method'] ?? '').toString().trim().toLowerCase();

    if (orderType == 'buyback') {
      expense += amount;
    } else {
      income += amount;
    }

    switch (method) {
      case 'cash':
        cashPayments++;
        cashAmount += amount;
        break;
      case 'transfer':
        transferPayments++;
        transferAmount += amount;
        break;
      case 'qris':
        qrisPayments++;
        qrisAmount += amount;
        break;
      case 'e-wallet':
      case 'ewallet':
        ewalletPayments++;
        ewalletAmount += amount;
        break;
      default:
        break;
    }
  }

  return {
    'total_payments': txs.length,
    'total_amount': income + expense,
    'income_amount': income,
    'expense_amount': expense,
    'net_amount': income - expense,
    'cash_payments': cashPayments,
    'transfer_payments': transferPayments,
    'qris_payments': qrisPayments,
    'ewallet_payments': ewalletPayments,
    'cash_amount': cashAmount,
    'transfer_amount': transferAmount,
    'qris_amount': qrisAmount,
    'ewallet_amount': ewalletAmount,
  };
}
