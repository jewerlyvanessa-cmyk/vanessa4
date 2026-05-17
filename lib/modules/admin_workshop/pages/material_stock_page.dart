import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

class MaterialStockPage extends ConsumerStatefulWidget {
  const MaterialStockPage({super.key});

  @override
  ConsumerState<MaterialStockPage> createState() => _MaterialStockPageState();
}

class _MaterialStockPageState extends ConsumerState<MaterialStockPage> {
  static const _materialOptions = ['EMAS', 'PERAK', 'LAINNYA'];
  static const _kategoriOptions = [
    'BAHAN',
    'PERLENGKAPAN',
    'PERHIASAN',
    'LOGAM MULIA',
    'AKSESORIES',
    'LAINNYA',
  ];
  static const Map<String, List<String>> _jenisByKategori = {
    'BAHAN': ['UMUM', 'SOLDER', 'PATRI', 'LEM', 'CAT'],
    'PERLENGKAPAN': ['UMUM', 'ALAT', 'BAHAN HABIS'],
    'PERHIASAN': ['CINCIN', 'GELANG', 'KALUNG', 'ANTING', 'LIONTIN', 'BRO'],
    'LOGAM MULIA': ['ANTAM', 'UBS', 'BATANGAN'],
    'AKSESORIES': ['GELANG', 'KALUNG', 'ANTING', 'BRO'],
    'LAINNYA': ['UMUM'],
  };
  static const _tipeOptions = ['BIASA', 'GRESS'];

