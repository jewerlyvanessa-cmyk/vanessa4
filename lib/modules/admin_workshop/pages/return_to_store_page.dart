import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/order_status_ui.dart';

class ReturnToStorePage extends ConsumerStatefulWidget {
  const ReturnToStorePage({super.key});

  @override
  ConsumerState<ReturnToStorePage> createState() => _ReturnToStorePageState();
}

class _ReturnToStorePageState extends ConsumerState<ReturnToStorePage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final us = ref.read(userStateProvider);
      final branch = us.branch.trim();
      if (branch.isEmpty) {
        setState(() {
          _error = 'Cabang belum dipilih';
          _loading = false;
        });
        return;
      }

      // status=completed -> backend mengembalikan done_workshop + ready_for_pickup
      final baseUrl = NetworkConfig.baseUrl;
      final uri = Uri.parse('$baseUrl/workshop-orders').replace(
        queryParameters: <String, String>{
          'branch_id': branch,
          'status': 'completed',
        },
      );

      final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
      if (resp.statusCode != 200) {
        setState(() {
          _error = 'Gagal memuat (HTTP ${resp.statusCode})';
          _loading = false;
        });
        return;
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! List) {
        setState(() {
          _error = 'Format data tidak valid';
          _loading = false;
        });
        return;
      }
      final list = decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _filter(String status) {
    return _rows
        .where(
          (r) => (r['status'] ?? '').toString().trim().toLowerCase() == status,
        )
        .toList();
  }

  Future<void> _setReadyForPickup(Map<String, dynamic> row) async {
    try {
      final us = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;
      final oid = row['order_id']?.toString().trim();
      if (oid == null || oid.isEmpty) return;

      final resp = await http.put(
        Uri.parse('$baseUrl/workshop-orders/$oid/status'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({
          'status': 'ready_for_pickup',
          'branch_id': us.branch,
        }),
      );
      if (resp.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Order #$oid -> Siap Diambil')),
          );
        }
        await _load();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Gagal update: ${resp.body}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  String _fmtTime(dynamic ts) {
    if (ts == null) return '-';
    try {
      return DateFormat(
        'dd MMM HH:mm',
        'id_ID',
      ).format(DateTime.parse(ts.toString()).toLocal());
    } catch (_) {
      return '-';
    }
  }

  Widget _table(BuildContext context, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const Center(child: Text('Tidak ada data'));
    }
    final cs = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 600;

    final columns = narrow
        ? <DataColumn>[
            DataColumn(label: dataTableColumnLabel('Order')),
            DataColumn(label: dataTableColumnLabel('Pelanggan')),
            const DataColumn(label: SizedBox(width: 44)),
          ]
        : <DataColumn>[
            DataColumn(label: dataTableColumnLabel('Order')),
            DataColumn(label: dataTableColumnLabel('Waktu')),
            DataColumn(label: dataTableColumnLabel('Pelanggan')),
            DataColumn(label: dataTableColumnLabel('Item')),
            DataColumn(label: dataTableColumnLabel('Status')),
            const DataColumn(label: SizedBox(width: 44)),
          ];

    final dataRows = rows.map((r) {
      final oid = r['order_id']?.toString() ?? '—';
      final cust = (r['customer_name'] ?? '—').toString();
      final item = (r['item_name'] ?? '—').toString();
      final st = (r['status'] ?? '').toString();
      final stLabel = (st == 'ready_for_pickup')
          ? 'Kirim ke Toko (Siap Diambil)'
          : OrderStatusUi.label(st);
      final stColor = OrderStatusUi.color(st);

      final action = (st.toLowerCase() == 'done_workshop')
          ? IconButton(
              tooltip: 'Kirim ke toko',
              icon: const Icon(Icons.local_shipping_outlined),
              onPressed: () => _setReadyForPickup(r),
            )
          : const SizedBox(width: 40);

      return DataRow(
        cells: narrow
            ? [
                DataCell(Text('#$oid')),
                DataCell(
                  Text(cust, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                DataCell(action),
              ]
            : [
                DataCell(Text('#$oid')),
                DataCell(Text(_fmtTime(r['updated_at'] ?? r['created_at']))),
                DataCell(
                  Text(cust, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                DataCell(
                  Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                DataCell(
                  Text(
                    stLabel,
                    style: TextStyle(
                      color: stColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                DataCell(action),
              ],
      );
    }).toList();

    final table = DataTable(
      headingRowColor: WidgetStateProperty.all(cs.surfaceContainerHigh),
      headingTextStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w800,
        fontSize: AppTypography.bodySmall,
      ),
      dataRowMinHeight: 44,
      dataRowMaxHeight: 62,
      columnSpacing: narrow ? 10 : 14,
      horizontalMargin: 10,
      showCheckboxColumn: false,
      dividerThickness: 0.6,
      columns: columns,
      rows: dataRows,
    );

    final scrolls = SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: table,
      ),
    );
    return kIsWeb ? Scrollbar(child: scrolls) : scrolls;
  }

  @override
  Widget build(BuildContext context) {
    // auto refresh when workshop updates arrive
    ref.listen(realTimeOrderUpdatesProvider, (prev, next) {
      next.whenData((u) {
        if (u['type'] == 'order_update' ||
            u['type'] == 'workshop_update' ||
            u['type'] == 'workshop_assignment') {
          _load();
        }
      });
    });

    final done = _filter('done_workshop');
    final ready = _filter('ready_for_pickup');

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kirim ke Toko'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
          ],
          bottom: _loading || _error != null
              ? null
              : TabBar(
                  tabs: [
                    Tab(text: 'Selesai (${done.length})'),
                    Tab(text: 'Siap diambil (${ready.length})'),
                  ],
                ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : TabBarView(
                children: [_table(context, done), _table(context, ready)],
              ),
      ),
    );
  }
}
