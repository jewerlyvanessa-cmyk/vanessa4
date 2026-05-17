import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/cs_daily_orders_refresh_provider.dart';
import 'package:vanessa3/modules/cs/pages/faktur_page.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/business_calendar.dart';
import 'package:vanessa3/utils/order_status_ui.dart';
import 'package:vanessa3/core/state/user_state.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/utils/daily_orders_payments_report_print.dart';
import 'package:vanessa3/modules/stockist/widgets/stock_inventory_grouped_table.dart'
    show stockBranchDisplayName;

/// Filter daftar order (ringkasan di strip atas).
enum _AdminOrderFilter {
  all,
  toko,
  online,
  completed,
  pending,
  /// Order service + custom (satu pintu, beda kolom tipe).
  serviceCustom,
  /// Hanya yang perlu aksi admin toko: pending/confirmed → workshop.
  kirimWorkshop,
}

class DailyOrdersPaymentsPage extends ConsumerStatefulWidget {
  const DailyOrdersPaymentsPage({
    super.key,
    this.serviceCustomMode = false,
    this.embedInParent = false,
    this.ordersOnly = false,
  });

  /// Dari menu khusus admin toko: daftar difilter service/custom, aksi kirim ke workshop tetap sama.
  final bool serviceCustomMode;

  /// Tanpa [Scaffold]/[AppBar] — untuk disematkan di halaman induk (dashboard CS).
  /// Di mode ini strip ringkasan (chip tanggal/order) dan bar judul kalender/refresh disembunyikan.
  final bool embedInParent;

  /// Hanya tab/isi order (tanpa pembayaran). Dipakai peran CS.
  final bool ordersOnly;

  @override
  ConsumerState<DailyOrdersPaymentsPage> createState() =>
      _DailyOrdersPaymentsPageState();
}

