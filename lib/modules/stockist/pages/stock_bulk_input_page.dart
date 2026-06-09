import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/modules/stockist/stock_warehouse_bulk.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/stock_item_qr_print.dart';

class _EditableBulkRow {
  _EditableBulkRow()
      : kode = TextEditingController(),
        nama = TextEditingController(),
        berat = TextEditingController(),
        qty = TextEditingController(text: '1'),
        kadar = TextEditingController();

  final TextEditingController kode;
  final TextEditingController nama;
  final TextEditingController berat;
  final TextEditingController qty;
  final TextEditingController kadar;

  void dispose() {
    kode.dispose();
    nama.dispose();
    berat.dispose();
    qty.dispose();
    kadar.dispose();
  }

  bool get isAllWhitespace {
    bool e(String s) => s.trim().isEmpty;
    return e(kode.text) && e(nama.text) && e(berat.text) && e(qty.text) && e(kadar.text);
  }
}

/// Halaman penuh: input stok massal via tabel → diserialisasi ke teks bulk (tab) untuk validasi & simpan.
class StockBulkInputPage extends ConsumerStatefulWidget {
  const StockBulkInputPage({super.key});

  @override
  ConsumerState<StockBulkInputPage> createState() => _StockBulkInputPageState();
}

class _StockBulkInputPageState extends ConsumerState<StockBulkInputPage> {
  final _scrollCtrl = ScrollController();
  final List<_EditableBulkRow> _rows = [];
  Timer? _staleDebounce;

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
  List<WarehouseBulkPreviewRow>? _preview;
  bool _previewStale = true;

  /// Jumlah baris kosong saat halaman dibuka, setelah simpan sukses, atau impor kosong.
  static const int _kDefaultEmptyRows = 2;

  /// Contoh 5 kolom: kode; nama; berat (g); qty; kadar (boleh juga koma sebagai pemisah).
  static const _templateLine = 'KB001;Cincin emas;5.2;1;75%';

  @override
  void initState() {
    super.initState();
    _addEmptyRows(_kDefaultEmptyRows);
  }

  void _addEmptyRows(int n) {
    for (var i = 0; i < n; i++) {
      _rows.add(_EditableBulkRow());
    }
  }

  void _disposeAllRows() {
    for (final r in _rows) {
      r.dispose();
    }
    _rows.clear();
  }

