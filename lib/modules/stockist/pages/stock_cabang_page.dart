import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/modules/stockist/widgets/stock_inventory_grouped_table.dart';
import 'package:vanessa3/modules/stockist/widgets/stock_jenis_two_step_panel.dart';
import 'package:vanessa3/shared_widgets/stock_status_filter_summary_header.dart';
import 'package:vanessa3/utils/network_config.dart';

class StockCabangPage extends ConsumerStatefulWidget {
  const StockCabangPage({super.key});

  @override
  ConsumerState<StockCabangPage> createState() => _StockCabangPageState();
}

class _StockCabangPageState extends ConsumerState<StockCabangPage> {
  bool _isLoading = true;
  String _error = '';
  List<dynamic> _items = [];
  String? _selectedBranchId;
  String _search = '';
  String _selectedStatus = 'all';
  String? _jenisDetailFocus;

  @override
  void initState() {
    super.initState();
    final userState = ref.read(userStateProvider);
    _selectedBranchId = userState.branch.isNotEmpty
        ? userState.branch
        : userState.branches.isNotEmpty
            ? userState.branches[0]['branch_id']?.toString()
            : null;
    _loadItems();
  }

  Future<void> _loadItems() async {
    final branchId = _selectedBranchId;
    if (branchId == null || branchId.isEmpty) {
      setState(() {
        _items = [];
        _isLoading = false;
        _error = 'Branch tidak tersedia';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final uri = Uri.parse(
        '$baseUrl/items?branch_id=$branchId&limit=200',
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
      setState(() {
        _items = (data is List) ? data : <dynamic>[];
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
    var list = _items;
    if (_selectedStatus != 'all') {
      list = list
          .where((it) =>
              stockItemVisibleForStatusFilter(it, _selectedStatus))
          .toList();
    }
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((it) {
      final code = (it['item_code'] ?? it['kode_produk'] ?? '').toString();
      final name = (it['name'] ?? '').toString();
      return code.toLowerCase().contains(q) || name.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final userState = ref.watch(userStateProvider);
    final branches = userState.branches;
    String branchName = _selectedBranchId ?? '-';
    if ((_selectedBranchId ?? '').isNotEmpty && branches.isNotEmpty) {
      try {
        final found = branches.firstWhere(
          (b) => b['branch_id'].toString() == _selectedBranchId,
        );
        branchName = (found['name'] ?? _selectedBranchId).toString();
      } catch (_) {
        branchName = _selectedBranchId ?? '-';
      }
    }

    final branchId = _selectedBranchId ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Cabang'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadItems,
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
                          onPressed: _loadItems,
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
                          Row(
                            children: [
                              Expanded(
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Cabang',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedBranchId,
                                      isExpanded: true,
                                      items: branches.map((b) {
                                        final id = b['branch_id'].toString();
                                        final name = (b['name'] ?? id).toString();
                                        return DropdownMenuItem(
                                          value: id,
                                          child: Text(name),
                                        );
                                      }).toList(),
                                      onChanged: (v) {
                                        setState(() {
                                          _selectedBranchId = v;
                                          _jenisDetailFocus = null;
                                        });
                                        _loadItems();
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  branchName,
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          StockStatusFilterSummaryHeader(
                            selectedStatus: _selectedStatus,
                            onStatusChanged: (v) => setState(() {
                              _selectedStatus = v;
                              _jenisDetailFocus = null;
                            }),
                            summaryItems: _filteredItems,
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Cari item_code / nama',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => setState(() {
                              _search = v;
                              _jenisDetailFocus = null;
                            }),
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
