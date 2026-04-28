import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/utils/network_config.dart';

class SalesReportTodayPage extends ConsumerStatefulWidget {
  const SalesReportTodayPage({super.key});

  @override
  ConsumerState<SalesReportTodayPage> createState() =>
      _SalesReportTodayPageState();
}

class _SalesReportTodayPageState extends ConsumerState<SalesReportTodayPage> {
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _today() => DateTime.now().toLocal().toIso8601String().split('T').first;

  String _fmtMoney(num v) {
    return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
        .format(v);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final date = _today();
      final branches = ref.read(userStateProvider).branches;

      final futures = branches.map((b) async {
        final branchId = b['branch_id']?.toString() ?? '';
        final name = (b['name'] ?? branchId).toString();
        if (branchId.isEmpty) return <String, dynamic>{};

        final uri = Uri.parse('$baseUrl/payments/daily-summary').replace(
          queryParameters: {'branch_id': branchId, 'date': date},
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
        final summary = decoded['summary'];
        if (summary is! Map) {
          return <String, dynamic>{
            'branch_id': branchId,
            'branch_name': name,
            'error': 'missing_summary',
          };
        }

        num toNum(dynamic v) =>
            num.tryParse(v?.toString() ?? '') ?? 0;

        return <String, dynamic>{
          'branch_id': branchId,
          'branch_name': name,
          'total_payments': toNum(summary['total_payments']),
          'total_amount': toNum(summary['total_amount']),
          'cash_payments': toNum(summary['cash_payments']),
          'transfer_payments': toNum(summary['transfer_payments']),
          'qris_payments': toNum(summary['qris_payments']),
        };
      }).toList();

      final results =
          (await Future.wait(futures)).where((m) => m.isNotEmpty).toList();

      results.sort((a, b) {
        final ar = num.tryParse(a['total_amount']?.toString() ?? '') ?? 0;
        final br = num.tryParse(b['total_amount']?.toString() ?? '') ?? 0;
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

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE, dd MMM yyyy', 'id_ID')
        .format(DateTime.now().toLocal());
    final totalAll = _rows.fold<num>(0, (p, r) {
      final v = num.tryParse(r['total_amount']?.toString() ?? '') ?? 0;
      return p + v;
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Penjualan (Hari Ini)'),
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
                          leading: const Icon(Icons.payments),
                          title: Text(dateLabel),
                          subtitle: Text('Total semua cabang: ${_fmtMoney(totalAll)}'),
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
                          final totalPayments =
                              (r['total_payments'] ?? 0).toString();
                          final totalAmount =
                              num.tryParse(r['total_amount']?.toString() ?? '') ??
                                  0;
                          final cash = (r['cash_payments'] ?? 0).toString();
                          final transfer =
                              (r['transfer_payments'] ?? 0).toString();
                          final qris = (r['qris_payments'] ?? 0).toString();

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
                                      'Transaksi: $totalPayments • Cash: $cash • Transfer: $transfer • QRIS: $qris',
                                    ),
                              trailing: Text(
                                err != null ? '-' : _fmtMoney(totalAmount),
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

