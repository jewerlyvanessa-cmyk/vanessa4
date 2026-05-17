import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/core/state/user_state.dart';
import 'package:vanessa3/modules/stockist/stock_warehouse_bulk.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/responsive_layout.dart';
import 'package:vanessa3/utils/stock_item_qr_print.dart';

/// Admin warehouse: catat barang masuk dari pembelian supplier ke stok gudang.
class SupplierReceiptPage extends ConsumerStatefulWidget {
  const SupplierReceiptPage({super.key});

  @override
  ConsumerState<SupplierReceiptPage> createState() =>
      _SupplierReceiptPageState();
}

class _SupplierReceiptPageState extends ConsumerState<SupplierReceiptPage> {
  final _formKey = GlobalKey<FormState>();
  final _itemFormKey = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();
  final _supplierCtrl = TextEditingController();
  final _invoiceCtrl = TextEditingController();
  final _receiptNotesCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _kodeCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _purityCtrl = TextEditingController();

  static const _kategoriOptions = ['PERHIASAN', 'LOGAM MULIA', 'AKSESORIES'];
  static const Map<String, List<String>> _jenisByKategori = {
    'PERHIASAN': ['CINCIN', 'GELANG', 'KALUNG', 'ANTING', 'LIONTIN', 'BRO'],
    'LOGAM MULIA': ['ANTAM', 'UBS', 'BATANGAN'],
    'AKSESORIES': ['GELANG', 'KALUNG', 'ANTING', 'BRO'],
  };
  static const _tipeOptions = ['BIASA', 'GRESS'];
  static const _materialOptions = ['EMAS', 'PERAK', 'LAINNYA'];

  String _selectedKategori = 'PERHIASAN';
  String _selectedJenis = 'CINCIN';
  String _selectedTipe = 'BIASA';
  String _selectedMaterial = 'EMAS';

