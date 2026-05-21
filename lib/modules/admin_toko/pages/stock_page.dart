import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/modules/stockist/widgets/stock_inventory_grouped_table.dart';
import 'package:vanessa3/shared_widgets/stock_inventory_search_field.dart';
import 'package:vanessa3/shared_widgets/stock_status_filter_summary_header.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/stock_inventory_search.dart';
import 'package:vanessa3/utils/stock_item_qr_print.dart';
import 'package:vanessa3/utils/stock_inventory_report_print.dart';

class StockPage extends ConsumerStatefulWidget {
  const StockPage({super.key});

  @override
  ConsumerState<StockPage> createState() => _StockPageState();
}

class _StockPageState extends ConsumerState<StockPage> {
  final _searchCtrl = TextEditingController();
  List<dynamic> _items = [];
  bool _isLoading = true;
  String _error = '';
  String _selectedStatus = 'ready';
  String _search = '';

  String? _normalizePhotoUrl(dynamic raw) {
    final s = raw?.toString().trim();
    if (s == null || s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    if (s.startsWith('/')) return '${NetworkConfig.baseUrl}$s';
    return '${NetworkConfig.baseUrl}/uploads/$s';
  }

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
        var msg = 'Gagal memuat data stok: ${response.statusCode}';
        if (response.statusCode == 403) {
          msg =
              'Cabang tidak diizinkan. Ganti cabang lewat menu profil (switch cabang/role) lalu coba lagi.';
        }
        try {
          final err = jsonDecode(response.body) as Map;
          final d = (err['error'] ?? '').toString().trim();
          if (d.isNotEmpty) msg = d;
        } catch (_) {}
        setState(() {
          _error = msg;
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
    var list = _selectedStatus == 'all'
        ? List<dynamic>.from(_items)
        : _items
            .where(
              (item) => stockItemVisibleForStatusFilter(item, _selectedStatus),
            )
            .toList();
    if (_search.trim().isNotEmpty) {
      list = list
          .where((item) => stockInventoryItemMatchesQuery(item, _search))
          .toList();
    }
    return list;
  }

  void _onSearchChanged(String v) => setState(() => _search = v);

  Future<void> _printStockReport() async {
    final user = ref.read(userStateProvider);
    final branchId = user.branch.trim();
    final branchLabel = stockBranchDisplayName(
          branches: user.branches,
          branchId: branchId,
        ) ??
        branchId;
    await printStockInventoryReportPdf(
      context,
      branchLabel: branchLabel.isEmpty ? 'Cabang' : branchLabel,
      branchIdForLogo: branchId,
      selectedStatus: _selectedStatus,
      filteredItems: _filteredItems,
      searchQuery: _search,
    );
  }

  Future<void> _showAddStockDialog() async {
    final shelfContext = context;
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
                if (!formKey.currentState!.validate()) return;
                final created = await _addStockItem(
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
                if (!context.mounted) return;
                if (created != null) {
                  Navigator.of(context).pop();
                  if (shelfContext.mounted) {
                    await promptPrintStockItemLabel(
                      shelfContext,
                      item: created,
                      afterSave: true,
                    );
                  }
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _addStockItem({
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
        Map<String, dynamic>? created;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            created = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Stok berhasil ditambahkan')),
          );
        }
        _loadItems();
        return created;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal menambah stok: ${response.statusCode}'),
            ),
          );
        }
        return null;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stok Barang'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            onPressed: _isLoading || _error.isNotEmpty ? null : _printStockReport,
            tooltip: 'Cetak laporan stok',
          ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: StockStatusFilterSummaryHeader(
              selectedStatus: _selectedStatus,
              onStatusChanged: (v) => setState(() => _selectedStatus = v),
              summaryItems: _filteredItems,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: StockInventorySearchFieldStateful(
              controller: _searchCtrl,
              onQueryChanged: _onSearchChanged,
              enabled: !_isLoading && _error.isEmpty,
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
                    ? Center(
                        child: Text(
                          _search.trim().isNotEmpty
                              ? 'Tidak ada hasil untuk "${_search.trim()}"'
                              : 'Tidak ada data stok',
                        ),
                      )
                    : StockInventoryGroupedTable(
                        filteredItems: _filteredItems,
                        branchIdForMutations: ref.read(userStateProvider).branch,
                        branchDisplayNameForHistory: stockBranchDisplayName(
                          branches: ref.watch(userStateProvider).branches,
                          branchId: ref.watch(userStateProvider).branch,
                        ),
                        showStockistActions: false,
                        showReadOnlyHistory: true,
                        onOpenItemDetail: (Map<String, dynamic> item) {
                          _showItemDetails(context, item);
                        },
                      ),
          ),
        ],
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
                stockItemStatusLabel(
                  (item['status'] ?? 'unknown').toString(),
                ),
              ),
              _buildDetailRow('Kategori', item['kategori'] ?? '-'),
              _buildDetailRow('Jenis', item['jenis'] ?? '-'),
              _buildDetailRow('Tipe', item['tipe'] ?? '-'),
              if (_normalizePhotoUrl(item['photo_produk'] ?? item['photo_url']) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Center(
                    child: Image.network(
                      _normalizePhotoUrl(item['photo_produk'] ?? item['photo_url'])!,
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
