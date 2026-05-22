import 'package:intl/intl.dart';
import 'package:vanessa3/core/state/user_state.dart';
import 'package:vanessa3/utils/order_bill_amount.dart';
import 'package:vanessa3/utils/order_status_ui.dart';
import 'package:vanessa3/utils/payment_order_flow.dart';

/// Filter daftar order (ringkasan di strip atas).
enum AdminOrderFilter {
  all,
  toko,
  online,
  completed,
  pending,
  serviceCustom,
  kirimWorkshop,
}

num dailyOrdersToNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v;
  return num.tryParse(v.toString()) ?? 0;
}

List<dynamic> filterOrdersForCsIfNeeded(
  UserState userState,
  List<dynamic> ordersList,
) {
  if (userState.role.trim().toLowerCase() != 'cs') return ordersList;
  final uid = userState.userId;
  if (uid == null) return ordersList;
  return ordersList.where((e) {
    if (e is! Map) return false;
    final m = Map<String, dynamic>.from(e);
    final ouid = m['user_id'];
    if (ouid == null) return false;
    return int.tryParse(ouid.toString()) == uid;
  }).toList();
}

List<Map<String, dynamic>> dedupeOrdersById(List<dynamic> raw) {
  final byId = <String, Map<String, dynamic>>{};
  for (final e in raw) {
    if (e is! Map) continue;
    final row = Map<String, dynamic>.from(e);
    final id = row['order_id']?.toString();
    if (id == null || id.isEmpty) continue;
    if (!byId.containsKey(id)) {
      byId[id] = row;
    } else {
      final base = byId[id]!;
      final a = (base['nama_item'] ?? '').toString().trim();
      final b = (row['nama_item'] ?? '').toString().trim();
      if (b.isNotEmpty && !a.split(',').map((x) => x.trim()).contains(b)) {
        base['nama_item'] = a.isEmpty ? b : '$a, $b';
      }
    }
  }
  final list = byId.values.toList();
  list.sort((a, b) {
    final ta = a['created_at']?.toString() ?? '';
    final tb = b['created_at']?.toString() ?? '';
    return tb.compareTo(ta);
  });
  return list;
}

String fmtDailyOrderMoney(num n) => NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(n);

num orderAmountSigned(Map<String, dynamic> o) {
  final n = orderBillAmountFromRow(o);
  final t = (o['order_type'] ?? '').toString().trim().toLowerCase();
  return t == 'buyback' ? -n : n;
}

String displayOrderNumber(Map<String, dynamic> row) {
  final n = row['order_number']?.toString().trim();
  if (n != null && n.isNotEmpty) return n;
  final legacy = row['nota_order']?.toString().trim();
  if (legacy != null && legacy.isNotEmpty) return legacy;
  final id = row['order_id']?.toString().trim();
  if (id != null && id.isNotEmpty) return id;
  return '—';
}

List<Map<String, dynamic>> rawOrderLineRows(List<dynamic> raw) {
  final out = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is Map) out.add(Map<String, dynamic>.from(e));
  }
  out.sort((a, b) {
    final ta = a['created_at']?.toString() ?? '';
    final tb = b['created_at']?.toString() ?? '';
    return tb.compareTo(ta);
  });
  return out;
}

String orderStatusLabel(String? status) => OrderStatusUi.label(status);