  void _markStale() {
    _staleDebounce?.cancel();
    _staleDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _previewStale = true;
      });
    });
  }

  @override
  void dispose() {
    _staleDebounce?.cancel();
    _disposeAllRows();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Gabungkan isi tabel → teks bulk (satu baris = satu item, kolom dipisah tab).
  String _bulkTextFromTable() {
    final buf = StringBuffer();
    for (final r in _rows) {
      if (r.isAllWhitespace) continue;
      buf.writeln(
        warehouseBulkEncodeTableRow(
          r.kode.text,
          r.nama.text,
          r.berat.text,
          r.qty.text,
          r.kadar.text,
        ),
      );
    }
    return buf.toString();
  }

  void _runPreview() {
    _staleDebounce?.cancel();
    final raw = _bulkTextFromTable();
    setState(() {
      _preview = previewWarehouseBulkPaste(raw);
      _previewStale = false;
    });
  }

  void _ensurePreviewFresh() {
    if (_previewStale || _preview == null) {
      _runPreview();
    }
  }

  int get _validCount => _preview?.where((r) => r.isValid).length ?? 0;
  int get _errorCount => _preview?.where((r) => !r.isValid).length ?? 0;

  bool get _canSubmit =>
      !_isSaving &&
      !_previewStale &&
      _selectedJenis.isNotEmpty &&
      _preview != null &&
      _errorCount == 0 &&
      _validCount > 0;

  void _addRow() {
    _staleDebounce?.cancel();
    setState(() {
      _rows.add(_EditableBulkRow());
      _preview = null;
      _previewStale = true;
    });
  }

  void _removeRowAt(int index) {
    if (index < 0 || index >= _rows.length) return;
    _staleDebounce?.cancel();
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
      if (_rows.isEmpty) _addEmptyRows(_kDefaultEmptyRows);
      _preview = null;
      _previewStale = true;
    });
  }

  Future<void> _copyTemplate() async {
    await Clipboard.setData(const ClipboardData(text: _templateLine));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contoh baris disalin — tempel di spreadsheet atau gunakan «Tempel dari teks».')),
    );
  }

  Future<void> _showPasteImportDialog() async {
    final pasteCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Tempel dari spreadsheet'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: pasteCtrl,
              maxLines: 14,
              decoration: const InputDecoration(
                labelText: 'Kode, nama, berat, qty, kadar (koma atau titik koma)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                final raw = pasteCtrl.text;
                final prev = previewWarehouseBulkPaste(raw);
                if (ctx.mounted) Navigator.pop(ctx);
                _applyImportPreview(prev, raw);
              },
              child: const Text('Isi tabel'),
            ),
          ],
        );
      },
    );
    pasteCtrl.dispose();
  }

  void _applyImportPreview(List<WarehouseBulkPreviewRow> prev, String rawFallback) {
    _staleDebounce?.cancel();
    for (final r in _rows) {
      r.dispose();
    }
    _rows.clear();
    setState(() {
      if (prev.isEmpty) {
        final lines = rawFallback
            .split(RegExp(r'\r?\n'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty && !e.startsWith('#'))
            .toList();
        for (final line in lines) {
          final row = _EditableBulkRow();
          final parts = splitWarehouseBulkLineParts(line);
          if (parts.length >= 5) {
            row.kode.text = parts[0];
            row.nama.text = parts[1];
            row.berat.text = parts[2];
            row.qty.text = parts[3];
            row.kadar.text = parts[4];
          } else {
            row.nama.text = line;
          }
          _rows.add(row);
        }
        if (_rows.isEmpty) _addEmptyRows(_kDefaultEmptyRows);
      } else {
        for (final p in prev) {
          final row = _EditableBulkRow();
          if (p.line != null) {
            row.kode.text = p.line!.kode;
            row.nama.text = p.line!.nama;
            row.berat.text = '${p.line!.berat}';
            row.qty.text = '${p.line!.qty}';
            row.kadar.text = p.line!.purity;
          } else {
            row.nama.text = p.rawSnippet;
          }
          _rows.add(row);
        }
      }
      _preview = null;
      _previewStale = true;
    });
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    _staleDebounce?.cancel();
    if (_selectedJenis.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih jenis terlebih dahulu.')),
      );
      return;
    }
    _ensurePreviewFresh();
    if (!mounted) return;
    if (_errorCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Perbaiki $_errorCount baris bermasalah sebelum simpan.')),
      );
      return;
    }
    if (_validCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi tabel lalu «Perbarui pratinjau» — tidak ada baris valid.')),
      );
      return;
    }

    final branchId = ref.read(userStateProvider).branch.toString();
    if (branchId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cabang tidak ditemukan — login ulang.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    var ok = 0;
    var fail = 0;
    final errors = <String>[];
    final createdItems = <Map<String, dynamic>>[];

    final lines = _preview!.where((r) => r.isValid).map((r) => r.line!).toList();
    for (final line in lines) {
      final res = await warehousePostStockItem(
        branchId: branchId,
        name: line.nama,
        kodeBarang: line.kode,
        weight: line.berat,
        quantity: line.qty,
        material: _selectedMaterial,
        purity: line.purity,
        kategori: _selectedKategori,
        jenis: _selectedJenis,
        tipe: _selectedTipe,
      );
      if (res.error == null) {
        ok++;
        final c = res.created;
        if (c != null) {
          createdItems.add(c);
        }
      } else {
        fail++;
        if (errors.length < 6) {
          errors.add('${line.kode}: ${res.error}');
        }
      }
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    final buf = StringBuffer('Selesai: $ok berhasil');
    if (fail > 0) buf.write(', $fail gagal');
    if (errors.isNotEmpty) {
      buf.write('\n');
      buf.write(errors.join('\n'));
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(buf.toString()), duration: const Duration(seconds: 6)),
    );
    if (createdItems.isNotEmpty) {
      await promptPrintStockItemsLabelBulk(
        context,
        items: createdItems,
        afterSave: true,
      );
    }
    if (!mounted) return;
    if (fail == 0 && ok > 0) {
      _staleDebounce?.cancel();
      _disposeAllRows();
      _addEmptyRows(_kDefaultEmptyRows);
      if (!mounted) return;
      setState(() {
        _preview = null;
        _previewStale = true;
      });
    }
  }

  InputDecoration _cellDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      border: const OutlineInputBorder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Input stok massal')),
      body: Scrollbar(
        controller: _scrollCtrl,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scrollCtrl,
          padding: EdgeInsets.fromLTRB(
            16, 16, 16,
            16 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Isi langsung di tabel (koma di nama tidak masalah). Saat pratinjau atau simpan, '
                'baris digabung menjadi teks bulk berpemisah tab — diproses sama seperti paste dari spreadsheet.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _copyTemplate,
                    icon: const Icon(Icons.content_copy, size: 18),
                    label: const Text('Salin contoh baris'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showPasteImportDialog,
                    icon: const Icon(Icons.paste, size: 18),
                    label: const Text('Tempel dari teks'),
                  ),
                  Text(
                    'Contoh: $_templateLine',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Data item', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 720),
                  child: Table(
                    border: TableBorder.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    columnWidths: const {
                      0: FixedColumnWidth(40),
                      1: FlexColumnWidth(1.1),
                      2: FlexColumnWidth(1.6),
                      3: FlexColumnWidth(0.85),
                      4: FixedColumnWidth(72),
                      5: FlexColumnWidth(0.9),
                      6: FixedColumnWidth(44),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                        children: const [
                          _HeaderCell('#'),
                          _HeaderCell('Kode'),
                          _HeaderCell('Nama'),
                          _HeaderCell('Berat (g)'),
                          _HeaderCell('Qty'),
                          _HeaderCell('Kadar'),
                          _HeaderCell(''),
                        ],
                      ),
                      for (var i = 0; i < _rows.length; i++)
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Center(child: Text('${i + 1}')),
                            ),
                            _Cell(
                              child: TextField(
                                controller: _rows[i].kode,
                                onChanged: (_) => _markStale(),
                                decoration: _cellDecoration('Kode'),
                              ),
                            ),
                            _Cell(
                              child: TextField(
                                controller: _rows[i].nama,
                                onChanged: (_) => _markStale(),
                                decoration: _cellDecoration('Nama'),
                                maxLines: 2,
                              ),
                            ),
                            _Cell(
                              child: TextField(
                                controller: _rows[i].berat,
                                onChanged: (_) => _markStale(),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: _cellDecoration('Berat'),
                              ),
                            ),
                            _Cell(
                              child: TextField(
                                controller: _rows[i].qty,
                                onChanged: (_) => _markStale(),
                                keyboardType: TextInputType.number,
                                decoration: _cellDecoration('Qty'),
                              ),
                            ),
                            _Cell(
                              child: TextField(
                                controller: _rows[i].kadar,
                                onChanged: (_) => _markStale(),
                                decoration: _cellDecoration('Kadar'),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: IconButton(
                                tooltip: 'Hapus baris',
                                onPressed: _rows.length <= 1 ? null : () => _removeRowAt(i),
                                icon: const Icon(Icons.delete_outline, size: 20),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _addRow,
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Tambah baris'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _runPreview,
                    icon: const Icon(Icons.fact_check_outlined, size: 20),
                    label: const Text('Perbarui pratinjau'),
                  ),
                  const SizedBox(width: 12),
                  if (_preview != null)
                    Expanded(
                      child: Text(
                        _errorCount == 0 && _validCount > 0
                            ? '$_validCount baris siap disimpan.'
                            : _validCount == 0 && (_preview!.isEmpty)
                                ? 'Tidak ada baris terisi.'
                                : '$_validCount OK, $_errorCount perlu perbaikan.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _errorCount > 0
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Atribut bersama', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedKategori,
                decoration: const InputDecoration(labelText: 'Kategori', border: OutlineInputBorder()),
                items: _kategoriOptions
                    .map((k) => DropdownMenuItem<String>(value: k, child: Text(k)))
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
                decoration: const InputDecoration(labelText: 'Jenis *', border: OutlineInputBorder()),
                hint: const Text('Pilih jenis'),
                items: (_jenisByKategori[_selectedKategori] ?? const <String>[])
                    .map((j) => DropdownMenuItem<String>(value: j, child: Text(j)))
                    .toList(),
                onChanged: (value) => setState(() => _selectedJenis = value ?? ''),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedTipe,
                decoration: const InputDecoration(labelText: 'Tipe', border: OutlineInputBorder()),
                items: _tipeOptions
                    .map((t) => DropdownMenuItem<String>(value: t, child: Text(t)))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedTipe = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedMaterial,
                decoration: const InputDecoration(labelText: 'Material', border: OutlineInputBorder()),
                items: _materialOptions
                    .map((m) => DropdownMenuItem<String>(value: m, child: Text(m)))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedMaterial = value);
                },
              ),
              const SizedBox(height: 20),
              if (_preview != null && _preview!.isNotEmpty) ...[
                Text('Hasil cek (sama seperti parse teks bulk)', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 40,
                    dataRowMinHeight: 36,
                    dataRowMaxHeight: 72,
                    columns: const [
                      DataColumn(label: Text('#')),
                      DataColumn(label: Text('Kode')),
                      DataColumn(label: Text('Nama')),
                      DataColumn(label: Text('Berat')),
                      DataColumn(label: Text('Qty')),
                      DataColumn(label: Text('Kadar')),
                      DataColumn(label: Text('Status')),
                    ],
                    rows: _preview!.map((r) {
                      final ok = r.isValid;
                      final errText = [
                        if (r.parseError != null) r.parseError!,
                        if (r.duplicateWarning != null) r.duplicateWarning!,
                      ].join(' · ');
                      return DataRow(
                        cells: [
                          DataCell(Text('${r.sourceLineNumber}')),
                          DataCell(Text(r.line?.kode ?? '—')),
                          DataCell(Text(r.line?.nama ?? '—', maxLines: 2, overflow: TextOverflow.ellipsis)),
                          DataCell(Text(r.line != null ? '${r.line!.berat}' : '—')),
                          DataCell(Text(r.line != null ? '${r.line!.qty}' : '—')),
                          DataCell(Text(r.line?.purity ?? '—')),
                          DataCell(
                            ok
                                ? Icon(Icons.check_circle, color: Colors.green.shade700, size: 22)
                                : Tooltip(
                                    message: errText,
                                    child: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 22),
                                  ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
                if (_errorCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Perbaiki sel di tabel atas sesuai pesan error, lalu Perbarui pratinjau.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _canSubmit ? _submit : null,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.cloud_upload),
                label: Text(_isSaving ? 'Menyimpan…' : 'Simpan semua baris valid'),
              ),
              if (!_canSubmit && !_isSaving) ...[
                const SizedBox(height: 8),
                Text(
                  _selectedJenis.isEmpty
                      ? 'Pilih jenis, isi tabel, lalu Perbarui pratinjau sampai tidak ada error.'
                      : _previewStale || _preview == null
                          ? 'Tekan «Perbarui pratinjau» untuk mengonversi tabel ke teks bulk dan mengecek duplikat/format.'
                          : _errorCount > 0
                              ? 'Tombol simpan nonaktif selama masih ada baris error.'
                              : _validCount == 0
                                  ? 'Tidak ada baris valid untuk disimpan.'
                                  : '',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: child,
    );
  }
}
