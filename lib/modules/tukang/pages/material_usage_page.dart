import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/main.dart';

class MaterialUsagePage extends ConsumerStatefulWidget {
  const MaterialUsagePage({super.key});

  @override
  ConsumerState<MaterialUsagePage> createState() => _MaterialUsagePageState();
}

class _MaterialUsagePageState extends ConsumerState<MaterialUsagePage> {
  List<Map<String, dynamic>> _workQueue = [];
  List<Map<String, dynamic>> _materialStock = [];
  bool _isLoading = true;
  String? _error;

  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();

  Map<String, dynamic>? _selectedWork;
  Map<String, dynamic>? _selectedMaterial;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userState = ref.read(userStateProvider);

      final results = await Future.wait([
        ApiService.getWorkQueue(userState.userId.toString(), userState.branch),
        ApiService.getMaterialStock(userState.branch),
      ]);

      setState(() {
        _workQueue = results[0];
        _materialStock = results[1];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _recordMaterialUsage() async {
    if (_selectedWork == null || _selectedMaterial == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih pekerjaan dan material terlebih dahulu'),
        ),
      );
      return;
    }

    final quantity = double.tryParse(_quantityController.text);
    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan jumlah yang valid')),
      );
      return;
    }

    try {
      final userState = ref.read(userStateProvider);
      await ApiService.updateMaterialStock(
        _selectedMaterial!['item_id'],
        -quantity, // Negative for usage
        userState.userId.toString(),
        notes:
            'Digunakan untuk Order #${_selectedWork!['order_id']} - ${_notesController.text}',
      );

      // Reset form
      setState(() {
        _selectedWork = null;
        _selectedMaterial = null;
      });
      _quantityController.clear();
      _notesController.clear();

      // Reload data
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Penggunaan material berhasil dicatat')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  void _showMaterialUsageDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Catat Penggunaan Material'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Work Selection
                DropdownButtonFormField<Map<String, dynamic>>(
                  initialValue: _selectedWork,
                  decoration: const InputDecoration(
                    labelText: 'Pilih Pekerjaan',
                  ),
                  items: _workQueue.map((work) {
                    return DropdownMenuItem(
                      value: work,
                      child: Text(
                        'Order #${work['order_id']} - ${work['item_name']}',
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedWork = value;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Material Selection
                DropdownButtonFormField<Map<String, dynamic>>(
                  initialValue: _selectedMaterial,
                  decoration: const InputDecoration(
                    labelText: 'Pilih Material',
                  ),
                  items: _materialStock.map((material) {
                    return DropdownMenuItem(
                      value: material,
                      child: Text(
                        '${material['item_name']} (${material['quantity']} ${material['unit'] ?? 'pcs'} tersedia)',
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedMaterial = value;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Quantity Input
                TextField(
                  controller: _quantityController,
                  decoration: InputDecoration(
                    labelText: 'Jumlah Digunakan',
                    suffixText: _selectedMaterial?['unit'] ?? 'pcs',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),

                // Notes
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (Opsional)',
                    hintText: 'Tambahkan catatan penggunaan...',
                  ),
                  maxLines: 2,
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
              onPressed: () {
                Navigator.of(context).pop();
                _recordMaterialUsage();
              },
              child: const Text('Catat'),
            ),
          ],
        ),
      ),
    );
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
        title: const Text('Penggunaan Material'),
      ),
      body: Column(
        children: [
          // Quick Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ElevatedButton.icon(
              onPressed: _showMaterialUsageDialog,
              icon: const Icon(Icons.add),
              label: const Text('Catat Penggunaan Material'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),

          // Content Area
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Error: $_error'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadData,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  )
                : DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        const TabBar(
                          tabs: [
                            Tab(text: 'Pekerjaan Aktif'),
                            Tab(text: 'Stok Material'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              // Active Work Tab
                              _workQueue.isEmpty
                                  ? const Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.assignment,
                                            size: 48,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(height: 16),
                                          Text('Tidak ada pekerjaan aktif'),
                                        ],
                                      ),
                                    )
                                  : RefreshIndicator(
                                      onRefresh: _loadData,
                                      child: ListView.builder(
                                        padding: const EdgeInsets.all(16.0),
                                        itemCount: _workQueue.length,
                                        itemBuilder: (context, index) {
                                          final work = _workQueue[index];
                                          return Card(
                                            margin: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            child: ListTile(
                                              leading: CircleAvatar(
                                                backgroundColor:
                                                    _getStatusColor(
                                                      work['status'],
                                                    ),
                                                child: Icon(
                                                  _getStatusIcon(
                                                    work['status'],
                                                  ),
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                              ),
                                              title: Text(
                                                'Order #${work['order_id']}',
                                              ),
                                              subtitle: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${work['item_name']} (${work['item_type']})',
                                                  ),
                                                  Text(
                                                    'Pelanggan: ${work['customer_name']}',
                                                  ),
                                                  Text(
                                                    'Status: ${_getStatusText(work['status'])}',
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),

                              // Material Stock Tab
                              _materialStock.isEmpty
                                  ? const Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.inventory,
                                            size: 48,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(height: 16),
                                          Text('Tidak ada stok material'),
                                        ],
                                      ),
                                    )
                                  : RefreshIndicator(
                                      onRefresh: _loadData,
                                      child: ListView.builder(
                                        padding: const EdgeInsets.all(16.0),
                                        itemCount: _materialStock.length,
                                        itemBuilder: (context, index) {
                                          final material =
                                              _materialStock[index];
                                          return Card(
                                            margin: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            child: ListTile(
                                              leading: CircleAvatar(
                                                backgroundColor: Colors.blue,
                                                child: const Icon(
                                                  Icons.inventory,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                              ),
                                              title: Text(
                                                material['item_name'],
                                              ),
                                              subtitle: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Tipe: ${material['item_type']}',
                                                  ),
                                                  Text(
                                                    'Stok: ${material['quantity']} ${material['unit'] ?? 'pcs'}',
                                                  ),
                                                  Text(
                                                    'Material: ${material['material_type'] ?? 'N/A'}',
                                                  ),
                                                ],
                                              ),
                                              trailing: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      (material['quantity']
                                                              as num) >
                                                          10
                                                      ? Colors.green
                                                      : Colors.orange,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  material['quantity'] > 10
                                                      ? 'Tersedia'
                                                      : 'Terbatas',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Menunggu';
      case 'in_progress':
        return 'Dalam Proses';
      case 'completed':
        return 'Selesai';
      case 'cancelled':
        return 'Dibatalkan';
      default:
        return 'Unknown';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.schedule;
      case 'in_progress':
        return Icons.engineering;
      case 'completed':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }
}
