import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/utils/network_config.dart';

class StockWarehousePage extends ConsumerStatefulWidget {
  const StockWarehousePage({super.key});

  @override
  ConsumerState<StockWarehousePage> createState() => _StockWarehousePageState();
}

class _StockWarehousePageState extends ConsumerState<StockWarehousePage> {
  bool _isLoading = true;
  String _error = '';
  List<dynamic> _items = [];
  String _search = '';
  // Note: saving state is handled inside the add dialog to avoid
  // setState+Navigator.pop race conditions that can trigger framework asserts.

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _showAddStockDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final kodeBarangController = TextEditingController();
    final weightController = TextEditingController();
    final quantityController = TextEditingController(text: '1');
    final purityController = TextEditingController();

    String selectedKategori = 'PERHIASAN';
    String selectedJenis = '';
    String selectedTipe = 'BIASA';
    String selectedMaterial = 'EMAS';

    final kategoriOptions = ['PERHIASAN', 'LOGAM MULIA', 'AKSESORIES'];
    final Map<String, List<String>> jenisOptions = {
      'PERHIASAN': ['CINCIN', 'GELANG', 'KALUNG', 'ANTING', 'LIONTIN', 'BRO'],
      'LOGAM MULIA': ['ANTAM', 'UBS', 'BATANGAN'],
      'AKSESORIES': ['GELANG', 'KALUNG', 'ANTING', 'BRO'],
    };
    final tipeOptions = ['BIASA', 'GRESS'];
    final materialOptions = ['EMAS', 'PERAK', 'LAINNYA'];

