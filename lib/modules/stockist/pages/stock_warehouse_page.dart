import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/modules/stockist/widgets/stock_inventory_grouped_table.dart';
import 'package:vanessa3/modules/stockist/widgets/stock_jenis_two_step_panel.dart';
import 'package:vanessa3/shared_widgets/stock_status_filter_summary_header.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/stock_item_qr_print.dart';

/// One logical row from bulk paste: `kode,nama,berat,qty,kadar`.
class _BulkStockLine {
  const _BulkStockLine({
    required this.displayLine,
    required this.kode,
    required this.nama,
    required this.berat,
    required this.qty,
    required this.purity,
  });

  final int displayLine;
  final String kode;
  final String nama;
  final double berat;
  final int qty;
  final String purity;
}

List<_BulkStockLine> _parseBulkStockLines(String raw) {
  final out = <_BulkStockLine>[];
  final lines = raw.split(RegExp(r'\r?\n'));
  var lineNo = 0;
  for (final rawLine in lines) {
    lineNo++;
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.contains(';')
        ? line.split(';').map((s) => s.trim()).toList()
        : line.split(',').map((s) => s.trim()).toList();
    if (parts.length < 5) {
      throw FormatException(
        'Baris $lineNo: butuh 5 kolom — kode, nama, berat, qty, kadar '
        '(pisah koma atau titik koma; jika nama mengandung koma gunakan titik koma).',
      );
    }
    final kode = parts[0];
    final nama = parts[1];
    final berat = double.tryParse(parts[2].replaceAll(',', '.'));
    final qty = int.tryParse(parts[3]);
    final purity = parts[4].trim();
    if (kode.isEmpty) {
      throw FormatException('Baris $lineNo: kode kosong.');
    }
    if (nama.isEmpty) {
      throw FormatException('Baris $lineNo: nama kosong.');
    }
    if (berat == null || berat <= 0) {
      throw FormatException('Baris $lineNo: berat tidak valid.');
    }
    if (qty == null || qty <= 0) {
      throw FormatException('Baris $lineNo: qty tidak valid.');
    }
    if (purity.isEmpty) {
      throw FormatException('Baris $lineNo: kadar kosong.');
    }
    out.add(
      _BulkStockLine(
        displayLine: lineNo,
        kode: kode,
        nama: nama,
        berat: berat,
        qty: qty,
        purity: purity,
      ),
    );
  }
  if (out.isEmpty) {
    throw const FormatException('Tidak ada baris data (kosong atau hanya komentar #).');
  }
  return out;
}

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
  String _selectedStatus = 'all';
  /// `null` = hanya tampilkan daftar jenis; non-null = detail stok untuk jenis itu.
  String? _jenisDetailFocus;
  // Note: saving state is handled inside the add dialog to avoid
  // setState+Navigator.pop race conditions that can trigger framework asserts.

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _showAddStockDialog() async {
    final shelfContext = context;
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
                          final created = await _addStockItem(
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
                          if (created != null) {
                            Navigator.pop(context);
                            if (shelfContext.mounted) {
                              await promptPrintStockItemQr(
                                shelfContext,
                                item: created,
                              );
                            }
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

  Future<({Map<String, dynamic>? created, String? error})> _postStockItem({
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

      if (resp.statusCode == 201 || resp.statusCode == 200) {
        Map<String, dynamic>? created;
        try {
          final decoded = jsonDecode(resp.body);
          if (decoded is Map) {
            created = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
        return (created: created, error: null);
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
      return (
        created: null,
        error: '(${resp.statusCode}) $backendMsg',
      );
    } catch (e) {
      return (created: null, error: e.toString());
    }
  }

  Future<Map<String, dynamic>?> _addStockItem({
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
    final r = await _postStockItem(
      name: name,
      kodeBarang: kodeBarang,
      weight: weight,
      quantity: quantity,
      material: material,
      purity: purity,
      kategori: kategori,
      jenis: jenis,
      tipe: tipe,
    );
    if (!mounted) return null;
    if (r.created != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stok berhasil ditambahkan')),
      );
      await _loadItems();
      return r.created;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Gagal menambah stok ${r.error ?? ''}'),
      ),
    );
    return null;
  }

  Future<void> _showBulkAddStockDialog() async {
    final shelfContext = context;
    final formKey = GlobalKey<FormState>();
    final bulkTextController = TextEditingController();

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
        var progressLabel = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Tambah stok massal'),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Satu baris = satu kode stok. Format: kode, nama, berat (gram), qty, kadar '
                          '(pisah koma atau titik koma). Jika nama mengandung koma, pisahkan kolom dengan titik koma. '
                          'Baris kosong atau yang diawali # diabaikan.',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: bulkTextController,
                          maxLines: 12,
                          decoration: const InputDecoration(
                            labelText: 'Data (paste dari spreadsheet)',
                            hintText:
                                'KB001,Cincin emas,5.2,1,75%\nKB002;Gelang motif;10;2;22K',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Wajib diisi';
                            }
                            try {
                              _parseBulkStockLines(v);
                            } on FormatException catch (e) {
                              return e.message;
                            }
                            return null;
                          },
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
                        DropdownButtonFormField<String>(
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
                        if (isSaving && progressLabel.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(progressLabel),
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(),
                        ],
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
                          List<_BulkStockLine> rows;
                          try {
                            rows = _parseBulkStockLines(bulkTextController.text);
                          } on FormatException catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.message)),
                              );
                            }
                            return;
                          }
                          setDialogState(() {
                            isSaving = true;
                            progressLabel = '0 / ${rows.length}';
                          });
                          var ok = 0;
                          final failures = <String>[];
                          final createdItems = <Map<String, dynamic>>[];
                          for (var i = 0; i < rows.length; i++) {
                            if (!context.mounted) break;
                            final line = rows[i];
                            setDialogState(
                              () => progressLabel = '${i + 1} / ${rows.length}',
                            );
                            final r = await _postStockItem(
                              name: line.nama,
                              kodeBarang: line.kode,
                              weight: line.berat,
                              quantity: line.qty,
                              material: selectedMaterial,
                              purity: line.purity,
                              kategori: selectedKategori.trim(),
                              jenis: selectedJenis.trim(),
                              tipe: selectedTipe.trim(),
                            );
                            if (r.created != null) {
                              ok++;
                              createdItems.add(
                                Map<String, dynamic>.from(r.created!),
                              );
                            } else {
                              failures.add('${line.kode}: ${r.error ?? "gagal"}');
                            }
                          }
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          await _loadItems();
                          if (!shelfContext.mounted) return;
                          final messenger = ScaffoldMessenger.of(shelfContext);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Massal selesai: berhasil $ok, gagal ${failures.length}',
                              ),
                            ),
                          );
                          if (createdItems.isNotEmpty && shelfContext.mounted) {
                            await promptPrintStockItemsQrBulk(
                              shelfContext,
                              items: createdItems,
                            );
                          }
                          if (failures.isNotEmpty && shelfContext.mounted) {
                            await showDialog<void>(
                              context: shelfContext,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Baris gagal'),
                                content: SizedBox(
                                  width: 420,
                                  height: 280,
                                  child: SingleChildScrollView(
                                    child: Text(failures.join('\n')),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Tutup'),
                                  ),
                                ],
                              ),
                            );
                          }
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
      bulkTextController.dispose();
    });
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
    var list = _items;
    if (_selectedStatus != 'all') {
      list = list
          .where((it) =>
              stockItemVisibleForStatusFilter(it, _selectedStatus))
          .toList();
    }
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((it) {
      final code = (it['item_code'] ?? it['kode_produk'] ?? '').toString();
      final name = (it['name'] ?? '').toString();
      return code.toLowerCase().contains(q) || name.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Warehouse'),
        actions: [
          IconButton(
            tooltip: 'Tambah stok massal',
            onPressed: _showBulkAddStockDialog,
            icon: const Icon(Icons.playlist_add),
          ),
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
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                      child: StockStatusFilterSummaryHeader(
                        selectedStatus: _selectedStatus,
                        onStatusChanged: (v) => setState(() {
                          _selectedStatus = v;
                          _jenisDetailFocus = null;
                        }),
                        summaryItems: _filteredItems,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Cari item_code / nama',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() {
                          _search = v;
                          _jenisDetailFocus = null;
                        }),
                      ),
                    ),
                    Expanded(
                      child: StockJenisTwoStepPanel(
                        filteredItems: _filteredItems,
                        selectedJenisLabel: _jenisDetailFocus,
                        onSelectedJenisLabelChanged: (v) =>
                            setState(() => _jenisDetailFocus = v),
                        detailBuilder: (context, items) =>
                            StockInventoryGroupedTable(
                          filteredItems: items,
                          branchIdForMutations:
                              ref.read(userStateProvider).branch,
                          branchDisplayNameForHistory: stockBranchDisplayName(
                            branches: ref.watch(userStateProvider).branches,
                            branchId: ref.watch(userStateProvider).branch,
                          ),
                          onReload: _loadItems,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
