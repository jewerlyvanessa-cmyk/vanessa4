import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:vanessa3/utils/network_config.dart';

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
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.today),
                          title: Text(dateLabel),
                          subtitle: const Text('Semua branch • status: completed'),
                          trailing: Chip(label: Text('${_orders.length}')),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_orders.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text('Belum ada order completed hari ini'),
                          ),
                        )
                      else
                        ..._orders.map((o) {
                          final orderNumber =
                              (o['order_number'] ?? o['order_id'] ?? '-')
                                  .toString();
                          final branchName = (o['branch_name'] ?? '-').toString();
                          final customer = (o['customer_name'] ?? '-').toString();
                          final total =
                              o['total_akhir'] ?? o['total'] ?? o['total_amount'];
                          final createdAt = o['created_at'];
                          final createdBy =
                              (o['created_by_username'] ?? '-').toString();
                          final orderType = (o['order_type'] ?? '-').toString();

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: const Icon(Icons.check_circle, color: Colors.green),
                              title: Text(orderNumber),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('$branchName • ${_fmtTime(createdAt)} • $orderType'),
                                  Text('Customer: $customer'),
                                  Text('Kasir/CS: $createdBy'),
                                ],
                              ),
                              trailing: Text(
                                _fmtMoney(total),
                                style: const TextStyle(fontWeight: FontWeight.w700),
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