    await showDialog<void>(
      context: context,
      builder: (context) {
        var isSaving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Tambah Stok Warehouse'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Nama Item',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Wajib diisi'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: kodeBarangController,
                          decoration: const InputDecoration(
                            labelText: 'Kode Barang',
                            helperText: 'Contoh: KB001, GOLD-001',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Wajib diisi'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedKategori,
                          decoration: const InputDecoration(
                            labelText: 'Kategori',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: kategoriOptions
                              .map(
                                (k) =>
                                    DropdownMenuItem(value: k, child: Text(k)),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() {
                              selectedKategori = value;
                              selectedJenis = '';
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedJenis.isEmpty ? null : selectedJenis,
                          decoration: const InputDecoration(
                            labelText: 'Jenis',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: (jenisOptions[selectedKategori] ?? const [])
                              .map(
                                (j) =>
                                    DropdownMenuItem(value: j, child: Text(j)),
                              )
                              .toList(),
                          onChanged: (value) {
                            setDialogState(() => selectedJenis = value ?? '');
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Jenis wajib dipilih';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedTipe,
                          decoration: const InputDecoration(
                            labelText: 'Tipe',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: tipeOptions
                              .map(
                                (t) =>
                                    DropdownMenuItem(value: t, child: Text(t)),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() => selectedTipe = value);
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: weightController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Berat (gram)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                validator: (v) {
                                  final parsed =
                                      double.tryParse((v ?? '').trim());
                                  if (parsed == null || parsed <= 0) {
                                    return 'Invalid';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: quantityController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Quantity',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                validator: (v) {
                                  final parsed = int.tryParse((v ?? '').trim());
                                  if (parsed == null || parsed <= 0) {
                                    return 'Invalid';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: selectedMaterial,
                                decoration: const InputDecoration(
                                  labelText: 'Material',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: materialOptions
                                    .map(
                                      (m) => DropdownMenuItem(
                                        value: m,
                                        child: Text(m),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setDialogState(() => selectedMaterial = value);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: purityController,
                                decoration: const InputDecoration(
                                  labelText: 'Kadar/Purity',
                                  helperText: 'Contoh: 75%, 22K, 99.99%',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (formKey.currentState?.validate() != true) return;
                          setDialogState(() => isSaving = true);
                          final ok = await _addStockItem(
                            name: nameController.text.trim(),
                            kodeBarang: kodeBarangController.text.trim(),
                            weight: double.parse(weightController.text.trim()),
                            quantity: int.parse(quantityController.text.trim()),
                            material: selectedMaterial,
                            purity: purityController.text.trim(),
                            kategori: selectedKategori.trim(),
                            jenis: selectedJenis.trim(),
                            tipe: selectedTipe.trim(),
                          );
                          if (!context.mounted) return;
                          if (ok) {
                            Navigator.pop(context);
                            return; // avoid setState after route pop
                          }
                          setDialogState(() => isSaving = false);
                        },
                  child: isSaving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    // Dispose controllers after the dialog route is fully removed from tree.
    // Disposing immediately after showDialog returns can still race with
    // transition/build callbacks on some devices and trigger "used after disposed".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      kodeBarangController.dispose();
      weightController.dispose();
      quantityController.dispose();
      purityController.dispose();
    });
  }

  Future<bool> _addStockItem({
    required String name,
    required String kodeBarang,
    required double weight,
    required int quantity,
    required String material,
    required String purity,
    required String kategori,
    required String jenis,
    required String tipe,
  }) async {
    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;

      final payload = <String, dynamic>{
        'name': name,
        // Keep both for compatibility: some clients/backends use either field.
        'item_code': kodeBarang,
        'kode_produk': kodeBarang,
        'weight': weight,
        'quantity': quantity,
        'status': 'ready',
        'branch_id': userState.branch,
        'source': 'manual_stockist',
        'kategori': kategori,
        'jenis': jenis,
        'tipe': tipe,
        'material': material,
        if (purity.isNotEmpty) 'purity': purity,
      };

      final resp = await http.post(
        Uri.parse('$baseUrl/items'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode(payload),
      );

      if (!mounted) return false;

      if (resp.statusCode == 201 || resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stok berhasil ditambahkan')),
        );
        await _loadItems();
        return true;
      } else {
        // Try to extract a meaningful error from backend
        String backendMsg = resp.body;
        try {
          final decoded = jsonDecode(resp.body);
          if (decoded is Map && decoded['error'] != null) {
            backendMsg = decoded['error'].toString();
          } else if (decoded is Map && decoded['detail'] != null) {
            backendMsg = decoded['detail'].toString();
          }
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menambah stok (${resp.statusCode}): $backendMsg'),
          ),
        );
        return false;
      }
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      return false;
    }
  }

  Future<void> _showRestockDialog(Map<String, dynamic> item) async {
    final formKey = GlobalKey<FormState>();
    final qtyController = TextEditingController(text: '1');

    final itemId = item['item_id'];
    final kode = (item['item_code'] ?? item['kode_produk'] ?? '').toString();
    final name = (item['name'] ?? '-').toString();

    if (itemId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item ID tidak ditemukan')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var isSaving = false;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Restock'),
              content: SizedBox(
                width: 420,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kode.isNotEmpty ? '$kode • $name' : name,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Qty tambah',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (v) {
                          final parsed = int.tryParse((v ?? '').trim());
                          if (parsed == null || parsed <= 0) return 'Invalid';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (formKey.currentState?.validate() != true) return;
                          setDialogState(() => isSaving = true);
                          final deltaQty = int.parse(qtyController.text.trim());
                          final ok = await _restockItem(
                            itemId: itemId,
                            deltaQty: deltaQty,
                          );
                          if (!dialogContext.mounted) return;
                          if (ok) {
                            Navigator.pop(dialogContext);
                            return;
                          }
                          setDialogState(() => isSaving = false);
                        },
                  child: isSaving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      qtyController.dispose();
    });
  }

  Future<bool> _restockItem({
    required dynamic itemId,
    required int deltaQty,
  }) async {
    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;
      final resp = await http.post(
        Uri.parse('$baseUrl/items/$itemId/restock'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode(<String, dynamic>{
          'delta_quantity': deltaQty,
          'branch_id': userState.branch,
        }),
      );

      if (!mounted) return false;

      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restock berhasil')),
        );
        await _loadItems();
        return true;
      }

      String backendMsg = resp.body;
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['error'] != null) {
          backendMsg = decoded['error'].toString();
        } else if (decoded is Map && decoded['detail'] != null) {
          backendMsg = decoded['detail'].toString();
        }
      } catch (_) {}

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal restock (${resp.statusCode}): $backendMsg'),
        ),
      );
      return false;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      return false;
    }
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;

      final uri = Uri.parse(
        '$baseUrl/items?branch_id=${userState.branch}&stock_type=inventory&limit=200',
      );
      final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
      if (resp.statusCode != 200) {
        setState(() {
          _error = 'Gagal memuat stok warehouse (${resp.statusCode})';
          _isLoading = false;
        });
        return;
      }

      final data = jsonDecode(resp.body);
      setState(() {
        _items = (data is List) ? data : <dynamic>[];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  List<dynamic> get _filteredItems {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((it) {
      final code = (it['item_code'] ?? it['kode_produk'] ?? '').toString();
      final name = (it['name'] ?? '').toString();
      return code.toLowerCase().contains(q) || name.toLowerCase().contains(q);
    }).toList();
  }

  Color _statusColor(String status) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Warehouse'),
        actions: [
          IconButton(
            tooltip: 'Tambah stok',
            onPressed: _showAddStockDialog,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadItems,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
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
                          onPressed: _loadItems,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Cari item_code / nama',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                    Expanded(
                      child: _filteredItems.isEmpty
                          ? const Center(child: Text('Stok kosong'))
                          : ListView.separated(
                              itemCount: _filteredItems.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = _filteredItems[index]
                                    as Map<String, dynamic>;
                                final kodeProduk =
                                    (item['kode_produk'] ?? item['item_code'] ?? '')
                                        .toString();
                                final name = (item['name'] ?? '-').toString();
                                final status = (item['status'] ?? '-').toString();
                                final weight = item['weight'];
                                final weightText = weight == null
                                    ? ''
                                    : (weight is num
                                        ? '${weight.toString()} g'
                                        : '$weight g');
                                final qtyRaw = item['quantity'] ?? item['qty'];
                                final qty = (qtyRaw is num)
                                    ? qtyRaw.toString()
                                    : (qtyRaw?.toString().trim().isNotEmpty == true)
                                        ? qtyRaw.toString()
                                        : '1';

                                return ListTile(
                                  title: Text(name),
                                  subtitle: Text(
                                    [
                                      if (kodeProduk.isNotEmpty) 'Kode: $kodeProduk',
                                      'Qty: $qty',
                                      if (weightText.isNotEmpty) weightText,
                                    ].join(' • '),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Chip(
                                        label: Text(status),
                                        side: BorderSide(
                                          color: _statusColor(status),
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        tooltip: 'Aksi',
                                        onSelected: (value) async {
                                          if (value == 'restock') {
                                            await _showRestockDialog(item);
                                          } else if (value == 'history') {
                                            await showModalBottomSheet<void>(
                                              context: context,
                                              isScrollControlled: true,
                                              useSafeArea: true,
                                              showDragHandle: true,
                                              builder: (ctx) => SizedBox(
                                                height:
                                                    MediaQuery.sizeOf(ctx)
                                                            .height *
                                                        0.68,
                                                child: _StockHistoryBottomSheet(
                                                  item: item,
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'history',
                                            child: ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              leading: Icon(Icons.history),
                                              title: Text('Riwayat stok'),
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'restock',
                                            child: ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              leading: Icon(Icons.add_box),
                                              title: Text('Restock'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _StockHistoryBottomSheet extends ConsumerStatefulWidget {
  const _StockHistoryBottomSheet({required this.item});

  final Map<String, dynamic> item;

  @override
  ConsumerState<_StockHistoryBottomSheet> createState() =>
      _StockHistoryBottomSheetState();
}

class _StockHistoryBottomSheetState
    extends ConsumerState<_StockHistoryBottomSheet> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final userState = ref.read(userStateProvider);
    final id = widget.item['item_id'];
    if (id == null) return [];
    final uri = Uri.parse(
      '${NetworkConfig.baseUrl}/stock-mutations?branch_id=${userState.branch}&item_id=$id&limit=100',
    );
    final r = await http.get(uri, headers: NetworkConfig.defaultHeaders);
    if (r.statusCode != 200) {
      throw Exception('Gagal memuat riwayat (${r.statusCode})');
    }
    final decoded = jsonDecode(r.body);
    if (decoded is! List) return [];
    return decoded
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static String _typeLabel(String? t) {
    switch ((t ?? '').toLowerCase()) {
      case 'in':
        return 'Masuk';
      case 'out':
        return 'Keluar';
      case 'transfer':
        return 'Transfer';
      case 'adjustment':
        return 'Koreksi';
      default:
        return t?.isNotEmpty == true ? t! : '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final kode =
        (widget.item['kode_produk'] ?? widget.item['item_code'] ?? '')
            .toString();
    final name = (widget.item['name'] ?? '-').toString();
    final subtitle = kode.isNotEmpty ? '$kode · $name' : name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Riwayat stok',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Tutup',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                );
              }
              final rows = snapshot.data ?? [];
              if (rows.isEmpty) {
                return const Center(
                  child: Text('Belum ada riwayat mutasi untuk item ini'),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                itemCount: rows.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1),
                itemBuilder: (context, i) {
                  final row = rows[i];
                  final ts = row['created_at'];
                  String dateStr = '-';
                  if (ts != null) {
                    try {
                      dateStr = DateFormat('dd MMM yyyy, HH:mm').format(
                        DateTime.parse(ts.toString()).toLocal(),
                      );
                    } catch (_) {
                      dateStr = ts.toString();
                    }
                  }
                  final type = _typeLabel(row['type']?.toString());
                  final qty = row['quantity'];
                  final prev = row['previous_stock'];
                  final cur = row['current_stock'];
                  final notes = (row['notes'] ?? '').toString().trim();
                  final by = (row['created_by_name'] ?? '').toString().trim();
                  final refType =
                      (row['reference_type'] ?? '').toString().trim();
                  final refId = row['reference_id'];

                  return ListTile(
                    dense: true,
                    title: Text(
                      '$type · qty ${qty ?? '-'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateStr,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                        if (prev != null || cur != null)
                          Text(
                            'Stok: ${prev ?? '?'} → ${cur ?? '?'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        if (refType.isNotEmpty || refId != null)
                          Text(
                            [
                              if (refType.isNotEmpty) 'Ref: $refType',
                              if (refId != null) '#$refId',
                            ].join(' '),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        if (notes.isNotEmpty)
                          Text(
                            notes,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        if (by.isNotEmpty)
                          Text(
                            'Oleh: $by',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

