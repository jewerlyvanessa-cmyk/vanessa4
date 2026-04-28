import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/utils/network_config.dart';

class StockPage extends ConsumerStatefulWidget {
  const StockPage({super.key});

  @override
  ConsumerState<StockPage> createState() => _StockPageState();
}

class _StockPageState extends ConsumerState<StockPage> {
  List<dynamic> _items = [];
  bool _isLoading = true;
  String _error = '';
  String _selectedStatus = 'all'; // all, ready, reserved, sold, buyback

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;

      final response = await http.get(
        Uri.parse('$baseUrl/items?branch_id=${userState.branch}'),
        headers: NetworkConfig.defaultHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _items = data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Gagal memuat data stok: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  List<dynamic> get _filteredItems {
    if (_selectedStatus == 'all') {
      return _items;
    }
    return _items.where((item) => item['status'] == _selectedStatus).toList();
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'ready':
        return Colors.green;
      case 'reserved':
        return Colors.orange;
      case 'sold':
        return Colors.red;
      case 'buyback':
        return Colors.blue;
      case 'on-service':
        return Colors.purple;
      case 'on-custom':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'ready':
        return 'Ready';
      case 'reserved':
        return 'Reserved';
      case 'sold':
        return 'Sold';
      case 'buyback':
        return 'Buyback';
      case 'on-service':
        return 'On Service';
      case 'on-custom':
        return 'On Custom';
      default:
        return status;
    }
  }

  double _calculateTotalWeight(String statusFilter) {
    double totalWeight = 0.0;
    for (var item in _items) {
      if (statusFilter == 'all' || item['status'] == statusFilter) {
        final rawWeight = item['weight'];
        final rawQty = item['quantity'];

        final weightPerItem = rawWeight is num
            ? rawWeight.toDouble()
            : double.tryParse(rawWeight?.toString() ?? '') ?? 0.0;

        final qty = rawQty is int
            ? rawQty
            : int.tryParse(rawQty?.toString() ?? '') ?? 1;

        if (weightPerItem > 0 && qty > 0) {
          totalWeight += weightPerItem * qty;
        }
      }
    }
    return totalWeight;
  }