String dailyOrderItemFieldStr(Map<String, dynamic> row, List<String> keys) {
  for (final k in keys) {
    final v = row[k]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return '—';
}

String lineItemName(Map<String, dynamic> row) =>
    dailyOrderItemFieldStr(row, const ['nama_item', 'item_name', 'name']);

String orderTotalDisplayStr(Map<String, dynamic> row) {
  final n = orderBillAmountFromRow(row);
  if (n > 0) return fmtDailyOrderMoney(n);
  return '—';
}

bool isServiceCustomOrder(Map<String, dynamic> row) {
  final t = (row['order_type'] ?? '').toString().trim().toLowerCase();
  return t == 'service' || t == 'custom';
}

bool isCompletedOrderStatus(String? status) {
  final s = (status ?? '').toString().trim().toLowerCase();
  return s == 'completed' || s == 'sold';
}

bool isOpenOrderStatus(String? status) {
  final s = (status ?? '').toString().trim().toLowerCase();
  if (s.isEmpty) return true;
  return s != 'completed' && s != 'sold' && s != 'cancelled';
}

bool orderMatchesAdminFilter(
  Map<String, dynamic> o, {
  required AdminOrderFilter filter,
  required bool serviceCustomMode,
}) {
  if (serviceCustomMode && !isServiceCustomOrder(o)) return false;
  switch (filter) {
    case AdminOrderFilter.all:
      return true;
    case AdminOrderFilter.toko:
      final m = (o['mode'] ?? '').toString().trim().toLowerCase();
      return m != 'online';
    case AdminOrderFilter.online:
      return (o['mode'] ?? '').toString().trim().toLowerCase() == 'online';
    case AdminOrderFilter.completed:
      return isCompletedOrderStatus(o['status']?.toString());
    case AdminOrderFilter.pending:
      return isOpenOrderStatus(o['status']?.toString());
    case AdminOrderFilter.serviceCustom:
      return isServiceCustomOrder(o);
    case AdminOrderFilter.kirimWorkshop:
      return nextAdminTokoWorkshopStatus(o) == 'awaiting_warehouse';
  }
}

List<Map<String, dynamic>> filterDedupedOrders(
  List<Map<String, dynamic>> deduped, {
  required AdminOrderFilter filter,
  required bool serviceCustomMode,
}) {
  if (filter == AdminOrderFilter.all && !serviceCustomMode) return deduped;
  return deduped
      .where(
        (o) => orderMatchesAdminFilter(
          o,
          filter: filter,
          serviceCustomMode: serviceCustomMode,
        ),
      )
      .toList();
}

List<dynamic> rawOrdersForTable(
  List<dynamic> ordersRaw, {
  required AdminOrderFilter filter,
  required bool serviceCustomMode,
}) {
  if (filter == AdminOrderFilter.all && !serviceCustomMode) return ordersRaw;
  final deduped = dedupeOrdersById(ordersRaw);
  final allowed = filterDedupedOrders(
    deduped,
    filter: filter,
    serviceCustomMode: serviceCustomMode,
  )
      .map((o) => o['order_id']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .toSet();
  final out = <dynamic>[];
  for (final e in ordersRaw) {
    if (e is! Map) continue;
    final id = e['order_id']?.toString() ?? '';
    if (allowed.contains(id)) out.add(e);
  }
  return out;
}

String adminOrderFilterLabel(
  AdminOrderFilter filter, {
  required bool serviceCustomMode,
}) {
  switch (filter) {
    case AdminOrderFilter.all:
      return serviceCustomMode ? 'Semua service/custom' : 'Semua order';
    case AdminOrderFilter.toko:
      return 'Mode toko';
    case AdminOrderFilter.online:
      return 'Mode online';
    case AdminOrderFilter.completed:
      return 'Status selesai';
    case AdminOrderFilter.pending:
      return 'Status pending';
    case AdminOrderFilter.serviceCustom:
      return 'Service / custom';
    case AdminOrderFilter.kirimWorkshop:
      return 'Kirim workshop';
  }
}

({int toko, int online}) orderModeCounts(List<Map<String, dynamic>> dedupedOrders) {
  var toko = 0;
  var online = 0;
  for (final o in dedupedOrders) {
    final m = (o['mode'] ?? '').toString().trim().toLowerCase();
    if (m == 'online') {
      online++;
    } else {
      toko++;
    }
  }
  return (toko: toko, online: online);
}

String? nextAdminTokoWorkshopStatus(Map<String, dynamic> row) {
  if (!isServiceCustomOrder(row)) return null;
  final status = (row['status'] ?? '').toString().trim().toLowerCase();
  if (status == 'pending' || status == 'confirmed') return 'awaiting_warehouse';
  if (status == 'done_workshop') return 'ready_for_pickup';
  return null;
}

String adminTokoWorkshopActionLabel(String nextStatus) {
  switch (nextStatus) {
    case 'awaiting_warehouse':
      return 'Kirim ke workshop';
    case 'ready_for_pickup':
      return 'Terima';
    default:
      return 'Proses';
  }
}

Set<String> serviceCustomOrderIdSet(List<dynamic> ordersRaw) {
  return dedupeOrdersById(ordersRaw)
      .where(isServiceCustomOrder)
      .map((o) => o['order_id']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .toSet();
}

Map<String, Map<String, dynamic>> orderByIdDeduped(List<dynamic> ordersRaw) {
  final out = <String, Map<String, dynamic>>{};
  for (final o in dedupeOrdersById(ordersRaw)) {
    final id = o['order_id']?.toString() ?? '';
    if (id.isEmpty) continue;
    out[id] = o;
  }
  return out;
}

List<Map<String, dynamic>> paymentsTransactionsForView({
  required Map<String, dynamic> dailyData,
  required bool serviceCustomMode,
}) {
  final payments = dailyData['payments'] as Map<String, dynamic>? ?? {};
  final transactions =
      payments['transactions'] as List<dynamic>? ?? <dynamic>[];
  final orderById = orderByIdDeduped(dailyData['orders'] as List<dynamic>? ?? []);

  List<Map<String, dynamic>> mapTx(Iterable<dynamic> list) {
    final out = <Map<String, dynamic>>[];
    for (final e in list) {
      if (e is! Map) continue;
      final p = Map<String, dynamic>.from(e);
      final oid = p['order_id']?.toString() ?? '';
      final order = orderById[oid];
      if ((p['order_type'] ?? '').toString().trim().isEmpty && order != null) {
        p['order_type'] = order['order_type'];
      }
      out.add(p);
    }
    return out;
  }

  if (!serviceCustomMode) return mapTx(transactions);
  final ids = serviceCustomOrderIdSet(
    dailyData['orders'] as List<dynamic>? ?? [],
  );
  return mapTx(
    transactions.where((e) {
      if (e is! Map) return false;
      return ids.contains(e['order_id']?.toString() ?? '');
    }),
  );
}

({num income, num expense, num net, int count}) paymentTotalsFromDailyData({
  required Map<String, dynamic> dailyData,
  required bool serviceCustomMode,
}) {
  final payments = dailyData['payments'] as Map<String, dynamic>? ?? {};
  final summary = payments['summary'] as Map<String, dynamic>? ?? {};
  final income = dailyOrdersToNum(summary['income_amount']);
  final expense = dailyOrdersToNum(summary['expense_amount']);
  if (income > 0 || expense > 0) {
    final net = dailyOrdersToNum(summary['net_amount']);
    final trx = dailyOrdersToNum(summary['total_transactions']).toInt();
    return (
      income: income,
      expense: expense,
      net: net != 0 ? net : income - expense,
      count: trx > 0
          ? trx
          : paymentsTransactionsForView(
              dailyData: dailyData,
              serviceCustomMode: serviceCustomMode,
            ).length,
    );
  }
  return summarizePaymentTransactions(
    paymentsTransactionsForView(
      dailyData: dailyData,
      serviceCustomMode: serviceCustomMode,
    ),
  );
}

num sumOrderAmountWhere(
  Iterable<Map<String, dynamic>> orders,
  bool Function(Map<String, dynamic> o) test,
) {
  var sum = 0.0;
  for (final o in orders) {
    if (test(o)) sum += orderAmountSigned(o).toDouble();
  }
  return sum;
}

int countItemLineRowsForOrderIds(
  List<dynamic> ordersRaw,
  Set<String> orderIds,
) {
  if (orderIds.isEmpty) return 0;
  return rawOrderLineRows(ordersRaw)
      .where((row) => orderIds.contains(row['order_id']?.toString() ?? ''))
      .length;
}
