import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'branch_api_service.dart';
import '../../../utils/network_config.dart';

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
        builder: (context) => AlertDialog(
          title: Text('Users - $branchName'),
          content: SizedBox(
            width: 420,
            child: users.isEmpty
                ? const Text('Belum ada user di cabang ini.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: users.length,
                    separatorBuilder: (_, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final user = users[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          user['is_primary'] == true ? Icons.star : Icons.person,
                          color: user['is_primary'] == true ? Colors.amber : null,
                        ),
                        title: Text(user['username']?.toString() ?? '-'),
                        subtitle: Text('Role: ${user['role'] ?? '-'} | Status: ${user['user_status'] ?? '-'}'),
                      );
                    },
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

  void _applyFilters() {
    _filteredBranches = _branches.where((branch) {
      final matchesSearch = _searchQuery.isEmpty ||
          branch['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
          branch['code'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (branch['alias']?.toString().toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);

      final matchesStatus = _statusFilter == null || branch['status'] == _statusFilter;

      return matchesSearch && matchesStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Cabang'),
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
                        : ListView.builder(
                            itemCount: _filteredBranches.length,
                            itemBuilder: (context, index) {
                              final branch = _filteredBranches[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: ExpansionTile(
                                  title: Text(
                                    branch['name'] ?? 'Unknown',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text('${branch['code']} - ${branch['alias'] ?? 'No alias'}'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: branch['status'] == 'active' 
                                            ? Theme.of(context).colorScheme.primary 
                                            : Theme.of(context).colorScheme.error,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          branch['status'] == 'active' ? 'Aktif' : 'Tidak Aktif',
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onPrimary, 
                                            fontSize: 12
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () => _showBranchForm(branch: branch),
                                      ),
                                      IconButton(
                                        tooltip: 'Hapus',
                                        icon: Icon(
                                          Icons.delete,
                                          color: Theme.of(context).colorScheme.error,
                                        ),
                                        onPressed: () => _confirmDeleteBranch(branch),
                                      ),
                                    ],
                                  ),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Alamat: ${branch['address'] ?? 'N/A'}'),
                                          Text('Telepon: ${branch['phone_number'] ?? 'N/A'}'),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              ElevatedButton.icon(
                                                onPressed: () => _showBranchUsers(
                                                  branch['branch_id'].toString(),
                                                  branch['name']?.toString() ?? 'Cabang',
                                                ),
                                                icon: const Icon(Icons.people),
                                                label: const Text('Lihat Users'),
                                              ),
                                              const SizedBox(width: 8),
                                              ElevatedButton.icon(
                                                onPressed: () => _showBranchStats(
                                                  branch['branch_id'].toString(),
                                                  branch['name']?.toString() ?? 'Cabang',
                                                ),
                                                icon: const Icon(Icons.bar_chart),
                                                label: const Text('Statistik'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showBranchForm(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
