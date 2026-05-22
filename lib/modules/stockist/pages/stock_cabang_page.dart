import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/modules/stockist/widgets/stock_inventory_grouped_table.dart';
import 'package:vanessa3/modules/stockist/widgets/stock_jenis_two_step_panel.dart';
import 'package:vanessa3/shared_widgets/stock_inventory_search_field.dart';
import 'package:vanessa3/shared_widgets/stock_status_filter_summary_header.dart';
import 'package:vanessa3/utils/branch_types.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/stock_inventory_search.dart';
import 'package:vanessa3/utils/stock_inventory_report_print.dart';

class StockCabangPage extends ConsumerStatefulWidget {
  const StockCabangPage({super.key});

  @override
  ConsumerState<StockCabangPage> createState() => _StockCabangPageState();
}

class _StockCabangPageState extends ConsumerState<StockCabangPage> {
  final _searchCtrl = TextEditingController();
  bool _isLoading = true;
  String _error = '';
  List<dynamic> _items = [];
  List<Map<String, dynamic>> _branches = const [];
  String? _selectedBranchId;
  String _search = '';
  String _selectedStatus = 'ready';
  String? _jenisDetailFocus;

  @override
  void initState() {
    super.initState();
    _initBranchesAndLoad();
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
      final aa = (a['alias'] ?? a['name'] ?? a['branch_id'] ?? '').toString();
      final bb = (b['alias'] ?? b['name'] ?? b['branch_id'] ?? '').toString();
      return aa.compareTo(bb);
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

  Future<void> _initBranchesAndLoad() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final branches = await _fetchTokoWarehouseBranches();
      if (!mounted) return;
      var selected = _selectedBranchId;
      final ids = branches
          .map((b) => b['branch_id']?.toString().trim())
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet();
      if (selected == null || !ids.contains(selected)) {
        selected = branches.isNotEmpty
            ? branches.first['branch_id']?.toString()
            : null;
      }
      setState(() {
        _branches = branches;
        _selectedBranchId = selected;
      });
      await _loadItems();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Map<String, String> _itemsQueryParams(String branchId) {
    final q = <String, String>{
      'branch_id': branchId,
      'limit': '5000',
      'in_stock_only': '1',
    };
    if (_selectedStatus != 'all') {
      q['status'] = _selectedStatus;
    }
    return q;
  }

  Future<void> _loadItems() async {
    final branchId = _selectedBranchId;
    if (branchId == null || branchId.isEmpty) {
      setState(() {
        _items = [];
        _isLoading = false;
        _error = _branches.isEmpty
            ? 'Tidak ada cabang toko/warehouse aktif'
            : 'Cabang belum dipilih';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final uri = Uri.parse('$baseUrl/items').replace(
        queryParameters: _itemsQueryParams(branchId),
      );
      final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
      if (resp.statusCode != 200) {
        setState(() {
          _error = 'Gagal memuat stok cabang (${resp.statusCode})';
          _isLoading = false;
        });
        return;
      }

      final data = jsonDecode(resp.body);
      final list = (data is List) ? List<dynamic>.from(data) : <dynamic>[];
      setState(() {
        _items = list.where(stockItemHasPositiveQuantity).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  List<dynamic> get _filteredItems {
    var list = _items.where(stockItemHasPositiveQuantity).toList();
    if (_selectedStatus != 'all') {
      list = list
          .where((it) =>
              stockItemVisibleForStatusFilter(it, _selectedStatus))
          .toList();
    }
    if (_search.trim().isEmpty) return list;
    return list
        .where((it) => stockInventoryItemMatchesQuery(it, _search))
        .toList();
  }

  void _onSearchChanged(String v) => setState(() {
        _search = v;
        _jenisDetailFocus = null;
      });

  String _selectedBranchName() {
    final id = (_selectedBranchId ?? '').trim();
    for (final b in _branches) {
      if (b['branch_id']?.toString().trim() == id) {
        return _branchDisplayLabel(b);
      }
    }
    return id.isEmpty ? '-' : id;
  }

  Future<void> _printStockReport() async {
    final branchId = (_selectedBranchId ?? '').trim();
    await printStockInventoryReportPdf(
      context,
      branchLabel: _selectedBranchName(),
      branchIdForLogo: branchId,
      selectedStatus: _selectedStatus,
      filteredItems: _filteredItems,
      searchQuery: _search,
    );
  }

  @override
  Widget build(BuildContext context) {
    final branchName = _selectedBranchName();
    final branchId = _selectedBranchId ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Cabang'),
        actions: [
          IconButton(
            tooltip: 'Cetak laporan stok',
            onPressed: _isLoading || _error.isNotEmpty
                ? null
                : _printStockReport,
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _initBranchesAndLoad,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _initBranchesAndLoad,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Cabang (toko & warehouse)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _branches.any((b) =>
                                        b['branch_id']?.toString() ==
                                        _selectedBranchId)
                                    ? _selectedBranchId
                                    : null,
                                isExpanded: true,
                                hint: const Text('Pilih cabang'),
                                items: _branches.map((b) {
                                  final id = b['branch_id'].toString();
                                  return DropdownMenuItem(
                                    value: id,
                                    child: Text(_branchDisplayLabel(b)),
                                  );
                                }).toList(),
                                onChanged: _branches.isEmpty
                                    ? null
                                    : (v) {
                                        setState(() {
                                          _selectedBranchId = v;
                                          _jenisDetailFocus = null;
                                        });
                                        _loadItems();
                                      },
                              ),
                            ),
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
                              _loadItems();
                            },
                            summaryItems: _filteredItems,
                          ),
                          const SizedBox(height: 10),
                          StockInventorySearchFieldStateful(
                            controller: _searchCtrl,
                            onQueryChanged: _onSearchChanged,
                            enabled: !_isLoading && _error.isEmpty,
                          ),
                        ],
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
                          branchIdForMutations: branchId,
                          branchDisplayNameForHistory: branchName,
                          onReload: _loadItems,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
