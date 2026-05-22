import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/stock_request_transfer.dart';
import 'package:vanessa3/utils/branch_types.dart';
import 'package:vanessa3/utils/order_item_kategori_jenis.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

class _CatJenisLine {
  /// Selaras form order Jual (default kategori umum).
  String? kategori = orderItemKategoriOptions.first;
  String? jenis;
  final TextEditingController qty = TextEditingController(text: '1');

  void dispose() {
    qty.dispose();
  }
}

/// Admin toko: permintaan stok ke warehouse per **kategori + jenis + qty** (bukan pilih SKU).
class RequestStockWarehousePage extends ConsumerStatefulWidget {
  const RequestStockWarehousePage({super.key});

  @override
  ConsumerState<RequestStockWarehousePage> createState() =>
      _RequestStockWarehousePageState();
}

class _RequestStockWarehousePageState
    extends ConsumerState<RequestStockWarehousePage> {
  List<dynamic> _branches = [];
  final List<_CatJenisLine> _lines = [_CatJenisLine()];
  bool _loadingBranches = true;
  bool _submitting = false;
  String _error = '';
  String? _warehouseBranchId;
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<http.Response> _fetchBranchesList(String baseUrl) async {
    return http.get(
      Uri.parse('$baseUrl/branches'),
      headers: NetworkConfig.defaultHeaders,
    );
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
            return branchTypeIsWarehouse(
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

  void _addLine() {
    setState(() => _lines.add(_CatJenisLine()));
  }

  void _removeLine(int index) {
    if (_lines.length <= 1) return;
    setState(() {
      _lines[index].dispose();
      _lines.removeAt(index);
    });
  }

  Future<void> _submit() async {
    final warehouseId = _warehouseBranchId;
    final user = ref.read(userStateProvider);
    final storeBranchId = user.branch.toString();

    if (warehouseId == null || warehouseId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih warehouse pengirim')),
      );
      return;
    }

    final entries = <({String k, String j, int q})>[];
    for (final l in _lines) {
      final k = l.kategori?.trim() ?? '';
      final j = l.jenis?.trim() ?? '';
      final q = int.tryParse(l.qty.text.trim()) ?? 0;
      if (k.isEmpty || j.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Setiap baris: pilih kategori dan jenis'),
          ),
        );
        return;
      }
      if (!orderItemIsValidKategoriJenisPair(k, j)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kombinasi kategori dan jenis tidak valid'),
          ),
        );
        return;
      }
      if (q <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Qty harus lebih dari 0 di setiap baris')),
        );
        return;
      }
      entries.add((k: k, j: j, q: q));
    }

    setState(() => _submitting = true);
    final baseUrl = NetworkConfig.baseUrl;
    final userNotes = _notesController.text.trim();
    var ok = 0;
    String? lastErr;

    try {
      for (final e in entries) {
        final itemName = stockRequestItemNameFromCategoryJenis(
          kategori: e.k,
          jenis: e.j,
        );
        final notes = buildStockRequestNotesByCategory(
          kategori: e.k,
          jenis: e.j,
          userNotes: userNotes.isEmpty ? null : userNotes,
        );
        final resp = await http.post(
          Uri.parse('$baseUrl/transfers'),
          headers: NetworkConfig.defaultHeaders,
          body: jsonEncode({
            'from_branch_id': warehouseId,
            'to_branch_id': storeBranchId,
            'item_name': itemName,
            'quantity': e.q,
            'source_type': 'stok',
            'courier': 'Permintaan toko',
            'notes': notes,
            'created_by': user.userId,
          }),
        );
        if (resp.statusCode == 201) {
          ok++;
        } else {
          lastErr = '${resp.statusCode}: ${resp.body}';
          break;
        }
      }

      if (!mounted) return;
      setState(() => _submitting = false);

      if (ok == entries.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok == 1 ? 'Permintaan terkirim.' : '$ok permintaan terkirim.',
            ),
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lastErr != null
                  ? 'Gagal setelah $ok sukses: $lastErr'
                  : 'Gagal mengirim permintaan',
            ),
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesan stok ke warehouse'),
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
              primary: false,
              physics: ResponsiveLayout.scrollPhysics,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: ResponsiveLayout.safeScrollPadding(context),
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
                    'Kategori & jenis mengikuti form order Jual (CS). '
                    'Hanya cabang bertipe warehouse yang tampil — atur di Superadmin.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _warehouseBranchId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Warehouse pengirim',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    hint: const Text('Pilih warehouse'),
                    items: _branches.map((b) {
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
                      setState(() => _warehouseBranchId = v);
                    },
                  ),
                  if (_branches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Tidak ada cabang tipe warehouse selain toko ini. '
                        'Jalankan migrasi cabang (branch_type) dan set tipe di Superadmin.',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.tertiary,
                        ),
                      ),
                    ),
                  if (_warehouseBranchId != null) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text(
                          'Detail permintaan',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _addLine,
                          icon: const Icon(Icons.add, size: 20),
                          label: const Text('Baris'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(_lines.length, (index) {
                      final line = _lines[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Baris ${index + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_lines.length > 1)
                                    IconButton(
                                      tooltip: 'Hapus baris',
                                      icon: Icon(
                                        Icons.close,
                                        color: cs.error,
                                        size: 20,
                                      ),
                                      onPressed: () => _removeLine(index),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                key: ValueKey('kat-$index-${line.kategori}'),
                                initialValue: line.kategori,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Kategori',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: orderItemKategoriOptions
                                    .map(
                                      (k) => DropdownMenuItem<String>(
                                        value: k,
                                        child: Text(k),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) {
                                  setState(() {
                                    line.kategori = v;
                                    line.jenis = null;
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                key: ValueKey('jen-$index-${line.kategori}-${line.jenis}'),
                                initialValue: line.jenis,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Jenis',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                hint: const Text('Pilih jenis'),
                                items: orderItemJenisOptionsForKategori(
                                  line.kategori ?? '',
                                )
                                    .map(
                                      (j) => DropdownMenuItem<String>(
                                        value: j,
                                        child: Text(j),
                                      ),
                                    )
                                    .toList(),
                                onChanged: line.kategori == null
                                    ? null
                                    : (v) {
                                        setState(() => line.jenis = v);
                                      },
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: line.qty,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Qty',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Catatan (opsional, sama untuk semua baris)',
                        border: OutlineInputBorder(),
                        isDense: true,
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed:
                          _submitting || _warehouseBranchId == null
                          ? null
                          : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: const Text('Kirim permintaan'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Stockist melihat permintaan di warehouse. Menyetujui hanya mengubah status '
                      '(tanpa mutasi stok otomatis di sistem untuk permintaan per kategori/jenis); '
                      'pencatatan fisik dilakukan di warehouse.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
