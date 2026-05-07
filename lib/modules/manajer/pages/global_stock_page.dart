import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/modules/stockist/widgets/stock_inventory_grouped_table.dart';
import 'package:vanessa3/modules/stockist/widgets/stock_jenis_two_step_panel.dart';
import 'package:vanessa3/shared_widgets/stock_status_filter_summary_header.dart';
import 'package:vanessa3/utils/network_config.dart';

class GlobalStockPage extends ConsumerStatefulWidget {
  const GlobalStockPage({super.key});

  @override
  ConsumerState<GlobalStockPage> createState() => _GlobalStockPageState();
}

class _GlobalStockPageState extends ConsumerState<GlobalStockPage> {
  bool _loading = true;
  String _error = '';

  List<dynamic> _items = const [];
  String _search = '';
  String _selectedStatus = 'all';
  String _selectedBranchId = 'all';
  String? _jenisDetailFocus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<(String value, String label)> _branchOptions() {
    final branches = ref.read(userStateProvider).branches;
    final out = <(String, String)>[('all', 'Semua cabang')];
    for (final b in branches) {
      final id = (b['branch_id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      final alias = (b['alias'] ?? '').toString().trim();
      final name = (b['name'] ?? id).toString().trim();
      out.add((id, alias.isNotEmpty ? alias : name));
    }
    return out;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final branches = ref.read(userStateProvider).branches;

      List<dynamic> items;
      if (_selectedBranchId != 'all') {
        final uri = Uri.parse('$baseUrl/items').replace(
          queryParameters: {
            'branch_id': _selectedBranchId,
            'limit': '1000',
          },
        );
        final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
        if (resp.statusCode != 200) {
          throw Exception('Gagal memuat stok (${resp.statusCode})');
        }
        final decoded = jsonDecode(resp.body);
        items = decoded is List ? List<dynamic>.from(decoded) : <dynamic>[];
      } else {
        final futures = branches.map((b) async {
          final branchId = b['branch_id']?.toString() ?? '';
          final branchName = (b['name'] ?? branchId).toString();
          if (branchId.isEmpty) return const <dynamic>[];

          final uri = Uri.parse('$baseUrl/items').replace(
            queryParameters: {'branch_id': branchId, 'limit': '500'},
          );
          final resp =
              await http.get(uri, headers: NetworkConfig.defaultHeaders);
          if (resp.statusCode != 200) return const <dynamic>[];

          final decoded = jsonDecode(resp.body);
          if (decoded is! List) return const <dynamic>[];

          return decoded
              .whereType<Map>()
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
    final q = _search.trim().toLowerCase();
    final out = <dynamic>[];
    for (final it in _items) {
      if (it is! Map) continue;
      final item = Map<String, dynamic>.from(it);

      if (_selectedStatus != 'all' &&
          !stockItemVisibleForStatusFilter(item, _selectedStatus)) {
        continue;
      }

      if (q.isNotEmpty) {
        final kode = (item['item_code'] ?? item['kode_produk'] ?? '')
            .toString()
            .toLowerCase();
        final name = (item['name'] ?? '').toString().toLowerCase();
        final branch = (item['branch_name'] ?? '').toString().toLowerCase();
        if (!kode.contains(q) && !name.contains(q) && !branch.contains(q)) {
          continue;
        }
      }

      out.add(item);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stok Global'),
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
                            onStatusChanged: (v) => setState(() {
                              _selectedStatus = v;
                              _jenisDetailFocus = null;
                            }),
                            summaryItems: _filteredItems,
                            filterLabel: 'Filter status',
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Cari item_code / nama / cabang',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() {
                          _search = v;
                          _jenisDetailFocus = null;
                        }),
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

