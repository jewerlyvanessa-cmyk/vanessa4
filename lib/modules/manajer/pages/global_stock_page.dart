import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/utils/network_config.dart';

class GlobalStockPage extends ConsumerStatefulWidget {
  const GlobalStockPage({super.key});

  @override
  ConsumerState<GlobalStockPage> createState() => _GlobalStockPageState();
}

class _GlobalStockPageState extends ConsumerState<GlobalStockPage> {
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final branches = ref.read(userStateProvider).branches;

      final futures = branches.map((b) async {
        final branchId = b['branch_id']?.toString() ?? '';
        final name = (b['name'] ?? branchId).toString();
        if (branchId.isEmpty) return <String, dynamic>{};

        // Load up to 500 items for summary; if more needed we can add paging later.
        final uri = Uri.parse('$baseUrl/items').replace(
          queryParameters: {'branch_id': branchId, 'limit': '500'},
        );
        final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
        if (resp.statusCode != 200) {
          return <String, dynamic>{
            'branch_id': branchId,
            'branch_name': name,
            'error': '${resp.statusCode}',
          };
        }
        final decoded = jsonDecode(resp.body);
        if (decoded is! List) {
          return <String, dynamic>{
            'branch_id': branchId,
            'branch_name': name,
            'error': 'invalid_response',
          };
        }
        int itemCount = 0;
        int totalQty = 0;
        int readyCount = 0;
        int readyQty = 0;

        for (final it in decoded) {
          if (it is! Map) continue;
          itemCount += 1;
          final q = it['quantity'];
          final qty = q is int ? q : int.tryParse(q?.toString() ?? '') ?? 0;
          totalQty += qty;
          final st = (it['status'] ?? '').toString();
          if (st == 'ready') {
            readyCount += 1;
            readyQty += qty;
          }
        }

        return <String, dynamic>{
          'branch_id': branchId,
          'branch_name': name,
          'item_count': itemCount,
          'total_qty': totalQty,
          'ready_count': readyCount,
          'ready_qty': readyQty,
        };
      }).toList();

      final results =
          (await Future.wait(futures)).where((m) => m.isNotEmpty).toList();

      results.sort((a, b) {
        final ar = int.tryParse(a['total_qty']?.toString() ?? '') ?? 0;
        final br = int.tryParse(b['total_qty']?.toString() ?? '') ?? 0;
        return br.compareTo(ar);
      });

      if (!mounted) return;
      setState(() {
        _rows = results;
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

  String _fmtInt(int v) => NumberFormat.decimalPattern('id_ID').format(v);

  @override
  Widget build(BuildContext context) {
    final totalItems = _rows.fold<int>(0, (p, r) {
      final v = int.tryParse(r['item_count']?.toString() ?? '') ?? 0;
      return p + v;
    });
    final totalQty = _rows.fold<int>(0, (p, r) {
      final v = int.tryParse(r['total_qty']?.toString() ?? '') ?? 0;
      return p + v;
    });

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
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.inventory_2),
                          title: Text('Total item: ${_fmtInt(totalItems)}'),
                          subtitle: Text('Total qty: ${_fmtInt(totalQty)}'),
                          trailing: Chip(label: Text('${_rows.length}')),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(child: Text('Tidak ada data')),
                        )
                      else
                        ..._rows.map((r) {
                          final name = (r['branch_name'] ?? '-').toString();
                          final err = r['error']?.toString();
                          final itemCount =
                              int.tryParse(r['item_count']?.toString() ?? '') ??
                                  0;
                          final qty =
                              int.tryParse(r['total_qty']?.toString() ?? '') ?? 0;
                          final readyCount =
                              int.tryParse(r['ready_count']?.toString() ?? '') ??
                                  0;
                          final readyQty =
                              int.tryParse(r['ready_qty']?.toString() ?? '') ?? 0;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: const Icon(Icons.store),
                              title: Text(name),
                              subtitle: err != null
                                  ? Text('Gagal memuat: $err',
                                      style:
                                          const TextStyle(color: Colors.red))
                                  : Text(
                                      'Item: ${_fmtInt(itemCount)} • Qty: ${_fmtInt(qty)}\nReady: ${_fmtInt(readyCount)} • Ready Qty: ${_fmtInt(readyQty)}',
                                    ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

