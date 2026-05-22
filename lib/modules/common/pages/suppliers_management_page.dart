import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/modules/common/widgets/supplier_form_dialog.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/suppliers_api.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

/// Pengelolaan master data supplier (admin warehouse & manajer).
class SuppliersManagementPage extends ConsumerStatefulWidget {
  const SuppliersManagementPage({super.key});

  @override
  ConsumerState<SuppliersManagementPage> createState() =>
      _SuppliersManagementPageState();
}

class _SuppliersManagementPageState
    extends ConsumerState<SuppliersManagementPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String _statusFilter = 'active';
  final _searchCtrl = TextEditingController();

  bool get _canEdit {
    final role = ref.read(userStateProvider).role.trim().toLowerCase();
    return {'admin_warehouse', 'manajer', 'superadmin'}.contains(role);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final params = <String, String>{};
      if (_statusFilter != 'all') {
        params['status'] = _statusFilter;
      }
      final q = _searchCtrl.text.trim();
      if (q.isNotEmpty) params['q'] = q;

      final uri = Uri.parse(suppliersApiBaseUrl())
          .replace(queryParameters: params.isEmpty ? null : params);
      final res = await http.get(uri, headers: NetworkConfig.defaultHeaders);
      if (res.statusCode != 200) {
        var hint = '';
        if (res.statusCode == 404) {
          hint =
              '\n\nAPI supplier belum tersedia di server. '
              'Restart backend terbaru atau deploy ulang.';
        }
        setState(() {
          _error = 'Gagal memuat (${res.statusCode})$hint';
          _loading = false;
        });
        return;
      }
      final data = jsonDecode(res.body);
      if (!mounted) return;
      setState(() {
        _rows = (data is List ? data : const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
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

  Future<void> _showFormDialog({Map<String, dynamic>? existing}) async {
    if (!_canEdit) return;

    final saved = await showSupplierFormDialog(
      context,
      existing: existing,
      compact: false,
    );

    if (saved == null || !mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Data supplier disimpan')),
    );
  }

  Future<void> _deactivate(Map<String, dynamic> row) async {
    if (!_canEdit) return;
    final id = row['supplier_id']?.toString();
    if (id == null || id.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nonaktifkan supplier?'),
        content: Text(
          'Supplier "${row['name']}" akan dinonaktifkan. '
          'Data tetap tersimpan dan bisa diaktifkan lagi lewat edit.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Nonaktifkan'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final res = await http.delete(
      Uri.parse('${suppliersApiBaseUrl()}/$id'),
      headers: NetworkConfig.defaultHeaders,
    );
    if (!mounted) return;
    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supplier dinonaktifkan')),
      );
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal (${res.statusCode})')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Supplier'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: _canEdit
          ? FloatingActionButton(
              onPressed: () => _showFormDialog(),
              tooltip: 'Tambah supplier',
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: ResponsiveLayout.pagePadding(context).copyWith(bottom: 0),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Cari nama, kode, telepon…',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        _load();
                      },
                    ),
                  ),
                  onSubmitted: (_) => _load(),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'active', label: Text('Aktif')),
                    ButtonSegment(value: 'inactive', label: Text('Nonaktif')),
                    ButtonSegment(value: 'all', label: Text('Semua')),
                  ],
                  selected: {_statusFilter},
                  onSelectionChanged: (s) {
                    setState(() => _statusFilter = s.first);
                    _load();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
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
                              FilledButton(
                                onPressed: _load,
                                child: const Text('Coba lagi'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _rows.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 80),
                                  Center(
                                    child: Text(
                                      'Belum ada data supplier.\n'
                                      'Tekan + untuk menambah.',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                padding: ResponsiveLayout.pagePadding(context),
                                itemCount: _rows.length,
                                itemBuilder: (context, i) {
                                  final row = _rows[i];
                                  final active =
                                      (row['status'] ?? 'active') == 'active';
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: active
                                            ? cs.primaryContainer
                                            : cs.surfaceContainerHighest,
                                        child: Icon(
                                          Icons.local_shipping_outlined,
                                          color: active
                                              ? cs.primary
                                              : cs.onSurfaceVariant,
                                        ),
                                      ),
                                      title: Text(
                                        row['name']?.toString() ?? '-',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          decoration: active
                                              ? null
                                              : TextDecoration.lineThrough,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if ((row['code'] ?? '')
                                              .toString()
                                              .isNotEmpty)
                                            Text('Kode: ${row['code']}'),
                                          if ((row['contact_name'] ?? '')
                                              .toString()
                                              .isNotEmpty)
                                            Text(
                                              'Kontak: ${row['contact_name']}',
                                            ),
                                          if ((row['phone'] ?? '')
                                              .toString()
                                              .isNotEmpty)
                                            Text('Telp: ${row['phone']}'),
                                          if ((row['email'] ?? '')
                                              .toString()
                                              .isNotEmpty)
                                            Text(row['email'].toString()),
                                        ],
                                      ),
                                      trailing: _canEdit
                                          ? PopupMenuButton<String>(
                                              onSelected: (v) {
                                                if (v == 'edit') {
                                                  _showFormDialog(
                                                    existing: row,
                                                  );
                                                } else if (v == 'off' &&
                                                    active) {
                                                  _deactivate(row);
                                                }
                                              },
                                              itemBuilder: (ctx) => [
                                                const PopupMenuItem(
                                                  value: 'edit',
                                                  child: Text('Edit'),
                                                ),
                                                if (active)
                                                  const PopupMenuItem(
                                                    value: 'off',
                                                    child: Text('Nonaktifkan'),
                                                  ),
                                              ],
                                            )
                                          : Chip(
                                              label: Text(
                                                active ? 'Aktif' : 'Nonaktif',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                      onTap: _canEdit
                                          ? () => _showFormDialog(
                                                existing: row,
                                              )
                                          : null,
                                    ),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}
