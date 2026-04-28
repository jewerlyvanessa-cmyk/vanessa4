import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/utils/network_config.dart';

class KasirReportsPage extends ConsumerStatefulWidget {
  const KasirReportsPage({super.key});

  @override
  ConsumerState<KasirReportsPage> createState() => _KasirReportsPageState();
}

class _KasirReportsPageState extends ConsumerState<KasirReportsPage> {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  String _error = '';

  List<dynamic> _orders = const [];
  Map<String, dynamic> _paymentsSummary = const {};
  List<dynamic> _payments = const [];

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      await _loadReport();
    }
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      final ordersUri = Uri.parse(
        '$baseUrl/orders/by-date?branch_id=${userState.branch}&date=$dateStr',
      );
      final paymentsUri = Uri.parse(
        '$baseUrl/payments/daily-summary?branch_id=${userState.branch}&date=$dateStr',
      );

      final responses = await Future.wait([
        http.get(ordersUri, headers: NetworkConfig.defaultHeaders),
        http.get(paymentsUri, headers: NetworkConfig.defaultHeaders),
      ]);

      final ordersRes = responses[0];
      final paymentsRes = responses[1];

      if (ordersRes.statusCode != 200 || paymentsRes.statusCode != 200) {
        setState(() {
          _error =
              'Gagal memuat laporan (orders: ${ordersRes.statusCode}, payments: ${paymentsRes.statusCode})';
          _isLoading = false;
        });
        return;
      }

      final ordersData = jsonDecode(ordersRes.body);
      final paymentsData = jsonDecode(paymentsRes.body);

      setState(() {
        _orders = ordersData is List ? ordersData : const [];
        _paymentsSummary =
            paymentsData is Map ? (paymentsData['summary'] ?? const {}) : const {};
        _payments =
            paymentsData is Map ? (paymentsData['transactions'] ?? const []) : const [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(_selectedDate);
    final money = NumberFormat('#,###', 'id_ID');

    final totalOrderAmount = _orders.fold<double>(0, (sum, o) {
      final n = double.tryParse((o is Map ? o['total'] : null)?.toString() ?? '');
      return sum + (n ?? 0);
    });

    final totalPaymentAmount =
        double.tryParse(_paymentsSummary['total_amount']?.toString() ?? '') ?? 0;
    final totalPayments =
        int.tryParse(_paymentsSummary['total_payments']?.toString() ?? '') ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Kasir'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectDate,
            tooltip: 'Pilih tanggal',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReport,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(child: Text(_error))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  dateLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),

                // Orders summary
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ringkasan Order',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text('Total order: ${_orders.length}'),
                        Text('Total nilai order: Rp ${money.format(totalOrderAmount)}'),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Payments summary
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ringkasan Pembayaran',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text('Total transaksi: $totalPayments'),
                        Text('Total pembayaran: Rp ${money.format(totalPaymentAmount)}'),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  'Pembayaran (${_payments.length})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                if (_payments.isEmpty)
                  const Text('Tidak ada pembayaran pada tanggal ini')
                else
                  ..._payments.take(50).map((p) {
                    if (p is! Map) return const SizedBox.shrink();
                    final orderId = p['order_id']?.toString() ?? '-';
                    final method = (p['payment_method'] ?? p['method'] ?? '-').toString();
                    final amount = double.tryParse(p['amount']?.toString() ?? '') ?? 0;
                    return Card(
                      child: ListTile(
                        dense: true,
                        title: Text('Order #$orderId'),
                        subtitle: Text('Metode: $method'),
                        trailing: Text('Rp ${money.format(amount)}'),
                      ),
                    );
                  }),
                if (_payments.length > 50)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Menampilkan 50 transaksi terbaru.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
    );
  }
}

