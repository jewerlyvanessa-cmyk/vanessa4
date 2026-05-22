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
                            summaryItems: _filteredItems,
                            filterLabel: 'Filter status',
                          ),
                        ],
                      ),
                    ),
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
                ),
    );
  }
}