  Future<void> _showAddStockDialog() async {
    final formKey = GlobalKey<FormState>();

    // Controllers
    final nameController = TextEditingController();
    final kodeBarangController = TextEditingController();
    final weightController = TextEditingController();
    final purityController = TextEditingController();
    final quantityController = TextEditingController(text: '1');

    String selectedKategori = 'PERHIASAN';
    String selectedJenis = '';
    String selectedTipe = 'BIASA';
    String selectedMaterial = 'EMAS';

    // Kategori options
    final kategoriOptions = ['PERHIASAN', 'LOGAM MULIA', 'AKSESORIES'];

    // Jenis options berdasarkan kategori
    Map<String, List<String>> jenisOptions = {
      'PERHIASAN': ['CINCIN', 'GELANG', 'KALUNG', 'ANTING', 'LIONTIN', 'BRO'],
      'LOGAM MULIA': ['ANTAM', 'UBS', 'BATANGAN'],
      'AKSESORIES': ['GELANG', 'KALUNG', 'ANTING', 'BRO'],
    };

    // Tipe options
    final tipeOptions = ['BIASA', 'GRESS'];
    final materialOptions = ['EMAS', 'PERAK', 'LAINNYA'];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Tambah Stok Barang'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nama Item
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nama Item',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Nama item wajib diisi';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Kode Barang
                  TextFormField(
                    controller: kodeBarangController,
                    decoration: const InputDecoration(
                      labelText: 'Kode Barang',
                      border: OutlineInputBorder(),
                      hintText: 'Contoh: KB001, GOLD-001',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Kode barang wajib diisi';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Kategori
                  DropdownButtonFormField<String>(
                    initialValue: selectedKategori,
                    decoration: const InputDecoration(
                      labelText: 'Kategori',
                      border: OutlineInputBorder(),
                    ),
                    items: kategoriOptions.map((kategori) {
                      return DropdownMenuItem(
                        value: kategori,
                        child: Text(kategori),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedKategori = value!;
                        selectedJenis = ''; // Reset jenis saat kategori berubah
                      });
                    },
                  ),
                  const SizedBox(height: 12),

                  // Jenis
                  DropdownButtonFormField<String>(
                    initialValue: selectedJenis.isEmpty ? null : selectedJenis,
                    decoration: const InputDecoration(
                      labelText: 'Jenis',
                      border: OutlineInputBorder(),
                    ),
                    items: jenisOptions[selectedKategori]?.map((jenis) {
                      return DropdownMenuItem(value: jenis, child: Text(jenis));
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedJenis = value!;
                      });
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Jenis wajib dipilih';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Tipe
                  DropdownButtonFormField<String>(
                    initialValue: selectedTipe,
                    decoration: const InputDecoration(
                      labelText: 'Tipe',
                      border: OutlineInputBorder(),
                    ),
                    items: tipeOptions.map((tipe) {
                      return DropdownMenuItem(value: tipe, child: Text(tipe));
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedTipe = value!;
                      });
                    },
                  ),
                  const SizedBox(height: 12),

                  // Berat
                  TextFormField(
                    controller: weightController,
                    decoration: const InputDecoration(
                      labelText: 'Berat (gram)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Berat wajib diisi';
                      }
                      final weight = double.tryParse(value);
                      if (weight == null || weight <= 0) {
                        return 'Berat harus angka positif';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Quantity
                  TextFormField(
                    controller: quantityController,
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Quantity wajib diisi';
                      }
                      final qty = int.tryParse(value);
                      if (qty == null || qty <= 0) {
                        return 'Quantity harus angka positif';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Material
                  DropdownButtonFormField<String>(
                    initialValue: selectedMaterial,
                    decoration: const InputDecoration(
                      labelText: 'Material',
                      border: OutlineInputBorder(),
                    ),
                    items: materialOptions.map((m) {
                      return DropdownMenuItem(value: m, child: Text(m));
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedMaterial = value ?? 'EMAS';
                      });
                    },
                  ),
                  const SizedBox(height: 12),

                  // Purity/Kadar
                  TextFormField(
                    controller: purityController,
                    decoration: const InputDecoration(
                      labelText: 'Kadar/Purity',
                      border: OutlineInputBorder(),
                      hintText: 'Contoh: 75%, 22K, 99.99%',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  await _addStockItem(
                    name: nameController.text,
                    kodeBarang: kodeBarangController.text,
                    kategori: selectedKategori,
                    jenis: selectedJenis,
                    tipe: selectedTipe,
                    weight: double.parse(weightController.text),
                    quantity: int.parse(quantityController.text),
                    material: selectedMaterial,
                    purity: purityController.text,
                  );
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _addStockItem({
    required String name,
    required String kodeBarang,
    required String kategori,
    required String jenis,
    required String tipe,
    required double weight,
    required int quantity,
    required String material,
    required String purity,
  }) async {
    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;

      final response = await http.post(
        Uri.parse('$baseUrl/items'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({
          'name': name,
          'kode_produk': kodeBarang,
          'kategori': kategori,
          'jenis': jenis,
          'tipe': tipe,
          'weight': weight,
          'quantity': quantity,
          'material': material,
          'purity': purity,
          'status': 'ready',
          'branch_id': userState.branch,
          'source': 'manual_admin',
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Stok berhasil ditambahkan')),
          );
          // Close dialog after showing success message
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) Navigator.of(context).pop();
          });
        }
        _loadItems(); // Refresh data
        return true;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal menambah stok: ${response.statusCode}'),
            ),
          );
        }
        return false;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stok Barang'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddStockDialog,
            tooltip: 'Tambah Stok',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadItems,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Status
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Text('Filter Status: '),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedStatus,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text('Semua Status'),
                      ),
                      DropdownMenuItem(value: 'ready', child: Text('Ready')),
                      DropdownMenuItem(
                        value: 'reserved',
                        child: Text('Reserved'),
                      ),
                      DropdownMenuItem(value: 'sold', child: Text('Sold')),
                      DropdownMenuItem(
                        value: 'buyback',
                        child: Text('Buyback'),
                      ),
                      DropdownMenuItem(
                        value: 'on-service',
                        child: Text('On Service'),
                      ),
                      DropdownMenuItem(
                        value: 'on-custom',
                        child: Text('On Custom'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedStatus = value!;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          // Summary Cards - JUMLAH STOK
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.grey[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📊 JUMLAH STOK',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        'Total Item',
                        _items.length.toString(),
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildSummaryCard(
                        'Ready Dijual',
                        _items
                            .where((item) => item['status'] == 'ready')
                            .length
                            .toString(),
                        Colors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildSummaryCard(
                        'Dipesan',
                        _items
                            .where((item) => item['status'] == 'reserved')
                            .length
                            .toString(),
                        Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        'Berat Ready',
                        '${_calculateTotalWeight('ready').toStringAsFixed(2)}g',
                        Colors.teal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildSummaryCard(
                        'Berat Total',
                        '${_calculateTotalWeight('all').toStringAsFixed(2)}g',
                        Colors.purple,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildSummaryCard(
                        'Terjual',
                        _items
                            .where((item) => item['status'] == 'sold')
                            .length
                            .toString(),
                        Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Items List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadItems,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  )
                : _filteredItems.isEmpty
                ? const Center(child: Text('Tidak ada data stok'))
                : ListView.builder(
                    itemCount: _filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = _filteredItems[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading:
                              item['photo_url'] != null &&
                                  item['photo_url'].isNotEmpty
                              ? CircleAvatar(
                                  backgroundImage: NetworkImage(
                                    item['photo_url'],
                                  ),
                                  onBackgroundImageError:
                                      (exception, stackTrace) =>
                                          const Icon(Icons.inventory),
                                )
                              : const CircleAvatar(
                                  child: Icon(Icons.inventory),
                                ),
                          title: Text(item['name'] ?? 'Unknown'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ID: ${item['item_id']}'),
                              if (item['kode_produk'] != null &&
                                  item['kode_produk'].isNotEmpty)
                                Text('Kode: ${item['kode_produk']}'),
                              Text('Berat: ${item['weight'] ?? 0} gram'),
                              Text('Qty: ${item['quantity'] ?? 1}'),
                              Text('Material: ${item['material'] ?? '-'}'),
                              Text('Kadar: ${item['purity'] ?? '-'}'),
                            ],
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _getStatusColor(
                                item['status'] ?? 'unknown',
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _getStatusText(item['status'] ?? 'unknown'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          onTap: () {
                            // Show item details
                            _showItemDetails(context, item);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              value,
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

  void _showItemDetails(BuildContext context, dynamic item) {
    final rawWeight = item['weight'];
    final rawQty = item['quantity'];
    final weightPerItem = rawWeight is num
        ? rawWeight.toDouble()
        : double.tryParse(rawWeight?.toString() ?? '') ?? 0.0;
    final qty = rawQty is int ? rawQty : int.tryParse(rawQty?.toString() ?? '') ?? 1;
    final totalWeight = weightPerItem * (qty <= 0 ? 1 : qty);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item['name'] ?? 'Detail Item'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('ID Item', item['item_id'].toString()),
              _buildDetailRow('Nama', item['name'] ?? '-'),
              if (item['kode_produk'] != null && item['kode_produk'].isNotEmpty)
                _buildDetailRow('Kode Barang', item['kode_produk']),
              _buildDetailRow('Berat / pcs', '${weightPerItem.toStringAsFixed(2)} gram'),
              _buildDetailRow('Quantity', '${item['quantity'] ?? 1}'),
              _buildDetailRow('Berat total', '${totalWeight.toStringAsFixed(2)} gram'),
              _buildDetailRow('Material', item['material'] ?? '-'),
              _buildDetailRow('Kadar', item['purity'] ?? '-'),
              _buildDetailRow(
                'Status',
                _getStatusText(item['status'] ?? 'unknown'),
              ),
              _buildDetailRow('Kategori', item['kategori'] ?? '-'),
              _buildDetailRow('Jenis', item['jenis'] ?? '-'),
              _buildDetailRow('Tipe', item['tipe'] ?? '-'),
              if (item['photo_url'] != null && item['photo_url'].isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Center(
                    child: Image.network(
                      item['photo_url'],
                      height: 150,
                      width: 150,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.broken_image, size: 100),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
