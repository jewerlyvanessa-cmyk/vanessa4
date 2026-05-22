/// Filter & ringkasan ulang untuk modul kasir (cabang aktif + user login).
/// Dipakai setelah API agar UI tetap benar jika backend/cache production belum terbarui.
library;

import 'package:vanessa3/shared_widgets/manager_report_period_selector.dart';

num _amount(dynamic raw) {
  if (raw is num) return raw;
  return num.tryParse(raw?.toString() ?? '') ?? 0;
}

/// Cocokkan ID user dari JSON (int, num, string).
bool kasirUserIdsMatch(dynamic raw, int userId) {
  if (raw == null) return false;
  if (raw is int) return raw == userId;
  if (raw is num) return raw.toInt() == userId;
  return int.tryParse(raw.toString()) == userId;
}

bool kasirPaymentBelongsToUser(Map<String, dynamic> tx, int userId) {
  return kasirUserIdsMatch(tx['validated_by'], userId);
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
  return kasirUserIdsMatch(entry['user_id'], userId);
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

/// Parse `GET /store-operational` — cadangan filter klien bila server lama.
List<Map<String, dynamic>> parseKasirOperationalListResponse(
  dynamic decoded,
  int userId, {
  bool requestedUserScope = false,
}) {
  if (decoded is! List) return [];
  final list = decoded
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  if (!requestedUserScope) return list;
  return list.where((e) {
    final uid = e['user_id'];
    if (uid == null) return true;
    return kasirOperationalBelongsToUser(e, userId);
  }).toList();
}

/// Parse `GET /payments/daily-summary` → transaksi + ringkasan selaras filter kasir.
({List<Map<String, dynamic>> transactions, Map<String, dynamic> summary})
    parseKasirPaymentsDailySummaryResponse(
  dynamic decoded,
  int userId,
) {
  if (decoded is! Map) {
    return (transactions: <Map<String, dynamic>>[], summary: <String, dynamic>{});
  }
  final root = Map<String, dynamic>.from(decoded);
  final tx = root['transactions'];
  final payments = tx is List
      ? filterKasirPaymentsForUser(tx, userId)
      : <Map<String, dynamic>>[];
  return (
    transactions: payments,
    summary: summarizeKasirPaymentTransactions(payments),
  );
}

String kasirReportPeriodSlug(DateTime start, DateTime end) {
  final a = managerReportIsoDate(start);
  final b = managerReportIsoDate(end);
  if (managerReportSameCalendarDay(start, end)) return a;
  return '${a}_$b';
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