  bool _saving = false;
  bool _loadingHistory = true;
  String? _historyError;
  List<Map<String, dynamic>> _recentReceipts = const [];
  final List<SupplierReceiptLine> _pendingLines = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHistory());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _supplierCtrl.dispose();
    _invoiceCtrl.dispose();
    _receiptNotesCtrl.dispose();
    _nameCtrl.dispose();
    _kodeCtrl.dispose();
    _weightCtrl.dispose();
    _qtyCtrl.dispose();
    _purityCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final branchId = ref.read(userStateProvider).branch.trim();
    if (branchId.isEmpty) {
      setState(() {
        _loadingHistory = false;
        _historyError = 'Cabang belum dipilih';
      });
      return;
    }
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    final res = await fetchSupplierReceiptHistory(branchId: branchId);
    if (!mounted) return;
    setState(() {
      _recentReceipts = res.items;
      _historyError = res.error;
      _loadingHistory = false;
    });
  }

  void _resetItemFields() {
    _nameCtrl.clear();
    _kodeCtrl.clear();
    _weightCtrl.clear();
    _qtyCtrl.text = '1';
    _purityCtrl.clear();
    setState(() {
      _selectedKategori = 'PERHIASAN';
      _selectedJenis = 'CINCIN';
      _selectedTipe = 'BIASA';
      _selectedMaterial = 'EMAS';
    });
  }

  String? _metadataString(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) {
      return raw['supplier']?.toString();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) return d['supplier']?.toString();
      } catch (_) {}
    }
    return null;
  }

  bool _validateSupplierHeader() {
    if (_supplierCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama supplier wajib diisi')),
      );
      return false;
    }
    return true;
  }

  SupplierReceiptLine? _lineFromForm() {
    if (_itemFormKey.currentState?.validate() != true) return null;
    return SupplierReceiptLine(
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
  }

  void _addLineToPending() {
    if (!_validateSupplierHeader()) return;
    final line = _lineFromForm();
    if (line == null) return;

    final dup = _pendingLines.any(
      (e) => e.kodeBarang.toLowerCase() == line.kodeBarang.toLowerCase(),
    );
    if (dup) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kode ${line.kodeBarang} sudah ada di daftar')),
      );
      return;
    }

    setState(() {
      _pendingLines.add(line);
      _resetItemFields();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ditambahkan: ${line.name} (${_pendingLines.length} item)')),
    );
  }

  Future<void> _submitAll() async {
    if (!_validateSupplierHeader()) return;

    final lines = List<SupplierReceiptLine>.from(_pendingLines);
    final draft = _lineFromForm();
    if (draft != null) {
      final dup = lines.any(
        (e) => e.kodeBarang.toLowerCase() == draft.kodeBarang.toLowerCase(),
      );
      if (!dup) {
        lines.add(draft);
      } else if (lines.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kode ${draft.kodeBarang} sudah ada di daftar')),
        );
        return;
      }
    }

    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tambahkan minimal satu barang ke daftar'),
        ),
      );
      return;
    }

    final user = ref.read(userStateProvider);
    final branchId = user.branch.trim();
    if (branchId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih cabang aktif terlebih dahulu.')),
      );
      return;
    }

    setState(() => _saving = true);
    final batch = await warehousePostSupplierReceiptBatch(
      branchId: branchId,
      supplierName: _supplierCtrl.text.trim(),
      lines: lines,
      invoiceNumber: _invoiceCtrl.text.trim(),
      receiptNotes: _receiptNotesCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _saving = false);

    final ok = batch.created.length;
    final fail = batch.failures.length;

    if (ok > 0) {
      setState(() {
        _pendingLines.clear();
        _resetItemFields();
      });
      await _loadHistory();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            fail > 0
                ? '$ok item tersimpan, $fail gagal'
                : '$ok item dari ${_supplierCtrl.text.trim()} berhasil dicatat',
          ),
        ),
      );

      if (batch.created.length == 1) {
        await promptPrintStockItemLabel(
          context,
          item: batch.created.first,
          afterSave: true,
        );
      } else if (batch.created.isNotEmpty && mounted) {
        final printAll = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cetak label?'),
            content: Text('Cetak label QR untuk $ok item yang berhasil disimpan?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Lewati'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Cetak semua'),
              ),
            ],
          ),
        );
        if (printAll == true && mounted) {
          for (final item in batch.created) {
            if (!mounted) break;
            await promptPrintStockItemLabel(context, item: item, afterSave: true);
          }
        }
      }
    }

    if (fail > 0 && mounted) {
      final detail = batch.failures
          .map((f) => 'Baris ${f.index + 1}: ${f.message}')
          .join('\n');
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sebagian gagal disimpan'),
          content: SingleChildScrollView(child: Text(detail)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else if (ok == 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua item gagal disimpan')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userStateProvider);
    final branchOk = user.branch.trim().isNotEmpty;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terima dari supplier'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
          ),
        ],
      ),
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
                  'Catat pembelian dari supplier: isi data supplier, tambahkan '
                  'satu atau banyak barang ke daftar, lalu simpan sekaligus. '
                  'Semua item dalam satu simpan memakai nomor batch yang sama.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (!branchOk)
                  Card(
                    color: cs.errorContainer,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Cabang aktif kosong. Pilih cabang di header.',
                      ),
                    ),
                  )
                else
                  _BranchLine(user: user),
                const SizedBox(height: 16),
                Text(
                  'Data supplier',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _supplierCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nama supplier *',
                    border: OutlineInputBorder(),
                    hintText: 'Contoh: PT Emas Nusantara',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _invoiceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'No. faktur / invoice (opsional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _receiptNotesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Catatan penerimaan (opsional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_pendingLines.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Daftar barang (${_pendingLines.length})',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _pendingLines.clear()),
                        child: const Text('Kosongkan'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...List.generate(_pendingLines.length, (i) {
                    final line = _pendingLines[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text('${i + 1}'),
                        ),
                        title: Text(line.name),
                        subtitle: Text(line.summary),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _saving
                              ? null
                              : () => setState(() => _pendingLines.removeAt(i)),
                        ),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 20),
                Text(
                  'Tambah barang',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Form(
                  key: _itemFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nama barang *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _kodeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Kode barang *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 10),
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
                      _selectedJenis =
                          (_jenisByKategori[value] ?? const ['UMUM']).first;
                    });
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>('jenis_$_selectedKategori'),
                  initialValue: _selectedJenis,
                  decoration: const InputDecoration(
                    labelText: 'Jenis *',
                    border: OutlineInputBorder(),
                  ),
                  items: (_jenisByKategori[_selectedKategori] ?? const ['UMUM'])
                      .map((j) => DropdownMenuItem(value: j, child: Text(j)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedJenis = v ?? ''),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Jenis wajib dipilih' : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _selectedTipe,
                  decoration: const InputDecoration(
                    labelText: 'Tipe *',
                    border: OutlineInputBorder(),
                  ),
                  items: _tipeOptions
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedTipe = v);
                  },
                ),
                const SizedBox(height: 10),
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
                const SizedBox(height: 10),
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
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text(m),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedMaterial = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _purityCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Kadar *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Wajib' : null,
                      ),
                    ),
                  ],
                ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _saving || !branchOk ? null : _addLineToPending,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Tambah ke daftar'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _saving || !branchOk ? null : _submitAll,
                  icon: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _saving
                        ? 'Menyimpan…'
                        : _pendingLines.isEmpty
                            ? 'Simpan penerimaan'
                            : 'Simpan penerimaan (${_pendingLines.length} + form jika diisi)',
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Penerimaan terbaru',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                if (_loadingHistory)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_historyError != null)
                  Text(
                    _historyError!,
                    style: TextStyle(color: cs.error),
                  )
                else if (_recentReceipts.isEmpty)
                  Text(
                    'Belum ada penerimaan supplier tercatat.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  )
                else
                  ..._recentReceipts.map((item) {
                    final created = item['created_at'];
                    String when = '—';
                    try {
                      when = DateFormat('dd MMM yyyy HH:mm').format(
                        DateTime.parse(created.toString()).toLocal(),
                      );
                    } catch (_) {}
                    final supplier = _metadataString(item['metadata']) ?? '—';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              cs.primaryContainer.withValues(alpha: 0.6),
                          child: Icon(Icons.inventory_2, color: cs.primary),
                        ),
                        title: Text(
                          item['name']?.toString() ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'Supplier: $supplier · ${item['kode_produk'] ?? '—'}\n$when',
                        ),
                        isThreeLine: true,
                      ),
                    );
                  }),
                const SizedBox(height: 24),
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
      'Cabang gudang: ${_label()}',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}