class _DailyOrdersPaymentsPageState
    extends ConsumerState<DailyOrdersPaymentsPage> {
  DateTime _selectedDate = BusinessCalendar.todayWibDateOnly();
  Map<String, dynamic> _dailyData = {};
  bool _isLoading = true;
  String _error = '';
  _AdminOrderFilter _orderFilter = _AdminOrderFilter.all;

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  /// Role CS: hanya tampilkan order yang `user_id`-nya sama dengan user login
  /// (selaras backend `dailyOrdersUserFilterFromJwt`; filter klien sebagai cadangan).
  List<dynamic> _filterOrdersForCsIfNeeded(
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

  /// CS: pembayaran hanya untuk order yang tersisa di [csOrdersList] (milik CS).
  Map<String, dynamic> _filterPaymentsForCsOrders(
    Map<String, dynamic> payments,
    List<dynamic> csOrdersList,
  ) {
    final allowed = <String>{};
    for (final e in csOrdersList) {
      if (e is! Map) continue;
      final id = Map<String, dynamic>.from(e)['order_id']?.toString() ?? '';
      if (id.isNotEmpty) allowed.add(id);
    }
    final txsRaw = payments['transactions'] as List<dynamic>? ?? [];
    final filtered = <Map<String, dynamic>>[];
    for (final e in txsRaw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final oid = m['order_id']?.toString() ?? '';
      if (allowed.contains(oid)) filtered.add(m);
    }
    final methodAmount = <String, double>{};
    final methodCounts = <String, int>{};
    for (final m in filtered) {
      final meth = (m['method'] ?? 'unknown').toString();
      final amt = _toNum(m['amount']).toDouble();
      methodAmount[meth] = (methodAmount[meth] ?? 0) + amt;
      methodCounts[meth] = (methodCounts[meth] ?? 0) + 1;
    }
    final totalAmt = filtered.fold<num>(0, (a, m) => a + _toNum(m['amount']));
    final out = Map<String, dynamic>.from(payments);
    out['transactions'] = filtered;
    out['summary'] = {
      'total_amount': totalAmt,
      'total_transactions': filtered.length,
      'payment_methods': {
        for (final e in methodAmount.entries) e.key: e.value,
      },
      'by_method': methodAmount.entries
          .map(
            (e) => {
              'method': e.key,
              'total_amount': e.value,
              'method_count': methodCounts[e.key] ?? 0,
            },
          )
          .toList(),
    };
    return out;
  }

  @override
  void initState() {
    super.initState();
    if (widget.serviceCustomMode) {
      // Hanya service/custom: basis tampilan = semua order tipe itu (subfilter toko/dll. di atasnya).
      _orderFilter = _AdminOrderFilter.all;
    }
    _loadDailyData();
  }

  Future<void> _loadDailyData() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      var ordersResponse = await http.get(
        Uri.parse(
          '$baseUrl/api/orders/daily?branch_id=${userState.branch}&date=$dateStr',
        ),
        headers: NetworkConfig.defaultHeaders,
      );
      if (ordersResponse.statusCode == 404) {
        ordersResponse = await http.get(
          Uri.parse(
            '$baseUrl/orders/daily?branch_id=${userState.branch}&date=$dateStr',
          ),
          headers: NetworkConfig.defaultHeaders,
        );
      }

      http.Response? paymentsResponse;
      if (!widget.ordersOnly) {
        paymentsResponse = await http.get(
          Uri.parse(
            '$baseUrl/payments/daily?date=$dateStr&branch_id=${userState.branch}',
          ),
          headers: NetworkConfig.defaultHeaders,
        );
      }

      final paymentsOk =
          widget.ordersOnly || (paymentsResponse?.statusCode == 200);

      if (ordersResponse.statusCode == 200 && paymentsOk) {
        var ordersData = jsonDecode(ordersResponse.body);
        if (ordersData is List<dynamic>) {
          ordersData = _filterOrdersForCsIfNeeded(userState, ordersData);
        }
        Map<String, dynamic> paymentsData;
        if (widget.ordersOnly) {
          paymentsData = {
            'summary': {
              'total_amount': 0,
              'total_transactions': 0,
              'payment_methods': <String, dynamic>{},
              'by_method': <Map<String, dynamic>>[],
            },
            'transactions': <dynamic>[],
          };
        } else {
          paymentsData = Map<String, dynamic>.from(
            jsonDecode(paymentsResponse!.body) as Map,
          );
          if (userState.role.trim().toLowerCase() == 'cs' &&
              userState.userId != null &&
              ordersData is List<dynamic>) {
            paymentsData = _filterPaymentsForCsOrders(
              paymentsData,
              ordersData,
            );
          }
        }

        setState(() {
          _dailyData = {'orders': ordersData, 'payments': paymentsData};
          // Reset subfilter ke "semua" (di halaman Service/Custom = semua order service/custom).
          _orderFilter = _AdminOrderFilter.all;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Gagal memuat data harian';
          _isLoading = false;
        });
      }
    } catch (error) {
      setState(() {
        _error = 'Error: $error';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: BusinessCalendar.todayWibDateOnly(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadDailyData();
    }
  }

  /// API order harian bisa mengembalikan beberapa baris per `order_id` (join item).
  List<Map<String, dynamic>> _dedupeOrdersById(List<dynamic> raw) {
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

  String _fmtMoney(num n) => NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  ).format(n);

  /// Total tagihan order (selaras kolom tabel: `jumlah` / `total`).
  num _orderAmount(Map<String, dynamic> o) => _toNum(o['jumlah'] ?? o['total']);

  num _sumOrderAmountWhere(
    Iterable<Map<String, dynamic>> orders,
    bool Function(Map<String, dynamic> o) test,
  ) {
    var sum = 0.0;
    for (final o in orders) {
      if (test(o)) sum += _orderAmount(o).toDouble();
    }
    return sum;
  }

  /// Nota / nomor order untuk tampilan (bukan `order_id` internal).
  String _displayOrderNumber(Map<String, dynamic> row) {
    final n = row['order_number']?.toString().trim();
    if (n != null && n.isNotEmpty) return n;
    final legacy = row['nota_order']?.toString().trim();
    if (legacy != null && legacy.isNotEmpty) return legacy;
    final id = row['order_id']?.toString().trim();
    if (id != null && id.isNotEmpty) return id;
    return '—';
  }

  List<Map<String, dynamic>> _rawOrderLineRows(List<dynamic> raw) {
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

  String _getStatusLabel(String? status) => OrderStatusUi.label(status);

  Color _getStatusColor(String? status) => OrderStatusUi.color(status);

  String _itemFieldStr(Map<String, dynamic> row, List<String> keys) {
    for (final k in keys) {
      final v = row[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return '—';
  }

  String _lineItemName(Map<String, dynamic> row) =>
      _itemFieldStr(row, const ['nama_item', 'item_name', 'name']);

  String _lineItemTotalStr(Map<String, dynamic> row) {
    final raw = row['item_total'] ?? row['line_total'];
    if (raw == null) return '—';
    final d = double.tryParse(raw.toString());
    if (d != null && d > 0) return _fmtMoney(d);
    return '—';
  }

  bool _isServiceCustomOrder(Map<String, dynamic> row) {
    final t = (row['order_type'] ?? '').toString().trim().toLowerCase();
    return t == 'service' || t == 'custom';
  }

  bool _orderMatchesFilter(Map<String, dynamic> o) {
    if (widget.serviceCustomMode && !_isServiceCustomOrder(o)) {
      return false;
    }
    switch (_orderFilter) {
      case _AdminOrderFilter.all:
        return true;
      case _AdminOrderFilter.toko:
        final m = (o['mode'] ?? '').toString().trim().toLowerCase();
        return m != 'online';
      case _AdminOrderFilter.online:
        return (o['mode'] ?? '').toString().trim().toLowerCase() == 'online';
      case _AdminOrderFilter.completed:
        return (o['status'] ?? '').toString().trim().toLowerCase() ==
            'completed';
      case _AdminOrderFilter.pending:
        return (o['status'] ?? '').toString().trim().toLowerCase() == 'pending';
      case _AdminOrderFilter.serviceCustom:
        return _isServiceCustomOrder(o);
      case _AdminOrderFilter.kirimWorkshop:
        return _nextAdminTokoWorkshopStatus(o) == 'awaiting_warehouse';
    }
  }

  List<Map<String, dynamic>> _filterDeduped(
    List<Map<String, dynamic>> deduped,
  ) {
    if (_orderFilter == _AdminOrderFilter.all && !widget.serviceCustomMode) {
      return deduped;
    }
    return deduped.where(_orderMatchesFilter).toList();
  }

  List<dynamic> _rawOrdersForTable(List<dynamic> ordersRaw) {
    if (_orderFilter == _AdminOrderFilter.all && !widget.serviceCustomMode) {
      return ordersRaw;
    }
    final deduped = _dedupeOrdersById(ordersRaw);
    final allowed = _filterDeduped(deduped)
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

  void _setOrderFilter(_AdminOrderFilter f) {
    setState(() {
      _orderFilter = f;
    });
  }

  String _orderFilterLabel() {
    switch (_orderFilter) {
      case _AdminOrderFilter.all:
        return widget.serviceCustomMode ? 'Semua service/custom' : 'Semua order';
      case _AdminOrderFilter.toko:
        return 'Mode toko';
      case _AdminOrderFilter.online:
        return 'Mode online';
      case _AdminOrderFilter.completed:
        return 'Status selesai';
      case _AdminOrderFilter.pending:
        return 'Status pending';
      case _AdminOrderFilter.serviceCustom:
        return 'Service / custom';
      case _AdminOrderFilter.kirimWorkshop:
        return 'Kirim workshop';
    }
  }

  String _reportTitle() {
    if (widget.serviceCustomMode) return 'Service / Custom';
    if (widget.ordersOnly) return 'Order';
    return 'Order & Pembayaran';
  }

  Future<void> _printReport() async {
    if (_isLoading || _error.isNotEmpty) return;

    final ordersRaw = _dailyData['orders'] as List<dynamic>? ?? [];
    if (ordersRaw.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada data untuk dicetak')),
      );
      return;
    }

    final user = ref.read(userStateProvider);
    final branchId = user.branch.trim();
    final branchLabel = stockBranchDisplayName(
          branches: user.branches,
          branchId: branchId,
        ) ??
        branchId;

    final tableRaw = _rawOrdersForTable(ordersRaw);
    final orderRowsAreLineItems = kIsWeb;
    final List<Map<String, dynamic>> orderRows;
    if (orderRowsAreLineItems) {
      orderRows = _rawOrderLineRows(tableRaw);
    } else {
      orderRows = _filterDeduped(_dedupeOrdersById(tableRaw));
    }

    final dedupedForSummary = widget.serviceCustomMode
        ? _dedupeOrdersById(ordersRaw).where(_isServiceCustomOrder).toList()
        : _filterDeduped(_dedupeOrdersById(ordersRaw));
    final modeCounts = _orderModeCounts(dedupedForSummary);
    final completed = dedupedForSummary
        .where(
          (o) =>
              (o['status'] ?? '').toString().trim().toLowerCase() ==
              'completed',
        )
        .length;
    final pending = dedupedForSummary
        .where(
          (o) =>
              (o['status'] ?? '').toString().trim().toLowerCase() == 'pending',
        )
        .length;

    num payTotal = 0;
    var payTrx = 0;
    if (!widget.ordersOnly) {
      final payTxs = _paymentsTransactionsForView();
      payTrx = payTxs.length;
      payTotal = payTxs.fold<num>(0, (a, p) => a + _toNum(p['amount']));
    }

    final userLabel = user.role.trim().toLowerCase() == 'cs'
        ? 'CS: ${user.username.isNotEmpty ? user.username : user.userId}'
        : null;

    await printDailyOrdersPaymentsReportPdf(
      context,
      reportDate: _selectedDate,
      branchLabel: branchLabel.isEmpty ? 'Cabang' : branchLabel,
      branchIdForLogo: branchId,
      reportTitle: _reportTitle(),
      filterDescription: _orderFilterLabel(),
      userLabel: userLabel,
      ordersOnly: widget.ordersOnly,
      totalOrders: dedupedForSummary.length,
      completedOrders: completed,
      pendingOrders: pending,
      tokoCount: modeCounts.toko,
      onlineCount: modeCounts.online,
      paymentTotal: payTotal,
      paymentTrxCount: payTrx,
      orderRows: orderRows,
      orderRowsAreLineItems: orderRowsAreLineItems,
      paymentRows:
          widget.ordersOnly ? null : _paymentsTransactionsForView(),
    );
  }

  Set<String> _serviceCustomOrderIdSet() {
    final ordersRaw = _dailyData['orders'] as List<dynamic>? ?? [];
    return _dedupeOrdersById(ordersRaw)
        .where(_isServiceCustomOrder)
        .map((o) => o['order_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  /// Satu baris per order (nama item sudah digabung) — dipakai melengkapi baris pembayaran.
  Map<String, Map<String, dynamic>> _orderByIdDeduped() {
    final ordersRaw = _dailyData['orders'] as List<dynamic>? ?? [];
    final out = <String, Map<String, dynamic>>{};
    for (final o in _dedupeOrdersById(ordersRaw)) {
      final id = o['order_id']?.toString() ?? '';
      if (id.isEmpty) continue;
      out[id] = o;
    }
    return out;
  }

  Widget _statusCellWithOptionalWorkshop(Map<String, dynamic> row) {
    final statusStr = row['status']?.toString();
    final nextStatus = _nextAdminTokoWorkshopStatus(row);
    final statusWidget = Text(
      _getStatusLabel(statusStr),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: _getStatusColor(statusStr),
        fontWeight: FontWeight.w600,
        fontSize: 12,
        height: 1.2,
      ),
    );
    if (nextStatus == null) return statusWidget;
    final IconData icon;
    switch (nextStatus) {
      case 'awaiting_warehouse':
        icon = Icons.local_shipping_outlined;
        break;
      case 'ready_for_pickup':
        icon = Icons.inventory_2_outlined;
        break;
      default:
        icon = Icons.more_horiz;
    }
    return Row(
      children: [
        Expanded(child: statusWidget),
        IconButton(
          icon: Icon(icon, size: 18),
          tooltip: _adminTokoActionLabel(nextStatus),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => _updateWorkshopStatusAdminToko(row, nextStatus),
        ),
      ],
    );
  }

  /// Tab pembayaran + nominal di strip: di halaman Service/Custom hanya order tipe itu.
  List<Map<String, dynamic>> _paymentsTransactionsForView() {
    final payments = _dailyData['payments'] as Map<String, dynamic>? ?? {};
    final transactions =
        payments['transactions'] as List<dynamic>? ?? <dynamic>[];
    if (!widget.serviceCustomMode) {
      return transactions
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    final ids = _serviceCustomOrderIdSet();
    final out = <Map<String, dynamic>>[];
    for (final e in transactions) {
      if (e is! Map) continue;
      final p = Map<String, dynamic>.from(e);
      final oid = p['order_id']?.toString() ?? '';
      if (ids.contains(oid)) out.add(p);
    }
    return out;
  }

  int _countItemLineRowsForOrderIds(
    List<dynamic> ordersRaw,
    Set<String> orderIds,
  ) {
    if (orderIds.isEmpty) return 0;
    return _rawOrderLineRows(ordersRaw)
        .where((row) => orderIds.contains(row['order_id']?.toString() ?? ''))
        .length;
  }

  /// Selaras backend `/api/dashboard/order-today`: online jika `mode` = online, selain itu toko.
  ({int toko, int online}) _orderModeCounts(List<Map<String, dynamic>> dedupedOrders) {
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

  String? _nextAdminTokoWorkshopStatus(Map<String, dynamic> row) {
    if (!_isServiceCustomOrder(row)) return null;
    final status = (row['status'] ?? '').toString().trim().toLowerCase();
    if (status == 'pending' || status == 'confirmed') return 'awaiting_warehouse';
    if (status == 'done_workshop') return 'ready_for_pickup';
    return null;
  }

  String _adminTokoActionLabel(String nextStatus) {
    switch (nextStatus) {
      case 'awaiting_warehouse':
        return 'Kirim ke workshop';
      case 'ready_for_pickup':
        return 'Terima';
      default:
        return 'Proses';
    }
  }

  Future<Map<String, dynamic>> _fetchFullOrderForFaktur(
    Map<String, dynamic> order,
  ) async {
    final baseUrl = NetworkConfig.baseUrl;
    final orderNumber = (order['order_number'] ?? order['nota_order'] ?? '')
        .toString()
        .trim();
    final orderIdStr = (order['order_id'] ?? '').toString().trim();

    Future<Map<String, dynamic>?> tryGet(Uri uri) async {
      final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
      if (resp.statusCode != 200) return null;
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    }

    if (orderNumber.isNotEmpty) {
      final byNota = await tryGet(
        Uri.parse('$baseUrl/orders').replace(
          queryParameters: {'order_number': orderNumber},
        ),
      );
      if (byNota != null) return byNota;
    }
    if (orderIdStr.isNotEmpty) {
      final byId = await tryGet(
        Uri.parse('$baseUrl/orders').replace(
          queryParameters: {'order_id': orderIdStr},
        ),
      );
      if (byId != null) return byId;
    }
    return Map<String, dynamic>.from(order);
  }

  Future<void> _openFaktur(
    BuildContext context,
    Map<String, dynamic> order,
  ) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final data = await _fetchFullOrderForFaktur(order);
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!context.mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (context) => FakturPage(orderData: data),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat faktur: $e')),
        );
      }
    }
  }

  void _openOrderDetail(BuildContext context, Map<String, dynamic> order) {
    _openFaktur(context, order);
  }

  Future<void> _updateWorkshopStatusAdminToko(
    Map<String, dynamic> row,
    String nextStatus,
  ) async {
    try {
      final userState = ref.read(userStateProvider);
      final branchId = int.tryParse(userState.branch);
      final orderId = int.tryParse((row['order_id'] ?? '').toString());
      if (branchId == null || orderId == null) return;
      final baseUrl = NetworkConfig.baseUrl;
      final response = await http.put(
        Uri.parse('$baseUrl/workshop-orders/$orderId/status'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({'branch_id': branchId, 'status': nextStatus}),
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Order #$orderId -> $nextStatus')),
          );
        }
        await _loadDailyData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal update status: ${response.body}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error update status: $e')));
      }
    }
  }

  Widget _compactSummaryStrip(BuildContext context) {
    final ordersRaw = _dailyData['orders'] as List<dynamic>? ?? [];
    final dedupedAll = _dedupeOrdersById(ordersRaw);
    final stripOrders = widget.serviceCustomMode
        ? dedupedAll.where(_isServiceCustomOrder).toList()
        : dedupedAll;
    final totalOrders = stripOrders.length;
    final modeCounts = _orderModeCounts(stripOrders);
    final completed = stripOrders
        .where(
          (o) =>
              (o['status'] ?? '').toString().trim().toLowerCase() ==
              'completed',
        )
        .length;
    final pending = stripOrders
        .where(
          (o) =>
              (o['status'] ?? '').toString().trim().toLowerCase() == 'pending',
        )
        .length;
    final completedAmount = widget.ordersOnly
        ? _sumOrderAmountWhere(
            stripOrders,
            (o) =>
                (o['status'] ?? '').toString().trim().toLowerCase() ==
                'completed',
          )
        : 0;
    final pendingAmount = widget.ordersOnly
        ? _sumOrderAmountWhere(
            stripOrders,
            (o) =>
                (o['status'] ?? '').toString().trim().toLowerCase() ==
                'pending',
          )
        : 0;
    final svcCustom = dedupedAll.where(_isServiceCustomOrder).length;
    final kirimWorkshopCount = dedupedAll
        .where((o) => _nextAdminTokoWorkshopStatus(o) == 'awaiting_warehouse')
        .length;

    final stripIds = stripOrders
        .map((o) => o['order_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final lineCount = _countItemLineRowsForOrderIds(ordersRaw, stripIds);

    num payTotal = 0;
    int payTrx = 0;
    if (!widget.ordersOnly) {
      final payments = _dailyData['payments'] as Map<String, dynamic>? ?? {};
      final summary = payments['summary'] as Map<String, dynamic>? ?? {};
      final payTxs = _paymentsTransactionsForView();
      payTotal = widget.serviceCustomMode
          ? payTxs.fold<num>(0, (a, p) => a + _toNum(p['amount']))
          : _toNum(summary['total_amount']);
      payTrx = widget.serviceCustomMode
          ? payTxs.length
          : _toNum(summary['total_transactions']).toInt();
    }

    final cs = Theme.of(context).colorScheme;
    final showModeChips = widget.serviceCustomMode || totalOrders > 0;
    final orderChipSelected = widget.serviceCustomMode
        ? (_orderFilter == _AdminOrderFilter.all ||
            _orderFilter == _AdminOrderFilter.serviceCustom)
        : _orderFilter == _AdminOrderFilter.all;

    final rowChildren = <Widget>[
      Text(
        DateFormat('dd MMM yyyy', 'id_ID').format(_selectedDate),
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      _summaryFilterChip(
        context,
        label: 'Order $totalOrders',
        icon: Icons.receipt_long_outlined,
        selected: orderChipSelected,
        onSelected: (_) {
          _setOrderFilter(_AdminOrderFilter.all);
        },
      ),
      if (showModeChips) ...[
        _summaryFilterChip(
          context,
          label: 'Toko ${modeCounts.toko}',
          icon: Icons.storefront_outlined,
          selected: _orderFilter == _AdminOrderFilter.toko,
          onSelected: (sel) => _setOrderFilter(
            sel ? _AdminOrderFilter.toko : _AdminOrderFilter.all,
          ),
        ),
        _summaryFilterChip(
          context,
          label: 'Online ${modeCounts.online}',
          icon: Icons.language_outlined,
          selected: _orderFilter == _AdminOrderFilter.online,
          onSelected: (sel) => _setOrderFilter(
            sel ? _AdminOrderFilter.online : _AdminOrderFilter.all,
          ),
        ),
      ],
      if (kIsWeb || widget.serviceCustomMode)
        _miniChip(
          context,
          '$lineCount baris item',
          Icons.view_list_outlined,
        ),
      _summaryFilterChip(
        context,
        label: widget.ordersOnly
            ? 'Selesai $completed · ${_fmtMoney(completedAmount)}'
            : 'Selesai $completed',
        icon: Icons.check_circle_outline,
        selected: _orderFilter == _AdminOrderFilter.completed,
        onSelected: (sel) => _setOrderFilter(
          sel ? _AdminOrderFilter.completed : _AdminOrderFilter.all,
        ),
        iconColor: Colors.green.shade700,
      ),
      _summaryFilterChip(
        context,
        label: widget.ordersOnly
            ? 'Pending $pending · ${_fmtMoney(pendingAmount)}'
            : 'Pending $pending',
        icon: Icons.hourglass_top_outlined,
        selected: _orderFilter == _AdminOrderFilter.pending,
        onSelected: (sel) => _setOrderFilter(
          sel ? _AdminOrderFilter.pending : _AdminOrderFilter.all,
        ),
        iconColor: Colors.orange.shade800,
      ),
      if (!widget.serviceCustomMode && svcCustom > 0)
        _summaryFilterChip(
          context,
          label: 'Service/Custom $svcCustom',
          icon: Icons.build_circle_outlined,
          selected: _orderFilter == _AdminOrderFilter.serviceCustom,
          onSelected: (sel) => _setOrderFilter(
            sel ? _AdminOrderFilter.serviceCustom : _AdminOrderFilter.all,
          ),
          iconColor: Colors.deepOrange.shade800,
        ),
      if (kirimWorkshopCount > 0)
        _summaryFilterChip(
          context,
          label: 'Kirim workshop $kirimWorkshopCount',
          icon: Icons.local_shipping_outlined,
          selected: _orderFilter == _AdminOrderFilter.kirimWorkshop,
          onSelected: (sel) => _setOrderFilter(
            sel ? _AdminOrderFilter.kirimWorkshop : _AdminOrderFilter.all,
          ),
          iconColor: Colors.brown.shade700,
        ),
      if (!widget.ordersOnly) ...[
        _miniChip(
          context,
          _fmtMoney(payTotal),
          Icons.payments_outlined,
          color: cs.primary,
        ),
        _miniChip(context, '$payTrx trx', Icons.swap_horiz_rounded),
      ],
    ];

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.start,
          children: rowChildren,
        ),
      ),
    );
  }

  Widget _miniChip(
    BuildContext context,
    String label,
    IconData icon, {
    Color? color,
  }) {
    return Chip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      side: BorderSide(color: Colors.grey.shade400.withValues(alpha: 0.5)),
    );
  }

  Widget _summaryFilterChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required ValueChanged<bool> onSelected,
    Color? iconColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    final accent = iconColor ?? cs.primary;
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? cs.onSecondaryContainer : accent,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? cs.onSecondaryContainer : null,
        ),
      ),
      selectedColor: cs.secondaryContainer,
      side: BorderSide(
        color: selected
            ? cs.primary.withValues(alpha: 0.65)
            : Colors.grey.shade400.withValues(alpha: 0.5),
      ),
      onSelected: onSelected,
    );
  }

  Widget _ordersTable(BuildContext context) {
    final ordersRaw = _dailyData['orders'] as List<dynamic>? ?? [];
    if (ordersRaw.isEmpty) {
      return const Center(child: Text('Tidak ada order'));
    }

    final tableRaw = _rawOrdersForTable(ordersRaw);
    if (tableRaw.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            widget.serviceCustomMode
                ? 'Tidak ada order Service atau Custom pada tanggal ini'
                : 'Tidak ada order untuk filter ini',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (kIsWeb) {
      return _ordersTableWebNarrow(context, tableRaw);
    }
    return _ordersTableDedupedMobile(context, tableRaw);
  }

  Widget _ordersTableDedupedMobile(
    BuildContext context,
    List<dynamic> ordersRaw,
  ) {
    final orders = _filterDeduped(_dedupeOrdersById(ordersRaw));
    if (orders.isEmpty) {
      return const Center(child: Text('Tidak ada order'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(Colors.grey.shade200),
                dataRowColor: WidgetStateProperty.all(const Color(0xFFFFF8EE)),
                headingRowHeight: 34,
                dataRowMinHeight: 32,
                dataRowMaxHeight: 44,
                columnSpacing: 12,
                horizontalMargin: 12,
                columns: [
                  DataColumn(
                    label: Text(
                      'No. Nota',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        height: 1.1,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Order',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        height: 1.1,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Item',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        height: 1.1,
                      ),
                    ),
                  ),
                  DataColumn(
                    numeric: true,
                    label: Text(
                      'Total',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        height: 1.1,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Status',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
                rows: orders.map((o) {
                  final no = _displayOrderNumber(o);
                  final total = _toNum(o['jumlah'] ?? o['total']);
                  void openRow() => _openOrderDetail(context, o);
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(no, style: const TextStyle(fontSize: 12, height: 1.2)),
                        onTap: openRow,
                      ),
                      DataCell(
                        Text(
                          (o['order_type'] ?? '-').toString(),
                          style: const TextStyle(fontSize: 12, height: 1.2),
                        ),
                        onTap: openRow,
                      ),
                      DataCell(
                        Text(
                          (o['nama_item'] ?? '-').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, height: 1.2),
                        ),
                        onTap: openRow,
                      ),
                      DataCell(
                        Text(
                          _fmtMoney(total),
                          style: const TextStyle(fontSize: 12, height: 1.2),
                        ),
                        onTap: openRow,
                      ),
                      DataCell(
                        _statusCellWithOptionalWorkshop(o),
                        onTap: openRow,
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _ordersTableWebNarrow(BuildContext context, List<dynamic> ordersRaw) {
    final lines = _rawOrderLineRows(ordersRaw);
    if (lines.isEmpty) {
      return const Center(child: Text('Tidak ada order'));
    }

    Widget cell(
      String text, {
      int maxLines = 2,
      TextAlign align = TextAlign.start,
      Color? color,
      FontWeight? weight,
    }) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: weight,
              fontSize: 12,
              height: 1.2,
            ),
      );
    }

    void openDetail(Map<String, dynamic> row) {
      _openOrderDetail(context, row);
    }

    final rows = <DataRow>[];
    for (final row in lines) {
      final no = _displayOrderNumber(row);
      rows.add(
        DataRow(
          onSelectChanged: (_) => openDetail(row),
          cells: [
            DataCell(cell(no, maxLines: 1)),
            DataCell(
              cell((row['order_type'] ?? '—').toString(), maxLines: 1),
            ),
            DataCell(cell(_lineItemName(row), maxLines: 1)),
            DataCell(
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: cell(
                  _lineItemTotalStr(row),
                  maxLines: 1,
                  align: TextAlign.end,
                ),
              ),
            ),
            DataCell(_statusCellWithOptionalWorkshop(row)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    Colors.grey.shade200,
                  ),
                  dataRowColor: WidgetStateProperty.all(const Color(0xFFFFF8EE)),
                  headingRowHeight: 34,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 44,
                  columnSpacing: 10,
                  horizontalMargin: 8,
                  showCheckboxColumn: false,
                  columns: [
                    DataColumn(label: dataTableColumnLabel('No. Nota')),
                    DataColumn(label: dataTableColumnLabel('Order')),
                    DataColumn(label: dataTableColumnLabel('Item')),
                    DataColumn(
                      label: dataTableColumnLabel('Total'),
                      numeric: true,
                    ),
                    DataColumn(label: dataTableColumnLabel('Status')),
                  ],
                  rows: rows,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _paymentsTable(BuildContext context) {
    final transactions = _paymentsTransactionsForView();
    if (transactions.isEmpty) {
      return Center(
        child: Text(
          widget.serviceCustomMode
              ? 'Tidak ada pembayaran untuk order Service/Custom hari ini'
              : 'Tidak ada pembayaran',
        ),
      );
    }

    final orderById = _orderByIdDeduped();

    final columns = <DataColumn>[
      DataColumn(label: dataTableColumnLabel('No. order')),
      DataColumn(label: dataTableColumnLabel('Jenis order')),
      DataColumn(label: dataTableColumnLabel('Nama item')),
      DataColumn(
        numeric: true,
        label: dataTableColumnLabel('Total', numeric: true),
      ),
      DataColumn(label: dataTableColumnLabel('Status')),
    ];

    final rows = transactions.map((p) {
      final oid = p['order_id']?.toString() ?? '';
      final order = orderById[oid];
      final no = _itemFieldStr(p, const ['order_number', 'nota_order']).trim();
      final displayPayNo = no != '—'
          ? no
          : _displayOrderNumber(order ?? const {});
      final orderType =
          (order?['order_type'] ?? p['order_type'] ?? '—').toString();
      final statusRaw = order?['status']?.toString();
      final amt = _toNum(p['amount']);
      return DataRow(
        cells: [
          DataCell(
            Text(
              displayPayNo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, height: 1.2),
            ),
          ),
          DataCell(
            Text(
              orderType,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, height: 1.2),
            ),
          ),
          DataCell(
            Text(
              (p['nama_item'] ?? '-').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, height: 1.2),
            ),
          ),
          DataCell(
            Text(
              _fmtMoney(amt),
              style: const TextStyle(fontSize: 12, height: 1.2),
            ),
          ),
          DataCell(
            Text(
              statusRaw != null && statusRaw.isNotEmpty
                  ? _getStatusLabel(statusRaw)
                  : '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _getStatusColor(statusRaw),
                fontWeight: FontWeight.w600,
                fontSize: 12,
                height: 1.2,
              ),
            ),
          ),
        ],
      );
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final minW = kIsWeb
            ? (640.0 > constraints.maxWidth ? 640.0 : constraints.maxWidth)
            : constraints.maxWidth;
        final table = DataTable(
          headingRowHeight: 34,
          dataRowMinHeight: 32,
          dataRowMaxHeight: 44,
          columnSpacing: kIsWeb ? 10 : 12,
          horizontalMargin: kIsWeb ? 8 : 16,
          headingRowColor: kIsWeb
              ? WidgetStateProperty.all(Colors.grey.shade200)
              : null,
          dataRowColor: WidgetStateProperty.all(const Color(0xFFFFF8EE)),
          showCheckboxColumn: false,
          columns: columns,
          rows: rows,
        );

        final scrolls = SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minW),
              child: table,
            ),
          ),
        );

        if (kIsWeb) {
          return Scrollbar(child: scrolls);
        }
        return scrolls;
      },
    );
  }

  Widget _buildMainBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDailyData,
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      );
    }
    if (widget.ordersOnly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.embedInParent) _compactSummaryStrip(context),
          Expanded(child: _ordersTable(context)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedInParent) _compactSummaryStrip(context),
        Expanded(
          child: TabBarView(
            children: [
              _ordersTable(context),
              _paymentsTable(context),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(csDailyOrdersListRevisionProvider, (previous, next) {
      if (previous != null && previous != next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadDailyData();
        });
      }
    });

    final ordersRaw = _dailyData['orders'] as List<dynamic>? ?? [];
    final dedupedOrders = _dedupeOrdersById(ordersRaw);
    final orderCount = dedupedOrders.length;
    final svcCustomCount = dedupedOrders.where(_isServiceCustomOrder).length;
    final payTx = _paymentsTransactionsForView().length;

    final showTabs = !widget.ordersOnly &&
        !_isLoading &&
        _error.isEmpty;

    final tabBar = !showTabs
        ? null
        : TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(
                text: widget.serviceCustomMode
                    ? 'Service/custom ($svcCustomCount)'
                    : 'Order ($orderCount)',
              ),
              Tab(text: 'Pembayaran ($payTx)'),
            ],
          );

    final tabBarEmbedded = !showTabs
        ? null
        : Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant,
              indicatorColor: Theme.of(context).colorScheme.primary,
              tabs: [
                Tab(
                  text: widget.serviceCustomMode
                      ? 'Service/custom ($svcCustomCount)'
                      : 'Order ($orderCount)',
                ),
                Tab(text: 'Pembayaran ($payTx)'),
              ],
            ),
          );

    if (widget.embedInParent) {
      final cs = Theme.of(context).colorScheme;
      final body = Material(
        color: cs.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.ordersOnly)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          'Order Today',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        _isLoading ? '…' : '$orderCount order',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ),
                    IconButton(
                      icon: _isLoading
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primary,
                              ),
                            )
                          : const Icon(Icons.refresh),
                      onPressed: _isLoading ? null : _loadDailyData,
                      tooltip: 'Muat ulang',
                    ),
                  ],
                ),
              ),
            if (!_isLoading && _error.isEmpty && !widget.ordersOnly)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.print_outlined),
                  onPressed: _printReport,
                  tooltip: 'Cetak laporan',
                ),
              ),
            ?tabBarEmbedded,
            Expanded(child: _buildMainBody(context)),
          ],
        ),
      );
      if (widget.ordersOnly) {
        return body;
      }
      return DefaultTabController(
        length: 2,
        child: body,
      );
    }

    final scaffoldBody = Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.serviceCustomMode
                  ? 'Service / Custom'
                  : widget.ordersOnly
                      ? 'Order'
                      : 'Order & Pembayaran',
            ),
            Text(
              widget.serviceCustomMode
                  ? '${DateFormat('EEEE, d MMM yyyy', 'id_ID').format(_selectedDate)} · kirim ke workshop dari toko'
                  : DateFormat('EEEE, d MMM yyyy', 'id_ID').format(
                      _selectedDate,
                    ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            onPressed: _printReport,
            tooltip: 'Cetak laporan',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () => _selectDate(context),
            tooltip: 'Pilih tanggal',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDailyData,
            tooltip: 'Refresh',
          ),
        ],
        bottom: tabBar,
      ),
      body: _buildMainBody(context),
    );

    if (widget.ordersOnly) {
      return scaffoldBody;
    }
    return DefaultTabController(
      length: 2,
      child: scaffoldBody,
    );
  }
}
