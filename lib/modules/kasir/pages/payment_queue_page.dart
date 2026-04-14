import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/main.dart';
import 'payment_page.dart';
import '../../../utils/network_config.dart';
import '../../../utils/logger.dart';
import 'package:vanessa3/providers/websocket_provider.dart';

class PaymentQueuePage extends ConsumerStatefulWidget {
  const PaymentQueuePage({super.key});

  @override
  ConsumerState<PaymentQueuePage> createState() => _PaymentQueuePageState();
}

class _PaymentQueuePageState extends ConsumerState<PaymentQueuePage> {
  List<dynamic> _pendingOrders = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadPendingOrders();
  }

  Future<void> _loadPendingOrders() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      Logger.logInfo('Loading pending orders for branch: ${userState.branch}');

      if (userState.branch.isEmpty) {
        setState(() {
          _error = 'Branch tidak dikonfigurasi. Silakan login ulang.';
          _isLoading = false;
        });
        return;
      }

      final response = await http.get(
        Uri.parse(
          '${NetworkConfig.baseUrl}/orders/pending-payment?branch_id=${userState.branch}',
        ),
        headers: NetworkConfig.defaultHeaders,
      );

      Logger.logInfo('Response status: ${response.statusCode}');
      Logger.logInfo('Payment queue fetched with status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        Logger.logInfo('Parsed data: $data');
        setState(() {
          _pendingOrders = data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Gagal memuat antrian pembayaran: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.logError('Error loading pending orders: $e');
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for real-time notifications
    ref.listen(notificationProvider, (previous, next) {
      next.whenData((message) {
        if (message.contains('completed')) {
          // Refresh pending orders when payment is completed
          _loadPendingOrders();
        }
      });
    });

    final isServerHealthy = ref.watch(healthCheckProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Antrian Pembayaran'),
        actions: [
          Row(
            children: [
              Icon(
                isServerHealthy ? Icons.wifi : Icons.wifi_off,
                color: isServerHealthy ? Colors.green : Colors.red,
                size: 20,
              ),
              const SizedBox(width: 4),
              const Text('Live', style: TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPendingOrders,
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
                    onPressed: _loadPendingOrders,
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            )
          : _pendingOrders.isEmpty
          ? const Center(child: Text('Tidak ada order yang perlu dibayar'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _pendingOrders.length,
              itemBuilder: (context, index) {
                final order = _pendingOrders[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text('Order #${order['order_id']}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Customer: ${order['customer_name'] ?? 'N/A'}'),
                        Text('Item: ${order['nama_item'] ?? 'N/A'}'),
                        Text('Total: Rp ${order['total']?.toString() ?? '0'}'),
                        Text('Status: ${order['status']}'),
                      ],
                    ),
                    trailing: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PaymentPage(order: order),
                          ),
                        );
                      },
                      child: const Text('Bayar'),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
