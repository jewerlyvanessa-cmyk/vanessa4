import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/stock_request_transfer.dart';
import 'package:vanessa3/utils/branch_types.dart';

/// Admin toko: buat transfer pending gudang → toko ini (ditandai di `notes` untuk stockist).
class RequestStockWarehousePage extends ConsumerStatefulWidget {
  const RequestStockWarehousePage({super.key});

  @override
  ConsumerState<RequestStockWarehousePage> createState() =>
      _RequestStockWarehousePageState();
}

class _RequestStockWarehousePageState
    extends ConsumerState<RequestStockWarehousePage> {
  List<dynamic> _branches = [];
  List<Map<String, dynamic>> _warehouseItems = [];
  bool _loadingBranches = true;
  bool _loadingItems = false;
  bool _submitting = false;
  String _error = '';
  String? _warehouseBranchId;
  Map<String, dynamic>? _selectedItem;
  final _qtyController = TextEditingController(text: '1');
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<http.Response> _fetchBranchesList(String baseUrl) async {
    final primary = await http.get(
      Uri.parse('$baseUrl/branches'),
      headers: NetworkConfig.defaultHeaders,
    );
    if (primary.statusCode == 200) return primary;
    final fallback = await http.get(
      Uri.parse('$baseUrl/api/branches'),
      headers: NetworkConfig.defaultHeaders,
    );
    if (fallback.statusCode == 200) return fallback;
    return primary;
  }

  Future<void> _loadBranches() async {
    setState(() {
      _loadingBranches = true;
      _error = '';
    });
    try {
      final user = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;
      final res = await _fetchBranchesList(baseUrl);
      if (res.statusCode != 200) {
        setState(() {
          _error = 'Gagal memuat cabang (${res.statusCode})';
          _loadingBranches = false;
        });
        return;
      }
      final decoded = jsonDecode(res.body);
      final list = (decoded is List ? decoded : const <dynamic>[])
          .whereType<Map>()
          .where((b) {
            final id = b['branch_id']?.toString();
            if (id == null || id == user.branch.toString()) return false;
            return branchTypeCanSupplyStockForTransfer(
              b['branch_type']?.toString(),
            );
          })
          .toList();
      if (!mounted) return;
      setState(() {
        _branches = list;
        _loadingBranches = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error: $e';
        _loadingBranches = false;
      });
    }
  }

  String _itemLabel(Map<String, dynamic> it) {
    final code = (it['item_code'] ?? it['kode_produk'] ?? '').toString();
    final name = (it['name'] ?? it['item_name'] ?? '').toString();
    if (code.isNotEmpty && name.isNotEmpty) return '$code - $name';
    return name.isNotEmpty ? name : code;
  }

  Future<void> _loadItemsForWarehouse(String warehouseId) async {
    setState(() {
      _loadingItems = true;
      _warehouseItems = [];
      _selectedItem = null;
      _error = '';
    });
    final baseUrl = NetworkConfig.baseUrl;
    Future<List<Map<String, dynamic>>> fetch(String url) async {
      final resp = await http.get(
        Uri.parse(url),
        headers: NetworkConfig.defaultHeaders,
      );
      if (resp.statusCode != 200) {
        throw Exception('Gagal memuat stok gudang (${resp.statusCode})');
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }

    try {
      final withStockType = await fetch(
        '$baseUrl/items?branch_id=$warehouseId&stock_type=inventory&limit=200',
      );
      final items =
          withStockType.isNotEmpty
              ? withStockType
              : await fetch('$baseUrl/items?branch_id=$warehouseId&limit=200');
      if (!mounted) return;
      setState(() {
        _warehouseItems = items;
        _loadingItems = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingItems = false;
      });
    }
  }

  Future<void> _submit() async {
    final warehouseId = _warehouseBranchId;
    final item = _selectedItem;
    final qty = int.tryParse(_qtyController.text.trim()) ?? 0;
    final user = ref.read(userStateProvider);
    final storeBranchId = user.branch.toString();

    if (warehouseId == null || warehouseId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih gudang pengirim')),
      );
      return;
    }
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih barang')),
      );
      return;
    }
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Qty harus lebih dari 0')),
      );
      return;
    }

    setState(() => _submitting = true);
    final baseUrl = NetworkConfig.baseUrl;
    final itemName = _itemLabel(item).trim();
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/transfers'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({
          'from_branch_id': warehouseId,
          'to_branch_id': storeBranchId,
          'item_name': itemName,
          'quantity': qty,
          'source_type': 'stok',
          'courier': 'Permintaan toko',
          'notes': buildStockRequestTransferNotes(_notesController.text),
          'created_by': user.userId,
        }),
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      if (resp.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permintaan terkirim. Stockist gudang dapat memproses di menu terkait.',
            ),
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal (${resp.statusCode}): ${resp.body}'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesan stok ke gudang'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang cabang',
            onPressed: _loadingBranches ? null : _loadBranches,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loadingBranches
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  Text(
                    'Toko Anda: cabang ${user.branch}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hanya cabang bertipe Gudang atau Pusat (HQ) yang tampil — atur di Superadmin → Manajemen cabang.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _warehouseBranchId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Gudang pengirim',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    hint: const Text('Pilih gudang'),
                    items:
                        _branches.map((b) {
                          final m = b as Map;
                          final id = m['branch_id'].toString();
                          final name = (m['name'] ?? id).toString();
                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                    onChanged: (v) {
                      setState(() {
                        _warehouseBranchId = v;
                        _selectedItem = null;
                      });
                      if (v != null) _loadItemsForWarehouse(v);
                    },
                  ),
                  if (_branches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Tidak ada cabang tipe Gudang atau Pusat selain toko ini. '
                        'Jalankan migrasi cabang (branch_type) dan set tipe di Superadmin.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (_warehouseBranchId != null) ...[
                    if (_loadingItems)
                      const LinearProgressIndicator()
                    else if (_warehouseItems.isEmpty)
                      const Text('Tidak ada stok di gudang ini untuk dipilih.')
                    else
                      Autocomplete<Map<String, dynamic>>(
                        key: ValueKey(_warehouseBranchId),
                        displayStringForOption: _itemLabel,
                        optionsBuilder: (textEditingValue) {
                          final q = textEditingValue.text.trim().toLowerCase();
                          if (q.isEmpty) {
                            return _warehouseItems.take(40);
                          }
                          return _warehouseItems
                              .where(
                                (it) =>
                                    _itemLabel(it).toLowerCase().contains(q),
                              )
                              .take(40);
                        },
                        onSelected: (it) {
                          setState(() => _selectedItem = it);
                        },
                        fieldViewBuilder: (
                          context,
                          textEditingController,
                          focusNode,
                          onFieldSubmitted,
                        ) {
                          return TextFormField(
                            controller: textEditingController,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'Barang (dari stok gudang)',
                              border: OutlineInputBorder(),
                              isDense: true,
                              hintText: 'Ketik untuk mencari',
                            ),
                            onChanged: (_) {
                              if (_selectedItem != null) {
                                setState(() => _selectedItem = null);
                              }
                            },
                          );
                        },
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _qtyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Jumlah',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Catatan (opsional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed:
                          _submitting ||
                              _loadingItems ||
                              _warehouseBranchId == null
                          ? null
                          : _submit,
                      icon:
                          _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send),
                      label: const Text('Kirim permintaan'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Permintaan muncul di gudang sebagai transfer keluar pending. '
                      'Stockist dapat menyetujui (stok terkirim) atau menolak.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
