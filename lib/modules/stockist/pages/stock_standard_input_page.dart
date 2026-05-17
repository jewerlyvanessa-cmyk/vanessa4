import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/core/state/user_state.dart';
import 'package:vanessa3/modules/stockist/stock_warehouse_bulk.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/responsive_layout.dart';
import 'package:vanessa3/utils/stock_item_qr_print.dart';

/// Input stok **satu SKU** (form standar: nama, kode, berat gram, qty, kadar, kategori/jenis/tipe/material).
/// Halaman penuh — pola sama dengan tambah stok di warehouse, tanpa dialog.
class StockStandardInputPage extends ConsumerStatefulWidget {
  const StockStandardInputPage({super.key});

  @override
  ConsumerState<StockStandardInputPage> createState() =>
      _StockStandardInputPageState();
}

class _StockStandardInputPageState extends ConsumerState<StockStandardInputPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _kodeCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _purityCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  static const _kategoriOptions = ['PERHIASAN', 'LOGAM MULIA', 'AKSESORIES'];
  static const Map<String, List<String>> _jenisByKategori = {
    'PERHIASAN': ['CINCIN', 'GELANG', 'KALUNG', 'ANTING', 'LIONTIN', 'BRO'],
    'LOGAM MULIA': ['ANTAM', 'UBS', 'BATANGAN'],
    'AKSESORIES': ['GELANG', 'KALUNG', 'ANTING', 'BRO'],
  };
  static const _tipeOptions = ['BIASA', 'GRESS'];
  static const _materialOptions = ['EMAS', 'PERAK', 'LAINNYA'];

  String _selectedKategori = 'PERHIASAN';
  String _selectedJenis = '';
  String _selectedTipe = 'BIASA';
  String _selectedMaterial = 'EMAS';

  bool _isSaving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _kodeCtrl.dispose();
    _weightCtrl.dispose();
    _qtyCtrl.dispose();
    _purityCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _resetFormForNextEntry() {
    _nameCtrl.clear();
    _kodeCtrl.clear();
    _weightCtrl.clear();
    _qtyCtrl.text = '1';
    _purityCtrl.clear();
    setState(() {
      _selectedKategori = 'PERHIASAN';
      _selectedJenis = '';
      _selectedTipe = 'BIASA';
      _selectedMaterial = 'EMAS';
    });
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;

    final user = ref.read(userStateProvider);
    final branchId = user.branch.trim();
    if (branchId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih cabang aktif terlebih dahulu.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final res = await warehousePostStockItem(
      branchId: branchId,
      name: _nameCtrl.text.trim(),
      kodeBarang: _kodeCtrl.text.trim(),
      weight: double.parse(_weightCtrl.text.trim()),
      quantity: int.parse(_qtyCtrl.text.trim()),
      material: _selectedMaterial,
      purity: _purityCtrl.text.trim(),
      kategori: _selectedKategori,
      jenis: _selectedJenis,
      tipe: _selectedTipe,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (res.created != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stok berhasil ditambahkan')),
      );
      await promptPrintStockItemLabel(
        context,
        item: res.created!,
        afterSave: true,
      );
      if (mounted) _resetFormForNextEntry();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Gagal menambah stok ${res.error ?? ''}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userStateProvider);
    final branchOk = user.branch.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Input stok (standar)')),
      body: Scrollbar(
        controller: _scrollCtrl,
        thumbVisibility: true,
        child: SingleChildScrollView(
          primary: false,
          controller: _scrollCtrl,
          physics: ResponsiveLayout.scrollPhysics,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: ResponsiveLayout.safeScrollPadding(context),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Satu formulir = satu item stok. Satuan berat: gram; qty: unit. '
                  'Data disimpan ke cabang aktif Anda.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (!branchOk)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.store_mall_directory_outlined,
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Cabang aktif kosong. Pilih cabang di header lalu kembali ke halaman ini.',
                              style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  _BranchLine(user: user),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nama item *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _kodeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Kode barang *',
                    helperText: 'Contoh: KB001, GOLD-001',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedKategori,
                  decoration: const InputDecoration(
                    labelText: 'Kategori *',
                    border: OutlineInputBorder(),
                  ),
                  items: _kategoriOptions
                      .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedKategori = value;
                      _selectedJenis = '';
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>('jenis_$_selectedKategori'),
                  initialValue: _selectedJenis.isEmpty ? null : _selectedJenis,
                  decoration: const InputDecoration(
                    labelText: 'Jenis *',
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('Pilih jenis'),
                  items: (_jenisByKategori[_selectedKategori] ?? const <String>[])
                      .map((j) => DropdownMenuItem(value: j, child: Text(j)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedJenis = v ?? ''),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Jenis wajib dipilih' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedTipe,
                  decoration: const InputDecoration(
                    labelText: 'Tipe *',
                    border: OutlineInputBorder(),
                  ),
                  items: _tipeOptions
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedTipe = value);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _weightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Berat (gram) *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final p = double.tryParse((v ?? '').trim());
                          if (p == null || p <= 0) return 'Berat tidak valid';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _qtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Qty *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final n = int.tryParse((v ?? '').trim());
                          if (n == null || n <= 0) return 'Qty tidak valid';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedMaterial,
                        decoration: const InputDecoration(
                          labelText: 'Material *',
                          border: OutlineInputBorder(),
                        ),
                        items: _materialOptions
                            .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _selectedMaterial = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _purityCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Kadar / purity *',
                          helperText: 'Contoh: 75%, 22K, 99.99%',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _isSaving || !branchOk ? null : _submit,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_isSaving ? 'Menyimpan…' : 'Simpan stok'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BranchLine extends StatelessWidget {
  const _BranchLine({required this.user});

  final UserState user;

  String _label() {
    final id = user.branch.trim();
    for (final b in user.branches) {
      if (b['branch_id']?.toString() == id) {
        return (b['name'] ?? id).toString();
      }
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      'Cabang aktif: ${_label()} (ID: ${user.branch})',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}
