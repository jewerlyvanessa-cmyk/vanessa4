/// Alur kas pembayaran order: buyback = toko bayar ke pelanggan (keluar).
library;

bool paymentIsExpenseOrderType(dynamic orderType) =>
    orderType.toString().trim().toLowerCase() == 'buyback';

/// Nominal bertanda: buyback negatif (keluar), jual/service/custom positif (masuk).
num paymentSignedAmount({
  required num amount,
  dynamic orderType,
}) {
  final n = amount.abs();
  return paymentIsExpenseOrderType(orderType) ? -n : n;
}

/// Ringkasan transaksi pembayaran (amount di DB selalu positif).
({num income, num expense, num net, int count}) summarizePaymentTransactions(
  Iterable<Map<String, dynamic>> txs,
) {
  var income = 0.0;
  var expense = 0.0;
  var count = 0;
  for (final tx in txs) {
    final raw = tx['amount'];
    final amount = raw is num ? raw : num.tryParse(raw?.toString() ?? '') ?? 0;
    if (amount <= 0) continue;
    count++;
    final type = tx['order_type'] ?? tx['orderType'];
    if (paymentIsExpenseOrderType(type)) {
      expense += amount;
    } else {
      income += amount;
    }
  }
  return (income: income, expense: expense, net: income - expense, count: count);
}
