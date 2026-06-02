import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/branch_types.dart';
import 'package:vanessa3/modules/stockist/widgets/stock_inventory_grouped_table.dart';
import 'package:vanessa3/modules/stockist/widgets/stock_jenis_two_step_panel.dart';
import 'package:vanessa3/shared_widgets/stock_inventory_search_field.dart';
import 'package:vanessa3/shared_widgets/stock_status_filter_summary_header.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/stock_inventory_search.dart';
import 'package:vanessa3/utils/stock_inventory_report_print.dart';

class GlobalStockPage extends ConsumerStatefulWidget {
  const GlobalStockPage({super.key});

  @override
  ConsumerState<GlobalStockPage> createState() => _GlobalStockPageState();
}

class _GlobalStockPageState extends ConsumerState<GlobalStockPage> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String _error = '';

  List<dynamic> _items = const [];
  List<Map<String, dynamic>> _branches = const [];
  String _search = '';
  String _selectedStatus = 'ready';
  String _selectedBranchId = 'all';
  String? _jenisDetailFocus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static bool _branchIsActive(Map<String, dynamic> b) {
    final s = (b['status'] ?? 'active').toString().trim().toLowerCase();
    return s.isEmpty || s == 'active';
  }

  Future<List<Map<String, dynamic>>> _fetchTokoWarehouseBranches() async {
    final uri = Uri.parse('${NetworkConfig.baseUrl}/branches');
    final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
    if (resp.statusCode != 200) {
      throw Exception('Gagal memuat cabang (${resp.statusCode})');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in decoded) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      if (!_branchIsActive(m)) continue;
      if (!branchTypeIsTokoOrWarehouse(m['branch_type']?.toString())) continue;
      out.add(m);
    }
    out.sort((a, b) {
      final an = (a['name'] ?? a['branch_id'] ?? '').toString();
      final bn = (b['name'] ?? b['branch_id'] ?? '').toString();
      return an.compareTo(bn);
    });
    return out;
  }

  String _branchDisplayLabel(Map<String, dynamic> b) {
    final id = (b['branch_id'] ?? '').toString().trim();
    final alias = (b['alias'] ?? '').toString().trim();
    final name = (b['name'] ?? id).toString().trim();
    final base = alias.isNotEmpty ? alias : name;
    final typeLabel = branchTypeLabel(b['branch_type']?.toString());
    return '$base · $typeLabel';
  }

  List<(String value, String label)> _branchOptions() {
    final out = <(String, String)>[('all', 'Semua toko & warehouse')];
    for (final b in _branches) {
      final id = (b['branch_id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      out.add((id, _branchDisplayLabel(b)));
    }
    return out;
  }

  Map<String, String> _itemsQueryParams(String branchId, {required int limit}) {
    final q = <String, String>{
      'branch_id': branchId,
      'limit': '$limit',
      'in_stock_only': '1',
    };
    if (_selectedStatus != 'all') {
      q['status'] = _selectedStatus;
    }
    return q;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final branches = await _fetchTokoWarehouseBranches();

      List<dynamic> items;
      if (_selectedBranchId != 'all') {
        final uri = Uri.parse('$baseUrl/items').replace(
          queryParameters: _itemsQueryParams(_selectedBranchId, limit: 1000),
        );
        final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
        if (resp.statusCode != 200) {
          throw Exception('Gagal memuat stok (${resp.statusCode})');
        }
        final decoded = jsonDecode(resp.body);
        items = decoded is List
            ? decoded.where(stockItemHasPositiveQuantity).toList()
            : <dynamic>[];
        Map<String, dynamic>? selected;
        for (final b in branches) {
          if (b['branch_id']?.toString().trim() == _selectedBranchId) {
            selected = b;
            break;
          }
        }
        if (selected != null) {
          final branchName = _branchDisplayLabel(selected);
          items = items
              .whereType<Map>()
              .map(
                (e) => <String, dynamic>{
                  ...Map<String, dynamic>.from(e),
                  'branch_id': _selectedBranchId,
                  'branch_name': branchName,
                },
              )
              .toList();
        }
      } else {
        final futures = branches.map((b) async {
          final branchId = b['branch_id']?.toString() ?? '';
          final branchName = _branchDisplayLabel(b);
          if (branchId.isEmpty) return const <dynamic>[];

          final uri = Uri.parse('$baseUrl/items').replace(
            queryParameters: _itemsQueryParams(branchId, limit: 500),
          );
          final resp =
              await http.get(uri, headers: NetworkConfig.defaultHeaders);
          if (resp.statusCode != 200) return const <dynamic>[];

          final decoded = jsonDecode(resp.body);
          if (decoded is! List) return const <dynamic>[];

          return decoded
              .whereType<Map>()
              .where(stockItemHasPositiveQuantity)
              .map((e) => <String, dynamic>{
                    ...Map<String, dynamic>.from(e),
                    'branch_id': branchId,
                    'branch_name': branchName,
                  })
              .toList();
        }).toList();

        final parts = await Future.wait(futures);
        items = [for (final p in parts) ...p];
      }

      if (!mounted) return;
      setState(() {
        _branches = branches;
        _items = items;
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

  List<dynamic> get _filteredItems {
    final out = <dynamic>[];
    for (final it in _items) {
      if (it is! Map) continue;
      final item = Map<String, dynamic>.from(it);

      if (!stockItemHasPositiveQuantity(item)) continue;

      if (_selectedStatus != 'all' &&
          !stockItemVisibleForStatusFilter(item, _selectedStatus)) {
        continue;
      }

      if (_search.trim().isNotEmpty &&
          !stockInventoryItemMatchesQuery(item, _search)) {
        continue;
      }

      out.add(item);
    }
    return out;
  }

  /// Sama seperti [_filteredItems] tapi **tanpa** filter search.
  /// Dipakai ringkasan tabel per-cabang agar tampil konsisten seperti laporan global.
  List<dynamic> get _statusFilteredItemsNoSearch {
    final out = <dynamic>[];
    for (final it in _items) {
      if (it is! Map) continue;
      final item = Map<String, dynamic>.from(it);
      if (!stockItemHasPositiveQuantity(item)) continue;
      if (_selectedStatus != 'all' &&
          !stockItemVisibleForStatusFilter(item, _selectedStatus)) {
        continue;
      }
      out.add(item);
    }
    return out;
  }

  List<_BranchStockSummaryRow> get _branchSummaryRows {
    final byBranch = <String, List<dynamic>>{};
    for (final it in _statusFilteredItemsNoSearch) {
      if (it is! Map) continue;
      final bid = (it['branch_id'] ?? '').toString().trim();
      if (bid.isEmpty) continue;
      (byBranch[bid] ??= <dynamic>[]).add(it);
    }
    final out = <_BranchStockSummaryRow>[];
    for (final e in byBranch.entries) {
      final bid = e.key;
      final items = e.value;
      String name = bid;
      for (final it in items) {
        final n = (it is Map ? (it['branch_name'] ?? '') : '').toString().trim();
        if (n.isNotEmpty) {
          name = n;
          break;
        }
      }
      out.add(
        _BranchStockSummaryRow(
          branchId: bid,
          branchName: name,
          skuCount: items.length,
          qtySum: stockListSumQuantity(items),
          weightGramSum: stockListSumWeightGram(items),
        ),
      );
    }
    out.sort((a, b) => b.qtySum.compareTo(a.qtySum));
    return out;
  }

  void _onSearchChanged(String v) => setState(() {
        _search = v;
        _jenisDetailFocus = null;
      });

  String _branchLabelForPrint() {
    if (_selectedBranchId == 'all') return 'Semua toko & warehouse';
    for (final e in _branchOptions()) {
      if (e.$1 == _selectedBranchId) return e.$2;
    }
    return _selectedBranchId;
  }

  Future<void> _printStockReport() async {
    final user = ref.read(userStateProvider);
    final logoBranch = _selectedBranchId != 'all'
        ? _selectedBranchId
        : user.branch.trim();
    await printStockInventoryReportPdf(
      context,
      branchLabel: _branchLabelForPrint(),
      branchIdForLogo: logoBranch.isEmpty ? user.branch.trim() : logoBranch,
      selectedStatus: _selectedStatus,
      filteredItems: _filteredItems,
      searchQuery: _search,
      includeBranchColumn: _selectedBranchId == 'all',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stok Global'),
        actions: [
          IconButton(
            tooltip: 'Cetak laporan stok',
            onPressed: _loading || _error.isNotEmpty ? null : _printStockReport,
            icon: const Icon(Icons.print_outlined),
          ),
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
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _selectedBranchId,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.store),
                              labelText: 'Cabang',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: _branchOptions()
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.$1,
                                    child: Text(e.$2),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) async {
                              final next = v ?? 'all';
                              if (next == _selectedBranchId) return;
                              setState(() {
                                _selectedBranchId = next;
                                _jenisDetailFocus = null;
                              });
                              await _load();
                            },
                          ),
                          const SizedBox(height: 10),
                          StockStatusFilterSummaryHeader(
                            selectedStatus: _selectedStatus,
                            onStatusChanged: (v) {
                              if (v == _selectedStatus) return;
                              setState(() {
                                _selectedStatus = v;
                                _jenisDetailFocus = null;
                              });
                              _load();
                            },
                            summaryItems: _statusFilteredItemsNoSearch,
                            filterLabel: 'Filter status',
                          ),
                        ],
                      ),
                    ),
                    if (_selectedBranchId == 'all') ...[
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: _GlobalStockBranchSummaryTable(
                            rows: _branchSummaryRows,
                            selectedStatus: _selectedStatus,
                          ),
                        ),
                      ),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: StockInventorySearchFieldStateful(
                          controller: _searchCtrl,
                          onQueryChanged: _onSearchChanged,
                          enabled: !_loading && _error.isEmpty,
                          hintText:
                              'Cari kode, nama, jenis, cabang, material, status…',
                        ),
                      ),
                      Expanded(
                        child: StockJenisTwoStepPanel(
                          filteredItems: _filteredItems,
                          selectedJenisLabel: _jenisDetailFocus,
                          onSelectedJenisLabelChanged: (v) =>
                              setState(() => _jenisDetailFocus = v),
                          detailBuilder: (context, items) =>
                              StockInventoryGroupedTable(
                            filteredItems: items,
                            showStockistActions: false,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _BranchStockSummaryRow {
  const _BranchStockSummaryRow({
    required this.branchId,
    required this.branchName,
    required this.skuCount,
    required this.qtySum,
    required this.weightGramSum,
  });

  final String branchId;
  final String branchName;
  final int skuCount;
  final int qtySum;
  final double weightGramSum;
}

class _GlobalStockBranchSummaryTable extends StatelessWidget {
  const _GlobalStockBranchSummaryTable({
    required this.rows,
    required this.selectedStatus,
  });

  final List<_BranchStockSummaryRow> rows;
  final String selectedStatus;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scope = stockUiFilterScopeLabel(selectedStatus);

    Widget headerCell(String label, {bool right = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Align(
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      );
    }

    Widget cell(
      String text, {
      bool right = false,
      bool strong = false,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Align(
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: right ? TextAlign.right : TextAlign.left,
            style: strong
                ? const TextStyle(fontWeight: FontWeight.w700)
                : null,
          ),
        ),
      );
    }

    final tableRows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(color: cs.surfaceContainerHigh),
        children: [
          headerCell('Cabang ($scope)'),
          headerCell('SKU', right: true),
          headerCell('Qty', right: true),
          headerCell('Berat', right: true),
        ],
      ),
    ];

    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      tableRows.add(
        TableRow(
          decoration: BoxDecoration(
            color: i.isOdd
                ? cs.surfaceContainerHighest.withValues(alpha: 0.35)
                : null,
          ),
          children: [
            cell(r.branchName),
            cell('${r.skuCount}', right: true),
            cell('${r.qtySum}', right: true, strong: true),
            cell(stockListFormatWeightGram(r.weightGramSum), right: true),
          ],
        ),
      );
    }

    if (rows.isEmpty) {
      return Center(
        child: Text(
          'Tidak ada stok untuk filter ini.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    return Material(
      color: cs.surfaceContainerLow.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        child: SingleChildScrollView(
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(3.4),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1.4),
            },
            border: TableBorder(
              horizontalInside: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.45),
                width: 0.5,
              ),
            ),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: tableRows,
          ),
        ),
      ),
    );
  }
}

