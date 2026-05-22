import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

/// Panel tambah / edit kategori pemasukan & pengeluaran (manajer).
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get('/store-operational/categories');
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

  Future<void> _showNameDialog({
    required String title,
    required String entryKind,
    String? initialName,
    String? categoryId,
  }) async {
    final controller = TextEditingController(text: initialName ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'Nama kategori',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;

    final name = controller.text.trim();
    controller.dispose();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama kategori wajib diisi.')),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              categoryId != null ? 'Kategori diperbarui.' : 'Kategori ditambah.',
            ),
          ),
        );
        await _load();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageFromBody(res.body, res.statusCode))),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
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
      itemBuilder: (context, i) {
        final row = items[i];
        final name = row['name']?.toString() ?? '—';
        final id = row['category_id']?.toString();
        return ListTile(
          title: Text(name),
          trailing: IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: id == null
                ? null
                : () => _showNameDialog(
                      title: 'Edit kategori',
                      entryKind: entryKind,
                      initialName: name,
                      categoryId: id,
                    ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
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
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: AppTypography.section,
                            ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context, true),
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
                            title: 'Tambah kategori',
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
