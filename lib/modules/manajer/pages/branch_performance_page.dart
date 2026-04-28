import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/utils/network_config.dart';

class BranchPerformancePage extends ConsumerStatefulWidget {
  const BranchPerformancePage({super.key});

  @override
  ConsumerState<BranchPerformancePage> createState() =>
      _BranchPerformancePageState();
}

class _BranchPerformancePageState extends ConsumerState<BranchPerformancePage> {
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

        final uri = Uri.parse('$baseUrl/api/dashboard/order-today').replace(
          queryParameters: {'branch_id': branchId},
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
        if (decoded is! Map) {
          return <String, dynamic>{
            'branch_id': branchId,
            'branch_name': name,
            'error': 'invalid_response',
          };
        }

        final total = decoded['total_orders'] ?? 0;
        final completed = decoded['completed_orders'] ?? 0;
        final pending = decoded['pending_orders'] ?? 0;
        final revenue = decoded['total_revenue'] ?? 0;

        return <String, dynamic>{
          'branch_id': branchId,
          'branch_name': name,
          'total_orders': total,
          'completed_orders': completed,
          'pending_orders': pending,
          'total_revenue': revenue,
        };
      }).toList();

      final results = (await Future.wait(futures))
          .where((m) => m.isNotEmpty)
          .toList();

      results.sort((a, b) {
        final ar = double.tryParse(a['total_revenue']?.toString() ?? '') ?? 0;
        final br = double.tryParse(b['total_revenue']?.toString() ?? '') ?? 0;
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

  String _fmtMoney(dynamic v) {
    final n = double.tryParse(v?.toString() ?? '');
    if (n == null) return '-';
    return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
        .format(n);
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE, dd MMM yyyy', 'id_ID')
        .format(DateTime.now().toLocal());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Performa Cabang (Hari Ini)'),
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
                          leading: const Icon(Icons.today),
                          title: Text(dateLabel),
                          subtitle: const Text('Order hari ini per cabang'),
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
                          final total = (r['total_orders'] ?? 0).toString();
                          final completed =
                              (r['completed_orders'] ?? 0).toString();
                          final pending = (r['pending_orders'] ?? 0).toString();
                          final revenue = _fmtMoney(r['total_revenue']);
                          final err = r['error']?.toString();

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: const Icon(Icons.store),
                              title: Text(name),
                              subtitle: err != null
                                  ? Text(
                                      'Gagal memuat: $err',
                                      style:
                                          const TextStyle(color: Colors.red),
                                    )
                                  : Text(
                                      'Total: $total • Completed: $completed • Pending: $pending',
                                    ),
                              trailing: Text(
                                err != null ? '-' : revenue,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
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

