import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/utils/branch_types.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

/// Penambahan stok bahan baku / material ke cabang workshop (dari gudang).
class WarehouseWorkshopMaterialPage extends ConsumerStatefulWidget {
  const WarehouseWorkshopMaterialPage({super.key});

  @override
  ConsumerState<WarehouseWorkshopMaterialPage> createState() =>
      _WarehouseWorkshopMaterialPageState();
}

class _WarehouseWorkshopMaterialPageState
    extends ConsumerState<WarehouseWorkshopMaterialPage> {
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

  List<Map<String, dynamic>> _workshopBranches = [];
  int? _targetWorkshopId;
  bool _loadingBranches = true;
  String? _branchError;

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _kodeCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _purityCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _selectedKategori = 'BAHAN';
  String _selectedJenis = 'UMUM';
  String _selectedTipe = 'BIASA';
  String _selectedMaterial = 'EMAS';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadWorkshops();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _kodeCtrl.dispose();
    _weightCtrl.dispose();
    _qtyCtrl.dispose();
    _purityCtrl.dispose();
    _locationCtrl.dispose();
    _supplierCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWorkshops() async {
    setState(() {
      _loadingBranches = true;
      _branchError = null;
    });
    try {
      final uri = Uri.parse('${NetworkConfig.baseUrl}/branches').replace(
        queryParameters: {'branch_type': 'workshop'},
      );
      final res = await http.get(uri, headers: NetworkConfig.defaultHeaders);
      if (res.statusCode != 200) {
        setState(() {
          _branchError = 'Gagal memuat cabang (${res.statusCode})';
          _loadingBranches = false;
        });
        return;
      }
      final data = jsonDecode(res.body);
      final workshops = filterBranchesForTypeScope(
        data is List ? data : const [],
        'workshop',
      );
      if (!mounted) return;
      setState(() {
        _workshopBranches = workshops;
        if (_targetWorkshopId == null && workshops.length == 1) {
          final id = workshops.first['branch_id'];
          _targetWorkshopId =
              id is int ? id : int.tryParse(id?.toString() ?? '');
        }
        _loadingBranches = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _branchError = e.toString();
        _loadingBranches = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final workshopId = _targetWorkshopId;
    if (workshopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih cabang workshop')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ApiService.createWorkshopMaterialStock(
        branchId: workshopId.toString(),
        name: _nameCtrl.text.trim(),
        kodeProduk: _kodeCtrl.text.trim(),
        material: _selectedMaterial,
        purity: _purityCtrl.text.trim(),
        weight: double.parse(_weightCtrl.text.trim()),
        quantity: int.parse(_qtyCtrl.text.trim()),
        kategori: _selectedKategori,
        jenis: _selectedJenis,
        tipe: _selectedTipe,
        location: _locationCtrl.text.trim().isEmpty
            ? null
            : _locationCtrl.text.trim(),
        supplier: _supplierCtrl.text.trim().isEmpty
            ? 'Gudang'
            : _supplierCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Material berhasil ditambah di workshop')),
      );
      _nameCtrl.clear();
      _kodeCtrl.clear();
      _weightCtrl.clear();
      _qtyCtrl.text = '1';
      _purityCtrl.clear();
      _locationCtrl.clear();
      _notesCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final jenisList =
        _jenisByKategori[_selectedKategori] ?? const ['UMUM'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bahan Baku ke Workshop'),
      ),
      body: _loadingBranches
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: ResponsiveLayout.pagePadding(context),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_branchError != null)
                      Text(
                        _branchError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    Text(
                      'Tambah stok bahan baku / perlengkapan non-inventaris '
                      'langsung ke stok material workshop.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      key: ValueKey(_targetWorkshopId),
                      initialValue: _targetWorkshopId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Workshop tujuan',
                        border: OutlineInputBorder(),
                      ),
                      items: _workshopBranches.map((b) {
                        final rawId = b['branch_id'];
                        final id = rawId is int
                            ? rawId
                            : int.tryParse(rawId?.toString() ?? '');
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(
                            (b['name'] ?? 'Workshop $id').toString(),
                          ),
                        );
                      }).toList(),
                      onChanged: _workshopBranches.isEmpty
                          ? null
                          : (v) => setState(() => _targetWorkshopId = v),
                      validator: (v) => v == null ? 'Pilih workshop' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nama material',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Wajib' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _kodeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Kode material',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Wajib' : null,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedKategori,
                      decoration: const InputDecoration(
                        labelText: 'Kategori',
                        border: OutlineInputBorder(),
                      ),
                      items: _kategoriOptions
                          .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _selectedKategori = v;
                          _selectedJenis =
                              (_jenisByKategori[v] ?? const ['UMUM']).first;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedJenis,
                      decoration: const InputDecoration(
                        labelText: 'Jenis',
                        border: OutlineInputBorder(),
                      ),
                      items: jenisList
                          .map((j) => DropdownMenuItem(value: j, child: Text(j)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedJenis = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedTipe,
                      decoration: const InputDecoration(
                        labelText: 'Tipe',
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
                    DropdownButtonFormField<String>(
                      initialValue: _selectedMaterial,
                      decoration: const InputDecoration(
                        labelText: 'Material',
                        border: OutlineInputBorder(),
                      ),
                      items: _materialOptions
                          .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedMaterial = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _weightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Berat (gram)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final w = double.tryParse((v ?? '').trim());
                        if (w == null || w <= 0) return 'Harus > 0';
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Jumlah',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final q = int.tryParse((v ?? '').trim());
                        if (q == null || q <= 0) return 'Harus > 0';
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _purityCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Kadar / purity',
                        border: OutlineInputBorder(),
                        hintText: '22K, 75%, 925',
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Wajib' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _locationCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Lokasi rak (opsional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _supplierCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Supplier (opsional)',
                        border: OutlineInputBorder(),
                        hintText: 'Default: Gudang',
                      ),
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
                    FilledButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_circle_outline),
                      label: Text(_saving ? 'Menyimpan…' : 'Tambah ke workshop'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
