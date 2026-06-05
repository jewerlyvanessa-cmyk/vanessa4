import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'branch_api_service.dart';
import '../../../utils/network_config.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/utils/branch_types.dart';

class BranchManagementPage extends ConsumerStatefulWidget {
  const BranchManagementPage({super.key});

  @override
  ConsumerState<BranchManagementPage> createState() => _BranchManagementPageState();
}

class _BranchManagementPageState extends ConsumerState<BranchManagementPage> {
  BranchApiService get _apiService =>
      BranchApiService(baseUrl: NetworkConfig.baseUrl);
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _filteredBranches = [];
  bool _isLoading = true;
  String _error = '';
  String _searchQuery = '';
  String? _statusFilter;
  String? _typeFilter;

  Future<void> _confirmDeleteBranch(Map<String, dynamic> branch) async {
    final branchId = branch['branch_id']?.toString() ?? '';
    final branchName = branch['name']?.toString() ?? 'Cabang';
    if (branchId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Cabang'),
        content: Text(
          'Yakin ingin menghapus cabang "$branchName"?\n\n'
          'Aksi ini tidak bisa dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _apiService.deleteBranch(branchId);
      if (!mounted) return;
      await _loadBranches();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cabang berhasil dihapus')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal hapus cabang: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      _branches = await _apiService.fetchBranches();
      _isLoading = false;
      _applyFilters();
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      debugPrint('Error loading branches: $error');
      String errorMessage = 'Gagal memuat data cabang. ';
      if (error.toString().contains('Connection refused') || error.toString().contains('Failed host lookup')) {
        errorMessage += 'Pastikan server backend sedang berjalan.';
      } else {
        errorMessage += 'Error: ${error.toString()}';
      }
      setState(() {
        _error = errorMessage;
        _isLoading = false;
      });
    }
  }

  Future<void> _showBranchForm({Map<String, dynamic>? branch}) async {
    final formKey = GlobalKey<FormState>();
    final isEdit = branch != null;
    String name = branch?['name']?.toString() ?? '';
    String code = branch?['code']?.toString() ?? '';
    String alias = branch?['alias']?.toString() ?? '';
    String initials = branch?['initials']?.toString() ?? '';
    String address = branch?['address']?.toString() ?? '';
    String phoneNumber = branch?['phone_number']?.toString() ?? '';
    String status = branch?['status']?.toString() ?? 'active';
    String branchType = normalizeBranchTypeKey(branch?['branch_type']?.toString());

    await showDialog(
      context: context,
      builder: (dialogContext) {
        bool submitting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? 'Edit Cabang' : 'Tambah Cabang'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        initialValue: name,
                        decoration: const InputDecoration(labelText: 'Nama cabang'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
                        onChanged: (v) => name = v.trim(),
                      ),
                      TextFormField(
                        initialValue: code,
                        decoration: const InputDecoration(labelText: 'Kode cabang'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Kode wajib diisi' : null,
                        onChanged: (v) => code = v.trim().toUpperCase(),
                      ),
                      TextFormField(
                        initialValue: alias,
                        decoration: const InputDecoration(labelText: 'Alias'),
                        onChanged: (v) => alias = v.trim(),
                      ),
                      TextFormField(
                        initialValue: initials,
                        decoration: const InputDecoration(labelText: 'Inisial'),
                        onChanged: (v) => initials = v.trim().toUpperCase(),
                      ),
                      TextFormField(
                        initialValue: address,
                        decoration: const InputDecoration(labelText: 'Alamat'),
                        onChanged: (v) => address = v.trim(),
                      ),
                      TextFormField(
                        initialValue: phoneNumber,
                        decoration: const InputDecoration(labelText: 'Nomor telepon'),
                        keyboardType: TextInputType.phone,
                        onChanged: (v) => phoneNumber = v.trim(),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: branchType,
                        decoration: const InputDecoration(
                          labelText: 'Tipe cabang',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final k in kBranchTypeKeys)
                            DropdownMenuItem<String>(
                              value: k,
                              child: Text(kBranchTypeLabels[k] ?? k),
                            ),
                        ],
                        onChanged: (v) => setDialogState(() => branchType = v ?? 'toko'),
                      ),
                      if (isEdit)
                        DropdownButtonFormField<String>(
                          initialValue: status,
                          decoration: const InputDecoration(labelText: 'Status'),
                          items: const [
                            DropdownMenuItem(value: 'active', child: Text('Aktif')),
                            DropdownMenuItem(value: 'inactive', child: Text('Tidak Aktif')),
                          ],
                          onChanged: (v) => status = v ?? 'active',
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) return;
                          setDialogState(() => submitting = true);

                          try {
                            final isCodeValid = await _apiService.validateBranchCode(
                              code,
                              excludeBranchId: isEdit ? branch['branch_id'].toString() : null,
                            );
                            if (isCodeValid == false) {
                              throw Exception('Kode cabang sudah dipakai.');
                            }

                            final payload = {
                              'name': name,
                              'code': code,
                              'alias': alias.isEmpty ? null : alias,
                              'initials': initials.isEmpty ? null : initials,
                              'address': address.isEmpty ? null : address,
                              'phone_number': phoneNumber.isEmpty ? null : phoneNumber,
                              'branch_type': branchType,
                              if (isEdit) 'status': status,
                            };

                            bool success;
                            if (isEdit) {
                              success = await _apiService.updateBranch(
                                branch['branch_id'].toString(),
                                payload,
                              );
                            } else {
                              success = await _apiService.createBranch(payload);
                            }

                            if (!success) {
                              throw Exception(isEdit ? 'Gagal mengubah cabang.' : 'Gagal menambah cabang.');
                            }

                            if (!mounted) return;
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            await _loadBranches();
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isEdit
                                      ? 'Cabang berhasil diperbarui'
                                      : 'Cabang berhasil ditambahkan',
                                ),
                              ),
                            );
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(content: Text('Gagal simpan cabang: $e')),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setDialogState(() => submitting = false);
                            }
                          }
                        },
                  child: Text(isEdit ? 'Simpan' : 'Tambah'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showBranchUsers(String branchId, String branchName) async {
    try {
      final users = await _apiService.fetchBranchUsers(branchId);
      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (dialogContext) {
          final cs = Theme.of(dialogContext).colorScheme;
Widget body;
          if (users.isEmpty) {
            body = const Text('Belum ada user di cabang ini.');
          } else {
            final dataRows = <DataRow>[];
            for (var i = 0; i < users.length; i++) {
              final user = users[i];
              final primary = user['is_primary'] == true;
              dataRows.add(
                DataRow(
                  color: WidgetStateProperty.resolveWith((s) {
                    if (s.contains(WidgetState.hovered)) {
                      return cs.primary.withValues(alpha: 0.06);
                    }
                    return i.isOdd
                        ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
                        : null;
                  }),
                  cells: [
                    DataCell(
                      Icon(
                        primary ? Icons.star : Icons.person,
                        color: primary ? Colors.amber : cs.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                    DataCell(
                      Text(
                        user['username']?.toString() ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    DataCell(Text(user['role']?.toString() ?? '-')),
                    DataCell(Text(user['user_status']?.toString() ?? '-')),
                  ],
                ),
              );
            }
            body = SizedBox(
              width: 520,
              height: math.min(
                400.0,
                MediaQuery.sizeOf(dialogContext).height * 0.55,
              ),
              child: Material(
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
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        cs.surfaceContainerHigh,
                      ),
dataRowMinHeight: 40,
                      columnSpacing: 12,
                      horizontalMargin: 12,
                      showCheckboxColumn: false,
                      columns: [
                        DataColumn(label: dataTableColumnLabel('')),
                        DataColumn(label: dataTableColumnLabel('Username')),
                        DataColumn(label: dataTableColumnLabel('Role')),
                        DataColumn(label: dataTableColumnLabel('Status')),
                      ],
                      rows: dataRows,
                    ),
                  ),
                ),
              ),
            );
          }
          return AlertDialog(
            title: Text('Users - $branchName'),
            content: body,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Tutup'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat users cabang: $e')),
      );
    }
  }

  Future<void> _showBranchStats(String branchId, String branchName) async {
    try {
      final stats = await _apiService.fetchBranchStatistics(branchId);
      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Statistik - $branchName'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total user: ${stats['total_users'] ?? 0}'),
                Text('Total transaksi bulan ini: ${stats['total_transactions'] ?? 0}'),
                Text('Total item: ${stats['total_items'] ?? 0}'),
                Text('Order completed bulan ini: ${stats['completed_orders_this_month'] ?? 0}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat statistik cabang: $e')),
      );
    }
  }

  String? _absoluteLogoUrl(Map<String, dynamic> branch) {
    final path = branch['logo_url']?.toString().trim();
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${NetworkConfig.baseUrl}$path';
  }

  Future<void> _pickAndUploadBranchLogo(Map<String, dynamic> branch) async {
    final id = branch['branch_id']?.toString() ?? '';
    if (id.isEmpty) return;
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 88,
    );
    if (x == null) return;
    try {
      await _apiService.uploadBranchLogo(id, x);
      if (!mounted) return;
      await _loadBranches();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logo cabang berhasil diunggah')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal upload logo: $e')),
      );
    }
  }

  Future<void> _confirmDeleteBranchLogo(Map<String, dynamic> branch) async {
    final id = branch['branch_id']?.toString() ?? '';
    if (id.isEmpty) return;
    final name = branch['name']?.toString() ?? 'Cabang';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus logo cabang'),
        content: Text('Hapus logo untuk cabang "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _apiService.deleteBranchLogo(id);
      if (!mounted) return;
      await _loadBranches();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logo cabang dihapus')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal hapus logo: $e')),
      );
    }
  }

  void _applyFilters() {
    _filteredBranches = _branches.where((branch) {
      final matchesSearch = _searchQuery.isEmpty ||
          branch['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
          branch['code'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (branch['alias']?.toString().toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);

      final matchesStatus = _statusFilter == null || branch['status'] == _statusFilter;

      final bt = normalizeBranchTypeKey(branch['branch_type']?.toString());
      final matchesType = _typeFilter == null || bt == _typeFilter;

      return matchesSearch && matchesStatus && matchesType;
    }).toList();
  }

  /// Satu gaya teks untuk sel data tabel cabang di layout sempit (mobile).
  TextStyle _mobileTableDataStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium;
    return (base ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
  }

  Widget _logoTableCell(String? logoUrl, {bool compact = false}) {
    final s = compact ? 36.0 : 44.0;
    return SizedBox(
      width: s,
      height: s,
      child: ClipOval(
        child: logoUrl != null
            ? Image.network(
                logoUrl,
                width: s,
                height: s,
                fit: BoxFit.cover,
                headers: NetworkConfig.imageHeaders,
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: const Color(0xFFE0E0E0), child: Icon(Icons.store, size: s * 0.5)),
              )
            : ColoredBox(
                color: const Color(0xFFE8E8E8),
                child: Icon(Icons.store_outlined, size: s * 0.5),
              ),
      ),
    );
  }

  Widget _branchActionsMenu(
    BuildContext context,
    Map<String, dynamic> branch,
    String? logoUrl,
    String id,
    String name,
  ) {
    return PopupMenuButton<String>(
      tooltip: 'Aksi',
      icon: const Icon(Icons.more_vert),
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            await _showBranchForm(branch: branch);
            break;
          case 'users':
            await _showBranchUsers(id, name);
            break;
          case 'stats':
            await _showBranchStats(id, name);
            break;
          case 'logo':
            await _pickAndUploadBranchLogo(branch);
            break;
          case 'logo_del':
            await _confirmDeleteBranchLogo(branch);
            break;
          case 'delete':
            await _confirmDeleteBranch(branch);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit cabang')),
        const PopupMenuItem(value: 'users', child: Text('Lihat users')),
        const PopupMenuItem(value: 'stats', child: Text('Statistik')),
        const PopupMenuItem(value: 'logo', child: Text('Unggah / ganti logo')),
        if (logoUrl != null)
          const PopupMenuItem(
            value: 'logo_del',
            child: Text('Hapus logo'),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Text(
            'Hapus cabang',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
  }

  Widget _buildBranchesTable(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 600;
        final minTableW = narrow ? constraints.maxWidth : 1060.0;
        final mobileDataStyle = _mobileTableDataStyle(context);

        final columns = narrow
            ? <DataColumn>[
                DataColumn(label: dataTableColumnLabel('Kode')),
                DataColumn(label: dataTableColumnLabel('Alias')),
                DataColumn(label: dataTableColumnLabel('Inisial')),
                const DataColumn(label: SizedBox(width: 44)),
              ]
            : <DataColumn>[
                DataColumn(label: dataTableColumnLabel('Logo')),
                DataColumn(label: dataTableColumnLabel('Nama cabang')),
                DataColumn(label: dataTableColumnLabel('Kode')),
                DataColumn(label: dataTableColumnLabel('Alias')),
                DataColumn(label: dataTableColumnLabel('Inisial')),
                DataColumn(label: dataTableColumnLabel('Tipe')),
                DataColumn(label: dataTableColumnLabel('Status')),
                DataColumn(label: dataTableColumnLabel('Alamat')),
                DataColumn(label: dataTableColumnLabel('Telepon')),
                const DataColumn(label: SizedBox(width: 48)),
              ];

        final rows = <DataRow>[];
        for (var i = 0; i < _filteredBranches.length; i++) {
          final branch = _filteredBranches[i];
          final logoUrl = _absoluteLogoUrl(branch);
          final name = (branch['name'] ?? '-').toString();
          final id = branch['branch_id']?.toString() ?? '';
          final active = branch['status'] == 'active';

          final cells = narrow
              ? <DataCell>[
                  DataCell(
                    Tooltip(
                      message: name,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            (branch['code'] ?? '-').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mobileDataStyle,
                          ),
                          Text(
                            branchTypeLabel(branch['branch_type']?.toString()),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.2,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      (branch['alias'] ?? '—').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mobileDataStyle,
                    ),
                  ),
                  DataCell(
                    Text(
                      (branch['initials'] ?? '—').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mobileDataStyle,
                    ),
                  ),
                  DataCell(
                    Align(
                      alignment: Alignment.centerRight,
                      child: _branchActionsMenu(
                        context,
                        branch,
                        logoUrl,
                        id,
                        name,
                      ),
                    ),
                  ),
                ]
              : <DataCell>[
                  DataCell(_logoTableCell(logoUrl)),
                  DataCell(
                    Tooltip(
                      message: name,
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      (branch['code'] ?? '-').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DataCell(
                    Text(
                      (branch['alias'] ?? '—').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DataCell(
                    Text(
                      (branch['initials'] ?? '—').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DataCell(
                    Text(
                      branchTypeLabel(branch['branch_type']?.toString()),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                  DataCell(
                    Text(
                      active ? 'Aktif' : 'Tidak aktif',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: active ? Colors.green.shade800 : cs.error,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      (branch['address'] ?? '—').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                  DataCell(
                    Text(
                      (branch['phone_number'] ?? '—').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DataCell(
                    Align(
                      alignment: Alignment.centerRight,
                      child: _branchActionsMenu(
                        context,
                        branch,
                        logoUrl,
                        id,
                        name,
                      ),
                    ),
                  ),
                ];

          rows.add(
            DataRow(
              color: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.hovered)) {
                  return cs.primary.withValues(alpha: 0.06);
                }
                return i.isOdd ? cs.surfaceContainerHighest.withValues(alpha: 0.45) : null;
              }),
              cells: cells,
            ),
          );
        }

        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: minTableW > constraints.maxWidth ? minTableW : constraints.maxWidth,
                ),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(cs.surfaceContainerHigh),
dataRowMinHeight: narrow ? 40 : 52,
                  dataRowMaxHeight: narrow ? 48 : 72,
                  columnSpacing: narrow ? 8 : 14,
                  horizontalMargin: narrow ? 8 : 12,
                  showCheckboxColumn: false,
                  dividerThickness: 0.5,
                  columns: columns,
                  rows: rows,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text('Manajemen Cabang'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () => _showBranchForm(),
              icon: const Icon(Icons.add),
              label: const Text('Tambah cabang'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and Filter Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Cari cabang...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                      _applyFilters();
                    });
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: _statusFilter,
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Semua Status')),
                          DropdownMenuItem(value: 'active', child: Text('Aktif')),
                          DropdownMenuItem(value: 'inactive', child: Text('Tidak Aktif')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _statusFilter = value;
                            _applyFilters();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Tipe cabang',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: _typeFilter,
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Semua tipe'),
                          ),
                          for (final k in kBranchTypeKeys)
                            DropdownMenuItem<String>(
                              value: k,
                              child: Text(kBranchTypeLabels[k] ?? k),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _typeFilter = value;
                            _applyFilters();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _loadBranches,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error, size: 64, color: Theme.of(context).colorScheme.error),
                            const SizedBox(height: 16),
                            Text(_error, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadBranches,
                              child: const Text('Coba Lagi'),
                            ),
                          ],
                        ),
                      )
                    : _filteredBranches.isEmpty
                        ? const Center(
                            child: Text('Tidak ada data cabang'),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            child: _buildBranchesTable(context),
                          ),
          ),
        ],
      ),
    );
  }
}
