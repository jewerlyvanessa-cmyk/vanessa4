import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/order_status_ui.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

/// Tukang membuat perhiasan dari stok material (produksi mandiri atau opsional ke order).
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
  bool _loadingWorkQueue = false;
  String? _error;

  int? _selectedOrderId;
  int? _selectedMaterialId;
  bool _linkToOrder = false;
  String _outputKategori = 'PERHIASAN';
  String _outputJenis = 'CINCIN';
  String _outputTipe = 'BIASA';
  String _outputMaterial = 'EMAS';
  bool _saving = false;

  int? _orderIdOf(Map<String, dynamic> w) =>
      int.tryParse(w['order_id']?.toString() ?? '');

  int? _materialIdOf(Map<String, dynamic> m) =>
      int.tryParse(m['item_id']?.toString() ?? '');

  Map<String, dynamic>? get _selectedMaterial {
    if (_selectedMaterialId == null) return null;
    for (final m in _materialStock) {
      if (_materialIdOf(m) == _selectedMaterialId) return m;
    }
    return null;
  }

  List<String> get _outputJenisOptions =>
      _jenisByKategori[_outputKategori] ?? const ['UMUM'];

  String get _effectiveOutputJenis =>
      _outputJenisOptions.contains(_outputJenis)
          ? _outputJenis
          : _outputJenisOptions.first;

  @override
  void initState() {
    super.initState();
    _loadMaterialStock();
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

  Future<void> _loadMaterialStock() async {
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
      final stock = await ApiService.getMaterialStock(user.branch);
      if (!mounted) return;
      setState(() {
        _materialStock = stock;
        if (_selectedMaterialId != null &&
            !_materialStock.any((m) => _materialIdOf(m) == _selectedMaterialId)) {
          _selectedMaterialId = null;
        }
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

  Future<void> _loadWorkQueueIfNeeded() async {
    if (_workQueue.isNotEmpty || _loadingWorkQueue) return;
    setState(() => _loadingWorkQueue = true);
    try {
      final user = ref.read(userStateProvider);
      final queue = await ApiService.getWorkQueue(
        user.branch,
        assignedTechnicianId: user.userId!.toString(),
      );
      if (!mounted) return;
      setState(() {
        _workQueue = queue;
        if (_selectedOrderId != null &&
            !_workQueue.any((w) => _orderIdOf(w) == _selectedOrderId)) {
          _selectedOrderId = null;
        }
        _loadingWorkQueue = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingWorkQueue = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat daftar order: $e')),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final material = _selectedMaterial;
    if (material == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih material bahan')),
      );
      return;
    }

    if (_linkToOrder && _selectedOrderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih order atau matikan kaitan order')),
      );
      return;
    }

    final user = ref.read(userStateProvider);
    final materialId = _materialIdOf(material);
    final matQty = double.tryParse(_matQtyCtrl.text.trim());
    if (materialId == null || matQty == null || matQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data material tidak valid')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final res = await ApiService.produceJewelryFromMaterial(
        branchId: user.branch,
        orderId: _linkToOrder ? _selectedOrderId : null,
        technicianId: user.userId!,
        materialItemId: materialId,
        materialQtyUsed: matQty,
        notes: _notesCtrl.text.trim(),
        output: {
          'name': _nameCtrl.text.trim(),
          'kode_produk': _kodeCtrl.text.trim(),
          'kategori': _outputKategori,
          'jenis': _effectiveOutputJenis,
          'tipe': _outputTipe,
          'material': _outputMaterial,
          'purity': _purityCtrl.text.trim(),
          'weight': double.parse(_weightCtrl.text.trim()),
          'quantity': 1,
        },
      );
      if (!mounted) return;
      final linked = res['order_id'] != null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            linked
                ? 'Perhiasan "${res['output_name'] ?? _nameCtrl.text}" dibuat (terkait order)'
                : 'Perhiasan "${res['output_name'] ?? _nameCtrl.text}" berhasil dibuat',
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
        _selectedOrderId = null;
        _selectedMaterialId = null;
        _linkToOrder = false;
        _outputKategori = 'PERHIASAN';
        _outputJenis = 'CINCIN';
        _outputTipe = 'BIASA';
        _outputMaterial = 'EMAS';
      });
      await _loadMaterialStock();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildOptionalOrderSection(BuildContext context, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Kaitkan ke order service/custom'),
          subtitle: const Text(
            'Opsional — produksi mandiri tidak perlu order',
          ),
          value: _linkToOrder,
          onChanged: (on) async {
            setState(() {
              _linkToOrder = on;
              if (!on) _selectedOrderId = null;
            });
            if (on) await _loadWorkQueueIfNeeded();
          },
        ),
        if (_linkToOrder) ...[
          const SizedBox(height: 8),
          if (_loadingWorkQueue)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_workQueue.isEmpty)
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Order (opsional)',
                border: OutlineInputBorder(),
                enabled: false,
              ),
              child: Text(
                'Belum ada order service/custom yang ditugaskan ke Anda.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else
            DropdownButtonFormField<int>(
              key: ValueKey('work_${_workQueue.length}_$_selectedOrderId'),
              initialValue: _workQueue.any((w) => _orderIdOf(w) == _selectedOrderId)
                  ? _selectedOrderId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Order service/custom',
                border: OutlineInputBorder(),
              ),
              items: _workQueue.map((w) {
                final oid = _orderIdOf(w);
                if (oid == null) return null;
                final item = w['item_name']?.toString() ??
                    w['nama_item']?.toString() ??
                    'Item';
                final st = OrderStatusUi.label(w['status']?.toString());
                return DropdownMenuItem(
                  value: oid,
                  child: Text('Order #$oid — $item ($st)'),
                );
              }).whereType<DropdownMenuItem<int>>().toList(),
              onChanged: (v) => setState(() => _selectedOrderId = v),
              validator: (v) {
                if (_linkToOrder && v == null) return 'Pilih order';
                return null;
              },
            ),
        ],
      ],
    );
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
            onPressed: _loading ? null : _loadMaterialStock,
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
                          onPressed: _loadMaterialStock,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMaterialStock,
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
                                      'Produksi mandiri dari stok material workshop. '
                                      'Hasil tercatat di Admin Workshop (Produksi Tukang). '
                                      'Order service/custom hanya jika ingin dikaitkan.',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '1. Material bahan',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          if (_materialStock.isEmpty)
                            InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Stok material *',
                                border: OutlineInputBorder(),
                                enabled: false,
                              ),
                              child: Text(
                                'Belum ada stok material di workshop',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            )
                          else
                            DropdownButtonFormField<int>(
                              key: ValueKey(
                                'mat_${_materialStock.length}_$_selectedMaterialId',
                              ),
                              initialValue: _materialStock.any(
                                (m) => _materialIdOf(m) == _selectedMaterialId,
                              )
                                  ? _selectedMaterialId
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Stok material *',
                                border: OutlineInputBorder(),
                              ),
                              items: _materialStock.map((m) {
                                final id = _materialIdOf(m);
                                if (id == null) return null;
                                final name = m['item_name']?.toString() ??
                                    m['name']?.toString() ??
                                    'Material';
                                final qty = m['quantity']?.toString() ?? '0';
                                return DropdownMenuItem(
                                  value: id,
                                  child: Text('$name (stok: $qty)'),
                                );
                              }).whereType<DropdownMenuItem<int>>().toList(),
                              onChanged: (v) =>
                                  setState(() => _selectedMaterialId = v),
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
                            '2. Hasil perhiasan',
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
                            key: ValueKey<String>(
                              'output_jenis_${_outputKategori}_$_effectiveOutputJenis',
                            ),
                            initialValue: _effectiveOutputJenis,
                            decoration: const InputDecoration(
                              labelText: 'Jenis',
                              border: OutlineInputBorder(),
                            ),
                            items: _outputJenisOptions
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
                          const SizedBox(height: 20),
                          Text(
                            '3. Kaitan order (opsional)',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          _buildOptionalOrderSection(context, cs),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: (_saving || _materialStock.isEmpty)
                                ? null
                                : _submit,
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
