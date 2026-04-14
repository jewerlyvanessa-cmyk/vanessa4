import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/providers/websocket_provider.dart';

class WorkshopOrdersPage extends ConsumerStatefulWidget {
  const WorkshopOrdersPage({super.key});

  @override
  ConsumerState<WorkshopOrdersPage> createState() => _WorkshopOrdersPageState();
}

class _WorkshopOrdersPageState extends ConsumerState<WorkshopOrdersPage> {
  List<dynamic> _workshopOrders = [];
  bool _isLoading = true;
  String _error = '';
  String _selectedStatus = 'all';

  @override
  void initState() {
    super.initState();
    _loadWorkshopOrders();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Note: ref.listen should be used in build method, not here
  }

  Future<void> _loadWorkshopOrders() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;

      final response = await http.get(
        Uri.parse('$baseUrl/workshop-orders?branch_id=${userState.branch}'),
        headers: NetworkConfig.defaultHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _workshopOrders = data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Gagal memuat data order workshop';
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

  List<dynamic> get _filteredOrders {
    if (_selectedStatus == 'all') return _workshopOrders;
    return _workshopOrders
        .where((order) => order['status'] == _selectedStatus)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    // Listen to real-time workshop order updates
    ref.listen(realTimeOrderUpdatesProvider, (previous, next) {
      next.whenData((update) {
        if (update['type'] == 'order_update' ||
            update['type'] == 'workshop_assignment' ||
            update['type'] == 'workshop_update') {
          // Refresh workshop orders when relevant updates occur
          _loadWorkshopOrders();
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Workshop'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => setState(() => _selectedStatus = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('Semua')),
              const PopupMenuItem(value: 'pending', child: Text('Pending')),
              const PopupMenuItem(
                value: 'in_progress',
                child: Text('Dalam Proses'),
              ),
              const PopupMenuItem(value: 'completed', child: Text('Selesai')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(_getStatusLabel(_selectedStatus)),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadWorkshopOrders,
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
                    onPressed: _loadWorkshopOrders,
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Summary Cards
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          'Total Order',
                          _workshopOrders.length,
                          Icons.build,
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildSummaryCard(
                          'Dalam Proses',
                          _workshopOrders
                              .where((o) => o['status'] == 'in_progress')
                              .length,
                          Icons.schedule,
                          Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),

                // Orders List
                Expanded(
                  child: _filteredOrders.isEmpty
                      ? Center(
                          child: Text(
                            'Tidak ada order workshop ${_selectedStatus == 'all' ? '' : 'dengan status ${_getStatusLabel(_selectedStatus)}'}',
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredOrders.length,
                          itemBuilder: (context, index) {
                            final order = _filteredOrders[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text('Order #${order['order_id']}'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Customer: ${order['customer_name'] ?? 'N/A'}',
                                    ),
                                    Text(
                                      'Item: ${order['nama_item'] ?? 'N/A'}',
                                    ),
                                    Text(
                                      'Teknisi: ${order['technician_name'] ?? 'Belum diassign'}',
                                    ),
                                    Text(
                                      'Status: ${_getStatusLabel(order['status'])}',
                                      style: TextStyle(
                                        color: _getStatusColor(order['status']),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (action) =>
                                      _handleOrderAction(order, action),
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'assign_technician',
                                      child: Text('Assign Teknisi'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'update_status',
                                      child: Text('Update Status'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'view_details',
                                      child: Text('Lihat Detail'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    int count,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'pending':
        return Colors.grey;
      case 'in_progress':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'all':
        return 'Semua Status';
      case 'pending':
        return 'Pending';
      case 'in_progress':
        return 'Dalam Proses';
      case 'completed':
        return 'Selesai';
      case 'cancelled':
        return 'Dibatalkan';
      default:
        return status ?? 'Unknown';
    }
  }

  void _handleOrderAction(dynamic order, String action) {
    switch (action) {
      case 'assign_technician':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Assign teknisi untuk order #${order['order_id']}'),
          ),
        );
        break;
      case 'update_status':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update status order #${order['order_id']}')),
        );
        break;
      case 'view_details':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Melihat detail order #${order['order_id']}')),
        );
        break;
    }
  }
}
