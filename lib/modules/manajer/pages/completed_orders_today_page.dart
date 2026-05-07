import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

class CompletedOrdersTodayPage extends StatefulWidget {
  const CompletedOrdersTodayPage({super.key});

  @override
  State<CompletedOrdersTodayPage> createState() =>
      _CompletedOrdersTodayPageState();
}

class _CompletedOrdersTodayPageState extends State<CompletedOrdersTodayPage> {
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmtMoney(dynamic v) {
    final n = double.tryParse(v?.toString() ?? '');
    if (n == null) return '-';
    return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
        .format(n);
  }

  String _fmtTime(dynamic v) {
    if (v == null) return '-';
    try {
      final dt = DateTime.parse(v.toString()).toLocal();
      return DateFormat('HH:mm', 'id_ID').format(dt);
    } catch (_) {
      return v.toString();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final resp = await http.get(
        Uri.parse('$baseUrl/reports/orders-completed-today?limit=300'),
        headers: NetworkConfig.defaultHeaders,
      );

      if (!mounted) return;

      if (resp.statusCode != 200) {
        setState(() {
          _error = 'Gagal memuat data (${resp.statusCode}): ${resp.body}';
          _loading = false;
        });
        return;
      }

      final decoded = jsonDecode(resp.body);
      final list = decoded is List ? decoded : const [];
      setState(() {
        _orders = list
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE, dd MMM yyyy', 'id_ID')
        .format(DateTime.now().toLocal());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Completed Hari Ini'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Card(
                        child: ListTile(
                          leading: const Icon(Icons.today),
                          title: Text(dateLabel),
                          subtitle: const Text(
                            'Semua branch • status: completed',
                          ),
                          trailing: Chip(label: Text('${_orders.length}')),
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: _orders.isEmpty
                            ? ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(top: 48),
                                children: const [
                                  Center(
                                    child: Text(
                                      'Belum ada order completed hari ini',
                                    ),
                                  ),
                                ],
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final cs = Theme.of(context).colorScheme;
final minW = math.max(
                                    constraints.maxWidth,
                                    920.0,
                                  );
                                  final rows = <DataRow>[];
                                  for (var i = 0; i < _orders.length; i++) {
                                    final o = _orders[i];
                                    final orderNumber =
                                        (o['order_number'] ??
                                                o['order_id'] ??
                                                '-')
                                            .toString();
                                    final branchName =
                                        (o['branch_name'] ?? '-').toString();
                                    final customer =
                                        (o['customer_name'] ?? '-').toString();
                                    final total = o['total_akhir'] ??
                                        o['total'] ??
                                        o['total_amount'];
                                    final createdAt = o['created_at'];
                                    final createdBy =
                                        (o['created_by_username'] ?? '-')
                                            .toString();
                                    final orderType =
                                        (o['order_type'] ?? '-').toString();
                                    rows.add(
                                      DataRow(
                                        color:
                                            WidgetStateProperty.resolveWith(
                                                (s) {
                                          if (s.contains(
                                            WidgetState.hovered,
                                          )) {
                                            return cs.primary
                                                .withValues(alpha: 0.06);
                                          }
                                          return i.isOdd
                                              ? cs.surfaceContainerHighest
                                                  .withValues(alpha: 0.45)
                                              : null;
                                        }),
                                        cells: [
                                          DataCell(
                                            Text(
                                              orderNumber,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          DataCell(Text(branchName)),
                                          DataCell(Text(_fmtTime(createdAt))),
                                          DataCell(Text(orderType)),
                                          DataCell(Text(customer)),
                                          DataCell(Text(createdBy)),
                                          DataCell(
                                            Text(
                                              _fmtMoney(total),
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: cs.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      0,
                                      12,
                                      12,
                                    ),
                                    child: Material(
                                      elevation: 0,
                                      color: cs.surfaceContainerLow
                                          .withValues(alpha: 0.65),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(
                                          color: cs.outlineVariant
                                              .withValues(alpha: 0.45),
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Scrollbar(
                                        child: SingleChildScrollView(
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          scrollDirection: Axis.horizontal,
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              minWidth: minW,
                                            ),
                                            child: SingleChildScrollView(
                                              physics:
                                                  const AlwaysScrollableScrollPhysics(),
                                              child: DataTable(
                                                headingRowColor:
                                                    WidgetStateProperty.all(
                                                  cs.surfaceContainerHigh,
                                                ),
dataRowMinHeight: 44,
                                                dataRowMaxHeight: 56,
                                                columnSpacing: 12,
                                                horizontalMargin: 10,
                                                showCheckboxColumn: false,
                                                dividerThickness: 0.5,
                                                columns: [
                                                  DataColumn(
                                                    label: dataTableColumnLabel('No. Order'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Cabang'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Waktu'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Tipe'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Customer'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Kasir/CS'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Total'),
                                                    numeric: true,
                                                  ),
                                                ],
                                                rows: rows,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

