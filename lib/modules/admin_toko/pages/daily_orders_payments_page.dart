import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/modules/cs/pages/order_detail_page.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/order_status_ui.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

/// Filter daftar order (ringkasan di strip atas).
enum _AdminOrderFilter { all, toko, online, completed, pending }

class DailyOrdersPaymentsPage extends ConsumerStatefulWidget {
  const DailyOrdersPaymentsPage({super.key});

  @override
  ConsumerState<DailyOrdersPaymentsPage> createState() =>
      _DailyOrdersPaymentsPageState();
}

class _DailyOrdersPaymentsPageState
    extends ConsumerState<DailyOrdersPaymentsPage> {
  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic> _dailyData = {};
  bool _isLoading = true;
  String _error = '';
  _AdminOrderFilter _orderFilter = _AdminOrderFilter.all;

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  @override
  void initState() {
    super.initState();
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

      final paymentsResponse = await http.get(
        Uri.parse(
          '$baseUrl/payments/daily?date=$dateStr&branch_id=${userState.branch}',
        ),
        headers: NetworkConfig.defaultHeaders,
      );

      if (ordersResponse.statusCode == 200 &&
          paymentsResponse.statusCode == 200) {
        final ordersData = jsonDecode(ordersResponse.body);
        final paymentsData = jsonDecode(paymentsResponse.body);

        setState(() {
          _dailyData = {'orders': ordersData, 'payments': paymentsData};
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
      lastDate: DateTime.now(),
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

  String _fmtShortTime(dynamic ts) {
    if (ts == null) return '-';
    try {
      return DateFormat(
        'HH:mm',
      ).format(DateTime.parse(ts.toString()).toLocal());
    } catch (_) {
      return '-';
    }
  }

  String _fmtRpDots(dynamic v) {
    final n = double.tryParse(v?.toString() ?? '');
    if (n == null) return '0';
    final s = n.toStringAsFixed(0);
    return s.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
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

  String _lineBerat(Map<String, dynamic> row) {
    dynamic raw;
    for (final key in const ['berat', 'weight', 'item_weight']) {
      final v = row[key];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isEmpty) continue;
      raw = v;
      break;
    }
    if (raw == null) return '—';
    final b = double.tryParse(raw.toString());
    if (b == null || b <= 0) return '—';
    return '${raw.toString()} g';
  }

  String _lineItemTotalStr(Map<String, dynamic> row) {
    final raw = row['item_total'] ?? row['line_total'];
    if (raw == null) return '—';
    final d = double.tryParse(raw.toString());
    if (d != null && d > 0) return _fmtMoney(d);
    return '—';
  }

  String _lineHargaPerGram(Map<String, dynamic> row) {
    final raw = row['harga_per_gram'];
    final d = double.tryParse(raw?.toString() ?? '');
    if (d != null && d > 0) return 'Rp ${_fmtRpDots(raw)}';
    return '—';
  }

  bool _isServiceCustomOrder(Map<String, dynamic> row) {
    final t = (row['order_type'] ?? '').toString().trim().toLowerCase();
    return t == 'service' || t == 'custom';
  }

  bool _orderMatchesFilter(Map<String, dynamic> o) {
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
    }
  }

  List<Map<String, dynamic>> _filterDeduped(
    List<Map<String, dynamic>> deduped,
  ) {
    if (_orderFilter == _AdminOrderFilter.all) return deduped;
    return deduped.where(_orderMatchesFilter).toList();
  }

  List<dynamic> _rawOrdersForTable(List<dynamic> ordersRaw) {
    if (_orderFilter == _AdminOrderFilter.all) return ordersRaw;
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
        return 'Kirim Gudang';
      case 'ready_for_pickup':
        return 'Terima';
      default:
        return 'Proses';
    }
  }

  void _openOrderDetail(BuildContext context, Map<String, dynamic> order) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderDetailPage(order: order),
      ),
    );
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
    final orders = _dedupeOrdersById(ordersRaw);
    final totalOrders = orders.length;
    final modeCounts = _orderModeCounts(orders);
    final completed = orders
        .where(
          (o) =>
              (o['status'] ?? '').toString().trim().toLowerCase() == 'completed',
        )
        .length;
    final pending = orders
        .where(
          (o) => (o['status'] ?? '').toString().trim().toLowerCase() == 'pending',
        )
        .length;
    final lineCount = kIsWeb ? _rawOrderLineRows(ordersRaw).length : 0;

    final payments = _dailyData['payments'] as Map<String, dynamic>? ?? {};
    final summary = payments['summary'] as Map<String, dynamic>? ?? {};
    final payTotal = _toNum(summary['total_amount']);
    final payTrx = _toNum(summary['total_transactions']).toInt();

    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
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
              selected: _orderFilter == _AdminOrderFilter.all,
              onSelected: (_) {
                _setOrderFilter(_AdminOrderFilter.all);
              },
            ),
            if (totalOrders > 0) ...[
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
            if (kIsWeb && lineCount > 0)
              _miniChip(
                context,
                '$lineCount baris item',
                Icons.view_list_outlined,
              ),
            _summaryFilterChip(
              context,
              label: 'Selesai $completed',
              icon: Icons.check_circle_outline,
              selected: _orderFilter == _AdminOrderFilter.completed,
              onSelected: (sel) => _setOrderFilter(
                sel ? _AdminOrderFilter.completed : _AdminOrderFilter.all,
              ),
              iconColor: Colors.green.shade700,
            ),
            _summaryFilterChip(
              context,
              label: 'Pending $pending',
              icon: Icons.hourglass_top_outlined,
              selected: _orderFilter == _AdminOrderFilter.pending,
              onSelected: (sel) => _setOrderFilter(
                sel ? _AdminOrderFilter.pending : _AdminOrderFilter.all,
              ),
              iconColor: Colors.orange.shade800,
            ),
            _miniChip(
              context,
              _fmtMoney(payTotal),
              Icons.payments_outlined,
              color: cs.primary,
            ),
            _miniChip(context, '$payTrx trx', Icons.swap_horiz_rounded),
          ],
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
            'Tidak ada order untuk filter ini',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final narrow = MediaQuery.sizeOf(context).width < 600;
    final webWide = kIsWeb && !narrow;

    if (kIsWeb) {
      if (webWide) return _ordersTableWebWide(context, tableRaw);
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
                headingRowHeight: 40,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 72,
                columnSpacing: 16,
                columns: const [
                  DataColumn(
                    label: Text(
                      '#',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Waktu',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Tipe',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Status',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Pelanggan',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Item',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataColumn(
                    numeric: true,
                    label: Text(
                      'Total',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Aksi',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                rows: orders.map((o) {
                  final id = o['order_id']?.toString() ?? '-';
                  final total = _toNum(o['total'] ?? o['jumlah']);
                  final nextStatus = _nextAdminTokoWorkshopStatus(o);
                  void openRow() => _openOrderDetail(context, o);
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(id, style: const TextStyle(fontSize: 13)),
                        onTap: openRow,
                      ),
                      DataCell(
                        Text(_fmtShortTime(o['created_at'])),
                        onTap: openRow,
                      ),
                      DataCell(
                        Text((o['order_type'] ?? '-').toString()),
                        onTap: openRow,
                      ),
                      DataCell(
                        Text((o['status'] ?? '-').toString()),
                        onTap: openRow,
                      ),
                      DataCell(
                        Text(
                          (o['customer_name'] ?? '-').toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: openRow,
                      ),
                      DataCell(
                        Text(
                          (o['nama_item'] ?? '-').toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: openRow,
                      ),
                      DataCell(
                        Text(
                          _fmtMoney(total),
                          style: const TextStyle(fontSize: 13),
                        ),
                        onTap: openRow,
                      ),
                      DataCell(
                        nextStatus == null
                            ? const Text('—')
                            : OutlinedButton(
                                onPressed: () => _updateWorkshopStatusAdminToko(
                                  o,
                                  nextStatus,
                                ),
                                child: Text(_adminTokoActionLabel(nextStatus)),
                              ),
                        onTap: nextStatus == null ? openRow : null,
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
    }) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    void openDetail(Map<String, dynamic> row) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => OrderDetailPage(order: row)),
      );
    }

    final rows = <DataRow>[];
    for (final row in lines) {
      final oid = row['order_id']?.toString() ?? '—';
      final nextStatus = _nextAdminTokoWorkshopStatus(row);
      rows.add(
        DataRow(
          onSelectChanged: (_) => openDetail(row),
          cells: [
            DataCell(cell('#$oid', maxLines: 1)),
            DataCell(cell(_fmtShortTime(row['created_at']), maxLines: 1)),
            DataCell(cell(_lineItemName(row))),
            DataCell(
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: cell(_lineBerat(row), maxLines: 1, align: TextAlign.end),
              ),
            ),
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
            DataCell(
              nextStatus == null
                  ? const Text('—')
                  : OutlinedButton(
                      onPressed: () =>
                          _updateWorkshopStatusAdminToko(row, nextStatus),
                      child: Text(_adminTokoActionLabel(nextStatus)),
                    ),
            ),
            DataCell(
              IconButton(
                icon: const Icon(Icons.visibility_outlined, size: 20),
                tooltip: 'Detail',
                onPressed: () => openDetail(row),
              ),
            ),
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
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 52,
                  columnSpacing: 10,
                  horizontalMargin: 10,
                  showCheckboxColumn: false,
                  columns: [
                    DataColumn(label: dataTableColumnLabel('Order')),
                    DataColumn(label: dataTableColumnLabel('Waktu')),
                    DataColumn(label: dataTableColumnLabel('Nama item')),
                    DataColumn(
                      label: dataTableColumnLabel('Berat'),
                      numeric: true,
                    ),
                    DataColumn(
                      label: dataTableColumnLabel('Subtotal'),
                      numeric: true,
                    ),
                    DataColumn(label: dataTableColumnLabel('Aksi')),
                    const DataColumn(label: SizedBox(width: 44)),
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

  Widget _ordersTableWebWide(BuildContext context, List<dynamic> ordersRaw) {
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
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: color, fontWeight: weight),
      );
    }

    void openDetail(Map<String, dynamic> row) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => OrderDetailPage(order: row)),
      );
    }

    final columns = <DataColumn>[
      DataColumn(label: dataTableColumnLabel('Order')),
      DataColumn(label: dataTableColumnLabel('Waktu')),
      DataColumn(label: dataTableColumnLabel('Kode')),
      DataColumn(label: dataTableColumnLabel('Nama item')),
      DataColumn(label: dataTableColumnLabel('Kategori')),
      DataColumn(label: dataTableColumnLabel('Jenis')),
      DataColumn(label: dataTableColumnLabel('Tipe item')),
      DataColumn(label: dataTableColumnLabel('Material')),
      DataColumn(label: dataTableColumnLabel('Kadar')),
      DataColumn(label: dataTableColumnLabel('Berat'), numeric: true),
      DataColumn(label: dataTableColumnLabel('Qty'), numeric: true),
      DataColumn(label: dataTableColumnLabel('Harga/g'), numeric: true),
      DataColumn(label: dataTableColumnLabel('Subtotal'), numeric: true),
      DataColumn(label: dataTableColumnLabel('Pelanggan')),
      DataColumn(label: dataTableColumnLabel('Status')),
      DataColumn(label: dataTableColumnLabel('Tipe order')),
      DataColumn(label: dataTableColumnLabel('Aksi')),
      const DataColumn(label: SizedBox(width: 44)),
    ];

    final rows = <DataRow>[];
    for (final row in lines) {
      final oid = row['order_id']?.toString() ?? 'N/A';
      final cust = row['customer_name']?.toString().trim();
      final nextStatus = _nextAdminTokoWorkshopStatus(row);
      rows.add(
        DataRow(
          onSelectChanged: (_) => openDetail(row),
          cells: [
            DataCell(cell('#$oid', maxLines: 1)),
            DataCell(cell(_fmtShortTime(row['created_at']), maxLines: 1)),
            DataCell(
              cell(
                _itemFieldStr(row, const [
                  'kode_produk',
                  'item_kode',
                  'item_code',
                ]),
                maxLines: 1,
              ),
            ),
            DataCell(cell(_lineItemName(row))),
            DataCell(
              cell(
                _itemFieldStr(row, const ['kategori', 'item_kategori']),
                maxLines: 1,
              ),
            ),
            DataCell(
              cell(
                _itemFieldStr(row, const ['jenis', 'item_jenis']),
                maxLines: 1,
              ),
            ),
            DataCell(
              cell(
                _itemFieldStr(row, const ['tipe', 'item_tipe']),
                maxLines: 1,
              ),
            ),
            DataCell(
              cell(
                _itemFieldStr(row, const ['material', 'item_material']),
                maxLines: 1,
              ),
            ),
            DataCell(
              cell(
                _itemFieldStr(row, const ['purity', 'kadar', 'item_purity']),
                maxLines: 1,
              ),
            ),
            DataCell(
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: cell(_lineBerat(row), maxLines: 1, align: TextAlign.end),
              ),
            ),
            DataCell(
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: cell(
                  _itemFieldStr(row, const ['qty', 'quantity', 'item_qty']),
                  maxLines: 1,
                  align: TextAlign.end,
                ),
              ),
            ),
            DataCell(
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: cell(
                  _lineHargaPerGram(row),
                  maxLines: 1,
                  align: TextAlign.end,
                ),
              ),
            ),
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
            DataCell(cell(cust != null && cust.isNotEmpty ? cust : '—')),
            DataCell(
              cell(
                _getStatusLabel(row['status']?.toString()),
                maxLines: 1,
                color: _getStatusColor(row['status']?.toString()),
                weight: FontWeight.w600,
              ),
            ),
            DataCell(cell((row['order_type'] ?? '—').toString(), maxLines: 1)),
            DataCell(
              nextStatus == null
                  ? const Text('—')
                  : OutlinedButton(
                      onPressed: () =>
                          _updateWorkshopStatusAdminToko(row, nextStatus),
                      child: Text(_adminTokoActionLabel(nextStatus)),
                    ),
            ),
            DataCell(
              IconButton(
                icon: const Icon(Icons.visibility_outlined, size: 20),
                tooltip: 'Detail',
                onPressed: () => openDetail(row),
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const minW = 1320.0;
        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: minW > constraints.maxWidth
                      ? minW
                      : constraints.maxWidth,
                ),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    Colors.grey.shade200,
                  ),
                  dataRowMinHeight: 44,
                  dataRowMaxHeight: 64,
                  columnSpacing: 14,
                  horizontalMargin: 10,
                  showCheckboxColumn: false,
                  columns: columns,
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
    final payments = _dailyData['payments'] as Map<String, dynamic>? ?? {};
    final transactions =
        payments['transactions'] as List<dynamic>? ?? <dynamic>[];
    if (transactions.isEmpty) {
      return const Center(child: Text('Tidak ada pembayaran'));
    }

    final columns = <DataColumn>[
      DataColumn(label: dataTableColumnLabel('#Bayar')),
      DataColumn(label: dataTableColumnLabel('Order')),
      DataColumn(label: dataTableColumnLabel('Waktu')),
      DataColumn(label: dataTableColumnLabel('Metode')),
      DataColumn(label: dataTableColumnLabel('Pelanggan')),
      DataColumn(label: dataTableColumnLabel('Item')),
      DataColumn(
        numeric: true,
        label: dataTableColumnLabel('Jumlah', numeric: true),
      ),
    ];

    final rows = transactions.whereType<Map>().map((e) {
      final p = Map<String, dynamic>.from(e);
      final amt = _toNum(p['amount']);
      return DataRow(
        cells: [
          DataCell(Text((p['payment_id'] ?? '-').toString())),
          DataCell(Text((p['order_id'] ?? '-').toString())),
          DataCell(Text(_fmtShortTime(p['payment_date'] ?? p['timestamp']))),
          DataCell(Text((p['method'] ?? '-').toString())),
          DataCell(
            Text(
              (p['customer_name'] ?? '-').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          DataCell(
            Text(
              (p['nama_item'] ?? '-').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          DataCell(Text(_fmtMoney(amt))),
        ],
      );
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final minW = kIsWeb
            ? (960.0 > constraints.maxWidth ? 960.0 : constraints.maxWidth)
            : constraints.maxWidth;
        final table = DataTable(
          headingRowHeight: 40,
          dataRowMinHeight: kIsWeb ? 40 : 36,
          dataRowMaxHeight: kIsWeb ? 64 : 64,
          columnSpacing: kIsWeb ? 14 : 16,
          horizontalMargin: kIsWeb ? 10 : 24,
          headingRowColor: kIsWeb
              ? WidgetStateProperty.all(Colors.grey.shade200)
              : null,
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

  @override
  Widget build(BuildContext context) {
    final ordersRaw = _dailyData['orders'] as List<dynamic>? ?? [];
    final orderCount = _dedupeOrdersById(ordersRaw).length;
    final payTx =
        ((_dailyData['payments'] as Map?)?['transactions'] as List?)?.length ??
        0;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Order & Pembayaran'),
              Text(
                DateFormat('EEEE, d MMM yyyy', 'id_ID').format(_selectedDate),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.white),
              ),
            ],
          ),
          actions: [
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
          bottom: _isLoading || _error.isNotEmpty
              ? null
              : TabBar(
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.white,
                  tabs: [
                    Tab(text: 'Order ($orderCount)'),
                    Tab(text: 'Pembayaran ($payTx)'),
                  ],
                ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty
            ? Center(
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
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _compactSummaryStrip(context),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _ordersTable(context),
                        _paymentsTable(context),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
