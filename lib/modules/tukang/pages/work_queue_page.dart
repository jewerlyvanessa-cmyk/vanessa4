import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/data/api_service.dart';

class WorkQueuePage extends ConsumerStatefulWidget {
  const WorkQueuePage({super.key});

  @override
  ConsumerState<WorkQueuePage> createState() => _WorkQueuePageState();
}

class _WorkQueuePageState extends ConsumerState<WorkQueuePage> {
  List<Map<String, dynamic>> _workQueue = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadWorkQueue();
  }

  Future<void> _loadWorkQueue() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final workQueue = await ApiService.getWorkQueue(
        userState.userId.toString(),
        userState.branch,
      );

      setState(() {
        _workQueue = workQueue;
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _errorMessage = 'Gagal memuat antrian kerja: $error';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Kembali',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Antrian Kerja'),
      ),
      body: Column(
        children: [
          // Work Queue List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_errorMessage, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadWorkQueue,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  )
                : _workQueue.isEmpty
                ? const Center(
                    child: Text('Tidak ada order dalam antrian kerja'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: _workQueue.length,
                    itemBuilder: (context, index) {
                      final order = _workQueue[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _getStatusColor(order['status']),
                            child: Text('${index + 1}'),
                          ),
                          title: Text('Order #${order['order_id']}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Jenis: ${_getOrderTypeText(order['order_type'])}',
                              ),
                              Text('Item: ${order['item_name'] ?? 'N/A'}'),
                              Text(
                                'Customer: ${order['customer_name'] ?? 'N/A'}',
                              ),
                              Text(
                                'Prioritas: ${_getPriorityText(order['priority'])}',
                              ),
                              Text('Estimasi: ${order['estimated_time']}'),
                            ],
                          ),
                          trailing: ElevatedButton(
                            onPressed: () => _startWork(order),
                            child: const Text('Mulai'),
                          ),
                          onTap: () => _showWorkDetails(context, order),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadWorkQueue,
        tooltip: 'Refresh Antrian',
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'in_workshop':
      case 'repairing':
      case 'polishing':
      case 'custom_work':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getOrderTypeText(String orderType) {
    switch (orderType) {
      case 'service':
        return 'Service';
      case 'custom':
        return 'Custom Order';
      case 'buyback':
        return 'Buyback';
      default:
        return orderType;
    }
  }

  String _getPriorityText(String priority) {
    switch (priority) {
      case 'high':
        return 'Tinggi';
      case 'medium':
        return 'Sedang';
      case 'low':
        return 'Rendah';
      default:
        return 'Normal';
    }
  }

  void _startWork(Map<String, dynamic> order) async {
    try {
      await ApiService.updateWorkProgress(
        order['order_id'],
        'repairing',
        ref.read(userStateProvider).userId.toString(),
        notes: 'Work started by technician',
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Memulai pekerjaan Order #${order['order_id']}'),
            ),
          );
        }
      });

      // Refresh the work queue
      _loadWorkQueue();
    } catch (error) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memulai pekerjaan: $error')),
          );
        }
      });
    }
  }

  void _showWorkDetails(BuildContext context, Map<String, dynamic> order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Detail Order #${order['order_id']}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Jenis Order: ${_getOrderTypeText(order['order_type'])}'),
              const SizedBox(height: 8),
              Text('Status: ${order['status']}'),
              const SizedBox(height: 8),
              Text('Item: ${order['item_name'] ?? 'N/A'}'),
              const SizedBox(height: 8),
              Text('Material: ${order['material'] ?? 'N/A'}'),
              const SizedBox(height: 8),
              Text('Berat: ${order['weight'] ?? 'N/A'} gram'),
              const SizedBox(height: 8),
              Text('Customer: ${order['customer_name'] ?? 'N/A'}'),
              const SizedBox(height: 8),
              Text('Prioritas: ${_getPriorityText(order['priority'])}'),
              const SizedBox(height: 8),
              Text('Estimasi Waktu: ${order['estimated_time']}'),
              const SizedBox(height: 8),
              Text(
                'Catatan Teknisi: ${order['technician_notes'] ?? 'Tidak ada'}',
              ),
              const SizedBox(height: 8),
              Text(
                'Dibuat: ${order['created_at'] != null ? DateTime.parse(order['created_at']).toLocal().toString() : 'N/A'}',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _startWork(order);
            },
            child: const Text('Mulai Kerja'),
          ),
        ],
      ),
    );
  }
}
