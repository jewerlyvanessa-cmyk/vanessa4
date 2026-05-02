import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/utils/network_config.dart';

class DailyOrdersPaymentsPage extends ConsumerStatefulWidget {
  const DailyOrdersPaymentsPage({super.key});

  @override
  ConsumerState<DailyOrdersPaymentsPage> createState() =>
      _DailyOrdersPaymentsPageState();
}

class _DailyOrdersPaymentsPageState
    extends ConsumerState<DailyOrdersPaymentsPage> {
  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic> _dailyData = {};
  bool _isLoading = true;
  String _error = '';

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _loadDailyData();
  }

  Future<void> _loadDailyData() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      // Load orders data - menggunakan endpoint yang sama dengan CS tapi tanpa user_id filter
      final ordersResponse = await http.get(
        Uri.parse(
          '$baseUrl/orders/daily?branch_id=${userState.branch}&date=$dateStr',
        ),
        headers: NetworkConfig.defaultHeaders,
      );

      // Load payments data
      final paymentsResponse = await http.get(
        Uri.parse(
          '$baseUrl/payments/daily?date=$dateStr&branch_id=${userState.branch}',
        ),
        headers: NetworkConfig.defaultHeaders,
      );

      if (ordersResponse.statusCode == 200 &&
          paymentsResponse.statusCode == 200) {
        final ordersData = jsonDecode(ordersResponse.body);
        final paymentsData = jsonDecode(paymentsResponse.body);

        setState(() {
          _dailyData = {'orders': ordersData, 'payments': paymentsData};
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Gagal memuat data harian';
          _isLoading = false;
        });
      }
    } catch (error) {
      setState(() {
        _error = 'Error: $error';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadDailyData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order & Pembayaran Harian'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () => _selectDate(context),
            tooltip: 'Pilih Tanggal',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDailyData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadDailyData,
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date Header
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Tanggal: ${DateFormat('dd MMMM yyyy', 'id_ID').format(_selectedDate)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_calendar),
                            onPressed: () => _selectDate(context),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Orders Summary
                  _buildOrdersSummary(),

                  const SizedBox(height: 16),

                  // Payments Summary
                  _buildPaymentsSummary(),

                  const SizedBox(height: 16),

                  // Recent Orders
                  _buildRecentOrders(),

                  const SizedBox(height: 16),

                  // Recent Payments
                  _buildRecentPayments(),
                ],
              ),
            ),
    );
  }

  Widget _buildOrdersSummary() {
    final orders = _dailyData['orders'] ?? [];
    final totalOrders = orders.length;
    final completedOrders = orders
        .where((o) => o['status'] == 'completed')
        .length;
    final pendingOrders = orders.where((o) => o['status'] == 'pending').length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shopping_cart, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Ringkasan Order',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Total', totalOrders.toString(), Colors.blue),
                _buildStatItem(
                  'Selesai',
                  completedOrders.toString(),
                  Colors.green,
                ),
                _buildStatItem(
                  'Pending',
                  pendingOrders.toString(),
                  Colors.orange,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentsSummary() {
    final payments = _dailyData['payments'] ?? {};
    final summary = payments['summary'] ?? {};
    final totalAmount = summary['total_amount'] ?? 0;
    final totalTransactions = summary['total_transactions'] ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.payment, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Ringkasan Pembayaran',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Total',
                  'Rp ${NumberFormat('#,###', 'id_ID').format(_toNum(totalAmount))}',
                  Colors.green,
                ),
                _buildStatItem(
                  'Transaksi',
                  totalTransactions.toString(),
                  Colors.blue,
                ),
              ],
            ),
            if (summary['by_method'] != null &&
                (summary['by_method'] as List).isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Per Metode Pembayaran:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...(summary['by_method'] as List).map(
                (method) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(method['method'] ?? 'Unknown'),
                      Text(
                        'Rp ${NumberFormat('#,###', 'id_ID').format(_toNum(method['total_amount']))}',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecentOrders() {
    final orders = _dailyData['orders'] ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order Hari Ini (${orders.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            if (orders.isEmpty)
              const Text('Tidak ada order hari ini')
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: orders.length > 5 ? 5 : orders.length,
                itemBuilder: (context, index) {
                  final order = orders[index];
                  return ListTile(
                    title: Text('Order #${order['order_id']}'),
                    subtitle: Text(
                      '${order['nama_item'] ?? 'N/A'} - ${order['status']}',
                    ),
                    trailing: Text(
                      'Rp ${NumberFormat('#,###', 'id_ID').format(_toNum(order['total']))}',
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentPayments() {
    final payments = _dailyData['payments'] ?? {};
    final transactions = payments['transactions'] ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pembayaran Hari Ini (${transactions.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            if (transactions.isEmpty)
              const Text('Tidak ada pembayaran hari ini')
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: transactions.length > 5 ? 5 : transactions.length,
                itemBuilder: (context, index) {
                  final payment = transactions[index];
                  return ListTile(
                    title: Text('Order #${payment['order_id']}'),
                    subtitle: Text(
                      '${payment['customer_name'] ?? 'N/A'} - ${payment['method']}',
                    ),
                    trailing: Text(
                      'Rp ${NumberFormat('#,###', 'id_ID').format(_toNum(payment['amount']))}',
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}