  List<Map<String, dynamic>> _materialStock = [];
  bool _isLoading = true;
  String _errorMessage = '';
  String _selectedMaterial = 'Semua';
  String _selectedKategori = 'Semua';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadMaterialStock();
  }

  Future<void> _loadMaterialStock() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final stock = await ApiService.getMaterialStock(userState.branch);
      if (!mounted) return;
      setState(() {
        _materialStock = stock;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Gagal memuat stok material: $error';
        _isLoading = false;
      });
    }
  }

  List<String> _kategoriFilterOptions() {
    final fromData = _materialStock
        .map((e) => (e['kategori'] ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['Semua', ...fromData];
  }

  List<Map<String, dynamic>> _filteredStock() {
    var list = _materialStock;
    if (_selectedMaterial != 'Semua') {
      list = list
          .where(
            (item) =>
                (item['material'] ?? '').toString().toUpperCase() ==
                _selectedMaterial,
          )
          .toList();
    }
    if (_selectedKategori != 'Semua') {
      list = list
          .where(
            (item) =>
                (item['kategori'] ?? '').toString().toUpperCase() ==
                _selectedKategori,
          )
          .toList();
    }
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((item) {
      final hay = [
        item['name'],
        item['material'],
        item['kategori'],
        item['purity'],
        item['location'],
      ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
      return hay.contains(q);
    }).toList();
  }

  Future<void> _showAddMaterialDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final kodeCtrl = TextEditingController();
    final weightCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final purityCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final supplierCtrl = TextEditingController();

    String selectedKategori = 'BAHAN';
    String selectedJenis = 'UMUM';
    String selectedTipe = 'BIASA';
    String selectedMaterial = 'EMAS';
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final jenisList = _jenisByKategori[selectedKategori] ?? const ['UMUM'];
          if (selectedJenis.isNotEmpty &&
              !jenisList.contains(selectedJenis)) {
            selectedJenis = jenisList.first;
          }

          return AlertDialog(
            title: const Text('Tambah stok material'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nama material',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: kodeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Kode material',
                        border: OutlineInputBorder(),
                        hintText: 'Contoh: MAT-001',
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedKategori,
                      decoration: const InputDecoration(
                        labelText: 'Kategori',
                        border: OutlineInputBorder(),
                      ),
                      items: _kategoriOptions
                          .map(
                            (k) => DropdownMenuItem(value: k, child: Text(k)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() {
                          selectedKategori = v;
                          selectedJenis =
                              (_jenisByKategori[v] ?? const ['UMUM']).first;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedJenis,
                      decoration: const InputDecoration(
                        labelText: 'Jenis',
                        border: OutlineInputBorder(),
                      ),
                      items: jenisList
                          .map(
                            (j) => DropdownMenuItem(value: j, child: Text(j)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() => selectedJenis = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedTipe,
                      decoration: const InputDecoration(
                        labelText: 'Tipe',
                        border: OutlineInputBorder(),
                      ),
                      items: _tipeOptions
                          .map(
                            (t) => DropdownMenuItem(value: t, child: Text(t)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() => selectedTipe = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedMaterial,
                      decoration: const InputDecoration(
                        labelText: 'Material',
                        border: OutlineInputBorder(),
                      ),
                      items: _materialOptions
                          .map(
                            (m) => DropdownMenuItem(value: m, child: Text(m)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() => selectedMaterial = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: weightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Berat (gram)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final w = double.tryParse((v ?? '').trim());
                        if (w == null || w <= 0) {
                          return 'Berat harus angka positif';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Jumlah stok',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final q = int.tryParse((v ?? '').trim());
                        if (q == null || q <= 0) {
                          return 'Jumlah harus angka positif';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: purityCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Kadar / purity',
                        border: OutlineInputBorder(),
                        hintText: 'Contoh: 22K, 75%, 925',
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: locationCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Lokasi rak (opsional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: supplierCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Supplier (opsional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (formKey.currentState?.validate() != true) return;
                        final user = ref.read(userStateProvider);
                        final branchId = user.branch.trim();
                        if (branchId.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Pilih cabang aktif terlebih dahulu.'),
                            ),
                          );
                          return;
                        }
                        setDialogState(() => saving = true);
                        try {
                          await ApiService.createWorkshopMaterialStock(
                            branchId: branchId,
                            name: nameCtrl.text.trim(),
                            kodeProduk: kodeCtrl.text.trim(),
                            material: selectedMaterial,
                            purity: purityCtrl.text.trim(),
                            weight: double.parse(weightCtrl.text.trim()),
                            quantity: int.parse(qtyCtrl.text.trim()),
                            kategori: selectedKategori,
                            jenis: selectedJenis,
                            tipe: selectedTipe,
                            location: locationCtrl.text.trim(),
                            supplier: supplierCtrl.text.trim(),
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          if (!mounted) return;
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: Text('Stok material berhasil ditambahkan'),
                            ),
                          );
                          await _loadMaterialStock();
                        } catch (e) {
                          if (!context.mounted) return;
                          setDialogState(() => saving = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.toString())),
                          );
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Simpan'),
              ),
            ],
          );
        },
      ),
    );

    nameCtrl.dispose();
    kodeCtrl.dispose();
    weightCtrl.dispose();
    qtyCtrl.dispose();
    purityCtrl.dispose();
    locationCtrl.dispose();
    supplierCtrl.dispose();
  }

  Future<void> _showAdjustQtyDialog(Map<String, dynamic> item) async {
    final itemId = int.tryParse(item['item_id']?.toString() ?? '');
    if (itemId == null) return;

    final qtyCtrl = TextEditingController(
      text: (item['quantity'] ?? 0).toString(),
    );
    final notesCtrl = TextEditingController();
    final user = ref.read(userStateProvider);
    final techId = user.userId?.toString() ?? user.username;

    String? newQtyText;
    String? notesText;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sesuaikan stok — ${item['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Jumlah baru',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              newQtyText = qtyCtrl.text.trim();
              notesText = notesCtrl.text.trim();
              Navigator.pop(ctx, true);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    qtyCtrl.dispose();
    notesCtrl.dispose();

    if (ok != true || !mounted) return;

    final newQty = double.tryParse(newQtyText ?? '');
    if (newQty == null || newQty < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jumlah tidak valid')),
      );
      return;
    }

    try {
      final success = await ApiService.updateMaterialStock(
        itemId,
        newQty,
        techId,
        notes: notesText ?? '',
      );
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stok diperbarui')),
        );
        await _loadMaterialStock();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memperbarui: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _filteredStock();
    final kategoriFilters = _kategoriFilterOptions();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stok Material'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
            onPressed: _isLoading ? null : _loadMaterialStock,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddMaterialDialog,
        icon: const Icon(Icons.add),
        label: const Text('Tambah material'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadMaterialStock,
        child: ListView(
          physics: ResponsiveLayout.scrollPhysics,
          padding: ResponsiveLayout.safeScrollPadding(context),
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'Cari nama, material, kategori…',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 12),
            Text(
              'Material',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                'Semua',
                ..._materialOptions,
              ].map((m) {
                final selected = _selectedMaterial == m;
                return FilterChip(
                  label: Text(m),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedMaterial = m),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Text(
              'Kategori',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: kategoriFilters.map((k) {
                final selected = _selectedKategori == k;
                return FilterChip(
                  label: Text(k),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedKategori = k),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Text(
                      _errorMessage,
                      style: TextStyle(color: cs.error),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: _loadMaterialStock,
                      child: const Text('Coba lagi'),
                    ),
                  ],
                ),
              )
            else if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 48,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tidak ada stok material',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tekan "Tambah material" untuk menambah stok bahan workshop.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final rows = <DataRow>[];
                  for (var i = 0; i < filtered.length; i++) {
                    final item = filtered[i];
                    final qty = int.tryParse(item['quantity']?.toString() ?? '') ??
                        (item['quantity'] is num
                            ? (item['quantity'] as num).toInt()
                            : 0);
                    final minStock =
                        int.tryParse(item['min_stock']?.toString() ?? '') ?? 0;
                    final low = minStock > 0 && qty <= minStock;

                    rows.add(
                      DataRow(
                        color: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.hovered)) {
                            return cs.primary.withValues(alpha: 0.06);
                          }
                          return i.isOdd
                              ? cs.surfaceContainerHighest
                                  .withValues(alpha: 0.45)
                              : null;
                        }),
                        cells: [
                          DataCell(
                            Text(
                              item['name']?.toString() ?? '—',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          DataCell(Text(item['material']?.toString() ?? '—')),
                          DataCell(Text(item['purity']?.toString() ?? '—')),
                          DataCell(Text(item['kategori']?.toString() ?? '—')),
                          DataCell(Text('${item['weight'] ?? '—'} g')),
                          DataCell(
                            Text(
                              '$qty',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: low ? cs.error : null,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              item['location']?.toString() ?? 'Rak Umum',
                              style: TextStyle(
                                fontSize: AppTypography.bodySmall,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          DataCell(
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: 'Sesuaikan jumlah',
                              onPressed: () => _showAdjustQtyDialog(item),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Material(
                    elevation: 0,
                    color: cs.surfaceContainerLow.withValues(alpha: 0.65),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.45),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: constraints.maxWidth),
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              cs.surfaceContainerHigh,
                            ),
                            dataRowMinHeight: 44,
                            dataRowMaxHeight: 56,
                            columnSpacing: 12,
                            horizontalMargin: 10,
                            showCheckboxColumn: false,
                            dividerThickness: 0.5,
                            columns: [
                              DataColumn(label: dataTableColumnLabel('Nama')),
                              DataColumn(label: dataTableColumnLabel('Material')),
                              DataColumn(label: dataTableColumnLabel('Kadar')),
                              DataColumn(label: dataTableColumnLabel('Kategori')),
                              DataColumn(label: dataTableColumnLabel('Berat')),
                              DataColumn(label: dataTableColumnLabel('Stok')),
                              DataColumn(label: dataTableColumnLabel('Lokasi')),
                              DataColumn(label: dataTableColumnLabel('Aksi')),
                            ],
                            rows: rows,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
