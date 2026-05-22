import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

/// Dialog nama kategori — controller hidup/dimatikan di dalam route dialog.
class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog({
    required this.title,
    this.initialName,
  });

  final String title;
  final String? initialName;

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;

  bool get _isEdit =>
      (widget.initialName ?? '').trim().isNotEmpty ||
      widget.title.toLowerCase().contains('edit');

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _close() {
    if (!mounted) return;
    Navigator.pop(context);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _nameCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                autofocus: !_isEdit,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Nama kategori *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                onFieldSubmitted: (_) => _save(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _close,
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

/// Panel tambah / edit / hapus kategori pemasukan & pengeluaran (kasir & manajer).
class StoreOperationalCategoriesSheet extends StatefulWidget {
  const StoreOperationalCategoriesSheet({super.key});

  @override
  State<StoreOperationalCategoriesSheet> createState() =>
      _StoreOperationalCategoriesSheetState();
}

class _StoreOperationalCategoriesSheetState
    extends State<StoreOperationalCategoriesSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  List<Map<String, dynamic>> _expense = [];
  List<Map<String, dynamic>> _income = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get('/store-operational/categories');
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = _hintForStatus(res.statusCode) ??
              _messageFromBody(res.body, res.statusCode);
          _expense = [];
          _income = [];
        });
        return;
      }
      final decoded = jsonDecode(res.body);
      final all = decoded is List
          ? decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _expense = all
            .where((e) => e['entry_kind']?.toString() != 'income')
            .toList();
        _income = all
            .where((e) => e['entry_kind']?.toString() == 'income')
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
        _expense = [];
        _income = [];
      });
    }
  }

  String? _hintForStatus(int status) {
    if (status == 404) {
      return 'API /store-operational/categories tidak ditemukan (404).\n\n'
          'Backend production belum di-deploy dengan kode terbaru, atau server lokal belum di-restart.\n\n'
          'Langkah:\n'
          '1. Deploy folder backend (terutama routes/orders_core.js)\n'
          '2. psql -f backend/sql/patch_store_operational_categories.sql\n'
          '3. pm2 restart vanessa-api (atau restart node)';
    }
    if (status == 503) {
      return 'Tabel store_operational_categories belum ada (503).\n'
          'Jalankan backend/sql/patch_store_operational_categories.sql lalu restart backend.';
    }
    return null;
  }

  String _messageFromBody(String body, int status) {
    try {
      final m = jsonDecode(body);
      if (m is Map && m['error'] != null) return '${m['error']}';
    } catch (_) {}
    return 'Gagal ($status)';
  }

  Future<String?> _promptCategoryName({
    required String title,
    String? initialName,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => _CategoryNameDialog(
        title: title,
        initialName: initialName,
      ),
    );
  }

  Future<void> _showNameDialog({
    required String title,
    required String entryKind,
    String? initialName,
    String? categoryId,
  }) async {
    final name = await _promptCategoryName(
      title: title,
      initialName: initialName,
    );
    if (!mounted) return;
    if (name == null) return;
    if (name.isEmpty) {
      _snack('Nama kategori wajib diisi.');
      return;
    }

    try {
      final res = categoryId != null
          ? await ApiClient.patch(
              '/store-operational/categories/$categoryId',
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'name': name}),
            )
          : await ApiClient.post(
              '/store-operational/categories',
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'name': name, 'entry_kind': entryKind}),
            );
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        await _load();
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _snack(
            categoryId != null ? 'Kategori diperbarui.' : 'Kategori ditambah.',
          );
        });
        return;
      }
      _snack(_messageFromBody(res.body, res.statusCode));
    } catch (e) {
      if (mounted) _snack('Error: $e');
    }
  }

  Future<void> _confirmDelete({
    required String categoryId,
    required String name,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus kategori?'),
        content: Text(
          'Kategori "$name" akan dihapus dari daftar.\n\n'
          'Pencatatan lama tetap memakai nama kategori yang sudah tersimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final res = await ApiClient.delete(
        '/store-operational/categories/$categoryId',
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        await _load();
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _snack('Kategori dihapus.');
        });
        return;
      }
      _snack(_messageFromBody(res.body, res.statusCode));
    } catch (e) {
      if (mounted) _snack('Error: $e');
    }
  }

  Widget _buildList(String entryKind, List<Map<String, dynamic>> items) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }
    if (items.isEmpty) {
      return Center(
        child: Text(
          'Belum ada kategori. Tap + untuk menambah.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (listContext, i) {
        final row = items[i];
        final name = row['name']?.toString() ?? '—';
        final id = row['category_id']?.toString();
        return ListTile(
          title: Text(name),
          trailing: id == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit',
                      onPressed: () => _showNameDialog(
                        title: 'Edit kategori',
                        entryKind: entryKind,
                        initialName: name,
                        categoryId: id,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: Theme.of(listContext).colorScheme.error,
                      ),
                      tooltip: 'Hapus',
                      onPressed: () => _confirmDelete(
                        categoryId: id,
                        name: name,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sheetContext = context;
    final cs = Theme.of(sheetContext).colorScheme;
    final bottom = MediaQuery.paddingOf(sheetContext).bottom;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) {
        return Material(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Kelola Kategori',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: AppTypography.section,
                            ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext, true),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Pengeluaran'),
                  Tab(text: 'Pemasukan'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildList('expense', _expense),
                    _buildList('income', _income),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottom),
                child: FilledButton.icon(
                  onPressed: _loading
                      ? null
                      : () {
                          final kind =
                              _tabController.index == 1 ? 'income' : 'expense';
                          _showNameDialog(
                            title: 'Tambah kategori baru',
                            entryKind: kind,
                          );
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah kategori'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
