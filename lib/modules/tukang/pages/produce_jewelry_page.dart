import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/order_status_ui.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

/// Tukang membuat perhiasan dari stok material — tercatat untuk admin workshop.
class ProduceJewelryPage extends ConsumerStatefulWidget {
  const ProduceJewelryPage({super.key});

  @override
  ConsumerState<ProduceJewelryPage> createState() => _ProduceJewelryPageState();
}

class _ProduceJewelryPageState extends ConsumerState<ProduceJewelryPage> {
  static const _materialOptions = ['EMAS', 'PERAK', 'LAINNYA'];
  static const _kategoriOptions = ['PERHIASAN', 'LOGAM MULIA', 'AKSESORIES'];
  static const Map<String, List<String>> _jenisByKategori = {
    'PERHIASAN': ['CINCIN', 'GELANG', 'KALUNG', 'ANTING', 'LIONTIN', 'BRO'],
    'LOGAM MULIA': ['ANTAM', 'UBS', 'BATANGAN'],
    'AKSESORIES': ['GELANG', 'KALUNG', 'ANTING', 'BRO'],
  };
  static const _tipeOptions = ['BIASA', 'GRESS'];

  final _formKey = GlobalKey<FormState>();
  final _matQtyCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _kodeCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _purityCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  List<Map<String, dynamic>> _workQueue = [];
  List<Map<String, dynamic>> _materialStock = [];
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _selectedWork;
  Map<String, dynamic>? _selectedMaterial;
  String _outputKategori = 'PERHIASAN';
  String _outputJenis = 'CINCIN';
  String _outputTipe = 'BIASA';
  String _outputMaterial = 'EMAS';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _matQtyCtrl.dispose();
    _nameCtrl.dispose();
    _kodeCtrl.dispose();
    _weightCtrl.dispose();
    _purityCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = ref.read(userStateProvider);
      final block = user.workshopSessionBlockReason;
      if (block != null) {
        setState(() {
          _error = block;
          _loading = false;
        });
        return;
      }
      final results = await Future.wait([
        ApiService.getWorkQueue(
          user.branch,
          assignedTechnicianId: user.userId!.toString(),
        ),
        ApiService.getMaterialStock(user.branch),
      ]);
      if (!mounted) return;
      setState(() {
        _workQueue = results[0];
        _materialStock = results[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedWork == null || _selectedMaterial == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih pekerjaan dan material bahan')),
      );
      return;
    }

    final user = ref.read(userStateProvider);
    final orderId = int.tryParse(_selectedWork!['order_id']?.toString() ?? '');
    final materialId =
        int.tryParse(_selectedMaterial!['item_id']?.toString() ?? '');
    final matQty = double.tryParse(_matQtyCtrl.text.trim());
    if (orderId == null || materialId == null || matQty == null || matQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data pekerjaan atau material tidak valid')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final res = await ApiService.produceJewelryFromMaterial(
        branchId: user.branch,
        orderId: orderId,
        technicianId: user.userId!,
        materialItemId: materialId,
        materialQtyUsed: matQty,
        notes: _notesCtrl.text.trim(),
        output: {
          'name': _nameCtrl.text.trim(),
          'kode_produk': _kodeCtrl.text.trim(),
          'kategori': _outputKategori,
          'jenis': _outputJenis,
          'tipe': _outputTipe,
          'material': _outputMaterial,
          'purity': _purityCtrl.text.trim(),
          'weight': double.parse(_weightCtrl.text.trim()),
          'quantity': 1,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Perhiasan "${res['output_name'] ?? _nameCtrl.text}" berhasil dibuat',
          ),
        ),
      );
      _formKey.currentState!.reset();
      _matQtyCtrl.clear();
      _nameCtrl.clear();
      _kodeCtrl.clear();
      _weightCtrl.clear();
      _purityCtrl.clear();
      _notesCtrl.clear();
      setState(() {
        _selectedWork = null;
        _selectedMaterial = null;
      });
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buat Perhiasan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: _loadData,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    physics: ResponsiveLayout.scrollPhysics,
                    padding: ResponsiveLayout.safeScrollPadding(context),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            color: cs.primaryContainer.withValues(alpha: 0.35),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, color: cs.primary),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Hasil produksi tercatat di Admin Workshop '
                                      '(menu Produksi Tukang) dan terhubung ke nomor order.',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '1. Pekerjaan',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<Map<String, dynamic>>(
                            initialValue: _selectedWork,
                            decoration: const InputDecoration(
                              labelText: 'Order / pekerjaan *',
                              border: OutlineInputBorder(),
                            ),
                            items: _workQueue.map((w) {
                              final oid = w['order_id']?.toString() ?? '—';
                              final item = w['item_name']?.toString() ??
                                  w['nama_item']?.toString() ??
                                  'Item';
                              final st = OrderStatusUi.label(
                                w['status']?.toString(),
                              );
                              return DropdownMenuItem(
                                value: w,
                                child: Text('Order #$oid — $item ($st)'),
                              );
                            }).toList(),
                            onChanged: (v) => setState(() => _selectedWork = v),
                            validator: (v) =>
                                v == null ? 'Pilih pekerjaan' : null,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '2. Material bahan',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<Map<String, dynamic>>(
                            initialValue: _selectedMaterial,
                            decoration: const InputDecoration(
                              labelText: 'Stok material *',
                              border: OutlineInputBorder(),
                            ),
                            items: _materialStock.map((m) {
                              final name = m['item_name']?.toString() ??
                                  m['name']?.toString() ??
                                  'Material';
                              final qty = m['quantity']?.toString() ?? '0';
                              return DropdownMenuItem(
                                value: m,
                                child: Text('$name (stok: $qty)'),
                              );
                            }).toList(),
                            onChanged: (v) =>
                                setState(() => _selectedMaterial = v),
                            validator: (v) =>
                                v == null ? 'Pilih material' : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _matQtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Jumlah material dipakai *',
                              border: OutlineInputBorder(),
                              hintText: 'Gram / unit sesuai stok',
                            ),
                            validator: (v) {
                              final n = double.tryParse((v ?? '').trim());
                              if (n == null || n <= 0) {
                                return 'Masukkan jumlah valid';
                              }
                              final avail = double.tryParse(
                                    _selectedMaterial?['quantity']?.toString() ??
                                        '',
                                  ) ??
                                  0;
                              if (n > avail) {
                                return 'Melebihi stok ($avail)';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '3. Hasil perhiasan',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nama perhiasan *',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Wajib' : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _kodeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Kode produk *',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Wajib' : null,
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _outputKategori,
                            decoration: const InputDecoration(
                              labelText: 'Kategori',
                              border: OutlineInputBorder(),
                            ),
                            items: _kategoriOptions
                                .map(
                                  (k) => DropdownMenuItem(
                                    value: k,
                                    child: Text(k),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                _outputKategori = v;
                                _outputJenis =
                                    (_jenisByKategori[v] ?? const ['UMUM'])
                                        .first;
                              });
                            },
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _outputJenis,
                            decoration: const InputDecoration(
                              labelText: 'Jenis',
                              border: OutlineInputBorder(),
                            ),
                            items: (_jenisByKategori[_outputKategori] ??
                                    const ['UMUM'])
                                .map(
                                  (j) => DropdownMenuItem(
                                    value: j,
                                    child: Text(j),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _outputJenis = v);
                            },
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _outputTipe,
                            decoration: const InputDecoration(
                              labelText: 'Tipe',
                              border: OutlineInputBorder(),
                            ),
                            items: _tipeOptions
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _outputTipe = v);
                            },
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _outputMaterial,
                            decoration: const InputDecoration(
                              labelText: 'Material',
                              border: OutlineInputBorder(),
                            ),
                            items: _materialOptions
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(m),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _outputMaterial = v);
                            },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _weightCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Berat hasil (gram) *',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              final w = double.tryParse((v ?? '').trim());
                              if (w == null || w <= 0) return 'Berat tidak valid';
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _purityCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Kadar *',
                              border: OutlineInputBorder(),
                              hintText: '22K, 75%, 925',
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Wajib' : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _notesCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Catatan (opsional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _saving ? null : _submit,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.diamond_outlined),
                            label: Text(
                              _saving ? 'Menyimpan…' : 'Simpan hasil produksi',
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}
