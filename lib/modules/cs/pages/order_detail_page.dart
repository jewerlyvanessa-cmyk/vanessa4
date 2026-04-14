import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'faktur_page.dart';
import 'package:vanessa3/utils/network_config.dart';

class OrderDetailPage extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;

  const OrderDetailPage({super.key, required this.order});

  @override
  ConsumerState<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends ConsumerState<OrderDetailPage> {
  Map<String, dynamic>? _orderDetails;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrderDetails();
  }

  Future<void> _loadOrderDetails() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // For now, use the order data passed from the list
      // In the future, this could fetch detailed order data from API
      await Future.delayed(
        const Duration(milliseconds: 500),
      ); // Simulate API call

      setState(() {
        _orderDetails = widget.order;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Color _getOrderTypeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'jual':
        return Colors.orange;
      case 'buyback':
        return Colors.green;
      case 'service':
        return Colors.blue;
      case 'custom':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getOrderTypeIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'jual':
        return Icons.shopping_cart;
      case 'buyback':
        return Icons.replay;
      case 'service':
        return Icons.build;
      case 'custom':
        return Icons.design_services;
      default:
        return Icons.receipt;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status?.toLowerCase()) {
      case 'draft':
        return 'Draft';
      case 'reserved':
        return 'Reserved';
      case 'sold':
        return 'Terjual';
      case 'buyback':
        return 'Buyback';
      case 'on-service':
        return 'Sedang Service';
      case 'production':
        return 'Produksi';
      case 'completed':
        return 'Selesai';
      case 'cancelled':
        return 'Dibatalkan';
      default:
        return status ?? 'Unknown';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'draft':
        return Colors.grey;
      case 'reserved':
        return Colors.blue;
      case 'sold':
        return Colors.green;
      case 'buyback':
        return Colors.teal;
      case 'on-service':
        return Colors.orange;
      case 'production':
        return Colors.purple;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Order #${widget.order['order_id'] ?? 'N/A'}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrderDetails,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error: $_error',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadOrderDetails,
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            )
          : _buildOrderDetailContent(),
    );
  }

  Widget _buildOrderDetailContent() {
    final order = _orderDetails ?? widget.order;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order Header Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _getOrderTypeColor(order['order_type']),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getOrderTypeIcon(order['order_type']),
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Order #${order['order_id'] ?? 'N/A'}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${order['order_type'] ?? 'Unknown'}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(order['status']),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _getStatusLabel(order['status']),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Customer Information
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Informasi Pelanggan',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('Nama', order['customer_name'] ?? 'N/A'),
                  _buildInfoRow(
                    'ID Pelanggan',
                    order['customer_id']?.toString() ?? 'N/A',
                  ),
                  if (order['customer_phone'] != null)
                    _buildInfoRow('Telepon', order['customer_phone']),
                  if (order['customer_email'] != null)
                    _buildInfoRow('Email', order['customer_email']),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Order Information
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Informasi Order',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('Tanggal Dibuat', order['created_at'] ?? 'N/A'),
                  _buildInfoRow('Tanggal Update', order['updated_at'] ?? 'N/A'),
                  if (order['branch_name'] != null)
                    _buildInfoRow('Cabang', order['branch_name']),
                  if (order['notes'] != null &&
                      order['notes'].toString().isNotEmpty)
                    _buildInfoRow('Catatan', order['notes']),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Items Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Item Order',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (order['items'] != null &&
                      (order['items'] as List).isNotEmpty) ...[
                    ...(order['items'] as List).map(
                      (item) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item['nama_item'] ?? 'Unknown Item',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Text(
                                  item['total'] != null
                                      ? 'Rp ${item['total'].toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}'
                                      : 'Rp 0',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 16,
                              runSpacing: 6,
                              children: [
                                if (item['berat'] != null &&
                                    double.tryParse(item['berat'].toString()) !=
                                        null &&
                                    double.parse(item['berat'].toString()) > 0)
                                  Text(
                                    'Berat: ${item['berat']}g',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                if (item['harga_per_gram'] != null &&
                                    double.tryParse(
                                          item['harga_per_gram'].toString(),
                                        ) !=
                                        null &&
                                    double.parse(
                                          item['harga_per_gram'].toString(),
                                        ) >
                                        0)
                                  Text(
                                    'Harga/g: Rp ${item['harga_per_gram'].toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                if (item['kategori'] != null)
                                  Text(
                                    'Kategori: ${item['kategori']}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                if (item['jenis'] != null)
                                  Text(
                                    'Jenis: ${item['jenis']}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                if (item['tipe'] != null)
                                  Text(
                                    'Tipe Barang: ${item['tipe']}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                if (item['qty'] != null &&
                                    int.tryParse(item['qty'].toString()) !=
                                        null &&
                                    int.parse(item['qty'].toString()) > 0)
                                  Text(
                                    'Qty: ${item['qty']}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    const Center(
                      child: Text(
                        'Tidak ada detail item untuk order ini',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Total Amount
          if (order['total_amount'] != null)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Amount',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Rp ${order['total_amount'].toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 24),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showEditOrderDialog,
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit Order'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FakturPage(
                          orderData: _orderDetails ?? widget.order,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.print),
                  label: const Text('Cetak Faktur'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showEditOrderDialog() {
    final order = _orderDetails ?? widget.order;
    final statusController = TextEditingController(text: order['status'] ?? '');
    final notesController = TextEditingController(text: order['notes'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Order'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: order['status'],
                decoration: const InputDecoration(
                  labelText: 'Status Order',
                  border: OutlineInputBorder(),
                ),
                items:
                    [
                      'draft',
                      'reserved',
                      'sold',
                      'buyback',
                      'on-service',
                      'production',
                      'completed',
                      'cancelled',
                    ].map((status) {
                      return DropdownMenuItem(
                        value: status,
                        child: Text(_getStatusLabel(status)),
                      );
                    }).toList(),
                onChanged: (value) {
                  statusController.text = value ?? '';
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Catatan',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Store messenger before async operation
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);

              try {
                // Get the current order data
                final orderId = order['order_id'];
                final baseUrl = NetworkConfig.baseUrl;

                // Prepare the update data
                final updateData = {
                  'status': statusController.text,
                  // Note: The backend doesn't currently support notes field
                  // We'll store it locally for now
                };

                // Make API call to update order
                final response = await http.put(
                  Uri.parse('$baseUrl/orders/$orderId'),
                  headers: NetworkConfig.defaultHeaders,
                  body: jsonEncode(updateData),
                );

                if (response.statusCode == 200) {
                  // Update local state with the response
                  final updatedOrder = jsonDecode(response.body);
                  if (mounted) {
                    setState(() {
                      _orderDetails = {
                        ...order,
                        'status':
                            updatedOrder['status'] ?? statusController.text,
                        'notes': notesController.text, // Store notes locally
                        'updated_at': DateTime.now().toIso8601String(),
                      };
                    });
                  }

                  navigator.pop();

                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Order berhasil diperbarui'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  throw Exception(
                    'Failed to update order: ${response.statusCode}',
                  );
                }
              } catch (e) {
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Gagal memperbarui order: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
