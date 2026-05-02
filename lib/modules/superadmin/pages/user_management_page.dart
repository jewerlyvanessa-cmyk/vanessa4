import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'user_api_service.dart';
import '../../../utils/network_config.dart';
import '../../../main.dart';


class UserManagementPage extends ConsumerStatefulWidget {
  const UserManagementPage({super.key});

  @override
  ConsumerState<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends ConsumerState<UserManagementPage> {
  late UserApiService apiService;
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> branches = [];
  bool isLoading = true;
  String? error;

  bool get _isSuperadmin {
    final role = ref.read(userStateProvider).role.toString().trim().toLowerCase();
    return role == 'superadmin';
  }

  bool get _canSuperadminOrManajer {
    final role = ref.read(userStateProvider).role.toString().trim().toLowerCase();
    return role == 'superadmin' || role == 'manajer';
  }

  Future<void> _runGuarded(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    apiService = UserApiService(baseUrl: NetworkConfig.baseUrl);
    fetchUsers();
    fetchBranches();
  }

  String _branchLabel(Map<String, dynamic> branch) {
    final name = (branch['name'] ?? 'Unknown Branch').toString();
    final code = (branch['code'] ?? '').toString().trim();
    if (code.isEmpty) return name;
    return '$name ($code)';
  }

  Future<void> fetchUsers() async {
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      users = await apiService.fetchUsers();
    } catch (e) {
      error = e.toString();
    }
    setState(() {
      isLoading = false;
    });
  }

  Future<void> fetchBranches() async {
    try {
      branches = await apiService.fetchBranches();
    } catch (e) {
      debugPrint('Error fetching branches: $e');
    }
  }

  Future<void> addUser(Map<String, dynamic> user) async {
    await _runGuarded(() async {
      if (!_isSuperadmin) {
        throw Exception('Akses ditolak: hanya superadmin yang bisa menambah user.');
      }
      final success = await apiService.addUser(user);
      if (success) fetchUsers();
    });
  }

  Future<void> updateUser(String id, Map<String, dynamic> user) async {
    await _runGuarded(() async {
      if (!_isSuperadmin) {
        throw Exception('Akses ditolak: hanya superadmin yang bisa mengedit user.');
      }
      final success = await apiService.updateUser(id, user);
      if (success) fetchUsers();
    });
  }

  Future<void> deleteUser(String id) async {
    await _runGuarded(() async {
      if (!_isSuperadmin) {
        throw Exception('Akses ditolak: hanya superadmin yang bisa menghapus user.');
      }
      final success = await apiService.deleteUser(id);
      if (success) fetchUsers();
    });
  }

  Future<void> updateUserPassword(String id, String newPassword) async {
    await _runGuarded(() async {
      if (!_canSuperadminOrManajer) {
        throw Exception('Akses ditolak: hanya superadmin dan manajer yang bisa mengedit password.');
      }
      final success = await apiService.updateUserPassword(id, newPassword);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password berhasil diperbarui.')),
        );
      }
    });
  }

  Future<void> updateUserStatus(String id, String status) async {
    await _runGuarded(() async {
      if (!_canSuperadminOrManajer) {
        throw Exception('Akses ditolak: hanya superadmin dan manajer yang bisa mengubah status user.');
      }
      final success = await apiService.updateUserStatus(id, status);
      if (success) {
        fetchUsers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Status user berhasil diperbarui.')),
          );
        }
      }
    });
  }

  Future<void> addUserBranchRole(String userId, Map<String, dynamic> branchRole) async {
    await _runGuarded(() async {
      if (!_isSuperadmin) {
        throw Exception('Akses ditolak: hanya superadmin yang bisa mengubah branch/role user.');
      }
      final success = await apiService.addUserBranchRole(userId, branchRole);
      if (success) {
        fetchUsers();
        // If the user being modified is the current logged-in user, refresh their data
        final currentUserId = ref.read(userStateProvider).userId?.toString();
        if (currentUserId == userId) {
          await _refreshCurrentUserData();
        }
      }
    });
  }

  Future<void> removeUserBranchRole(String userId, String branchId, String role) async {
    await _runGuarded(() async {
      if (!_isSuperadmin) {
        throw Exception('Akses ditolak: hanya superadmin yang bisa mengubah branch/role user.');
      }
      final success = await apiService.removeUserBranchRole(userId, branchId, role);
      if (success) {
        fetchUsers();
        // If the user being modified is the current logged-in user, refresh their data
        final currentUserId = ref.read(userStateProvider).userId?.toString();
        if (currentUserId == userId) {
          await _refreshCurrentUserData();
        }
      }
    });
  }

  Future<void> _refreshCurrentUserData() async {
    try {
      // For now, we'll show a message to user to re-login to see changes
      // In a production app, you might want to store credentials securely and re-authenticate
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Branch/role baru telah ditambahkan. Silakan logout dan login kembali untuk melihat perubahan.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memperbarui data user: $e')),
        );
      }
    }
  }

  Future<void> showUserForm({Map<String, dynamic>? user}) async {
    if (!_isSuperadmin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Akses ditolak: hanya superadmin yang bisa mengubah data user.'),
        ),
      );
      return;
    }
    final formKey = GlobalKey<FormState>();
    String username = user?['username'] ?? '';
    String password = '';
    String selectedRole = '';
    String selectedBranchId = '';
    bool isPrimary = false;
    final isEdit = user != null;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEdit ? 'Edit User' : 'Tambah User'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: username,
                    decoration: const InputDecoration(labelText: 'Username'),
                    validator: (v) => v == null || v.isEmpty ? 'Username wajib diisi' : null,
                    onChanged: (v) => username = v,
                  ),
                  if (!isEdit) ...[
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                      validator: (v) => v == null || v.isEmpty ? 'Password wajib diisi' : null,
                      onChanged: (v) => password = v,
                    ),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: selectedBranchId.isNotEmpty ? selectedBranchId : null,
                    decoration: const InputDecoration(labelText: 'Branch'),
                    items: branches.map((branch) {
                      return DropdownMenuItem(
                        value: branch['branch_id'].toString(),
                        child: Text(_branchLabel(branch)),
                      );
                    }).toList(),
                    validator: (v) => v == null || v.isEmpty ? 'Branch wajib dipilih' : null,
                    onChanged: (v) => selectedBranchId = v ?? '',
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole.isNotEmpty ? selectedRole : null,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(value: 'superadmin', child: Text('Super Admin')),
                      DropdownMenuItem(value: 'admin_toko', child: Text('Admin Toko')),
                      DropdownMenuItem(value: 'kasir', child: Text('Kasir')),
                      DropdownMenuItem(value: 'cs', child: Text('Customer Service')),
                      DropdownMenuItem(value: 'tukang', child: Text('Tukang')),
                      DropdownMenuItem(value: 'manajer', child: Text('Manajer')),
                      DropdownMenuItem(value: 'admin_workshop', child: Text('Admin Workshop')),
                      DropdownMenuItem(value: 'stockist', child: Text('Stockist')),
                    ],
                    validator: (v) => v == null || v.isEmpty ? 'Role wajib dipilih' : null,
                    onChanged: (v) => selectedRole = v ?? '',
                  ),
                  CheckboxListTile(
                    title: const Text('Primary Branch'),
                    value: isPrimary,
                    onChanged: (v) => setState(() => isPrimary = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  final data = {
                    'username': username,
                    'role': selectedRole,
                    'branch_id': selectedBranchId,
                    'is_primary': isPrimary,
                  };
                  if (!isEdit) data['password'] = password;

                  final navigator = Navigator.of(context);

                  if (isEdit) {
                    await updateUser(user['user_id'].toString(), data);
                  } else {
                    await addUser(data);
                  }
                  navigator.pop();
                }
              },
              child: Text(isEdit ? 'Simpan' : 'Tambah'),
            ),
          ],
        );
      },
    );
  }

  Future<void> showAddBranchRoleDialog(String userId) async {
    final formKey = GlobalKey<FormState>();
    String selectedRole = '';
    String selectedBranchId = '';
    bool isPrimary = false;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Tambah Branch & Role'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Branch'),
                  items: branches.map((branch) {
                    return DropdownMenuItem(
                      value: branch['branch_id'].toString(),
                      child: Text(_branchLabel(branch)),
                    );
                  }).toList(),
                  validator: (v) => v == null || v.isEmpty ? 'Branch wajib dipilih' : null,
                  onChanged: (v) => selectedBranchId = v ?? '',
                ),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'superadmin', child: Text('Super Admin')),
                    DropdownMenuItem(value: 'admin_toko', child: Text('Admin Toko')),
                    DropdownMenuItem(value: 'kasir', child: Text('Kasir')),
                    DropdownMenuItem(value: 'cs', child: Text('Customer Service')),
                    DropdownMenuItem(value: 'tukang', child: Text('Tukang')),
                    DropdownMenuItem(value: 'manajer', child: Text('Manajer')),
                    DropdownMenuItem(value: 'admin_workshop', child: Text('Admin Workshop')),
                    DropdownMenuItem(value: 'stockist', child: Text('Stockist')),
                  ],
                  validator: (v) => v == null || v.isEmpty ? 'Role wajib dipilih' : null,
                  onChanged: (v) => selectedRole = v ?? '',
                ),
                CheckboxListTile(
                  title: const Text('Primary Branch'),
                  value: isPrimary,
                  onChanged: (v) => setState(() => isPrimary = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  final navigator = Navigator.of(context);
                  await addUserBranchRole(userId, {
                    'branch_id': selectedBranchId,
                    'role': selectedRole,
                    'is_primary': isPrimary,
                  });
                  navigator.pop();
                }
              },
              child: const Text('Tambah'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSuperadmin = ref.watch(userStateProvider).role.toString().trim().toLowerCase() == 'superadmin';
    final canSuperadminOrManajer = ref.watch(userStateProvider).role.toString().trim().toLowerCase() == 'superadmin' ||
        ref.watch(userStateProvider).role.toString().trim().toLowerCase() == 'manajer';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen User'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchUsers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text('Error: $error'))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total Users: ${users.length}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Tambah User'),
                            onPressed: isSuperadmin ? () => showUserForm() : null,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final user = users[index];
                          final userBranches = user['branches'] as List<dynamic>? ?? [];

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: ExpansionTile(
                              leading: const Icon(Icons.person),
                              title: Text(user['username'] ?? ''),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Status: ${user['status'] ?? 'Unknown'}'),
                                  Text('Branches: ${userBranches.length}'),
                                ],
                              ),
                              children: [
                                // List of branches and roles
                                if (userBranches.isNotEmpty) ...[
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Text('Branch & Role Assignments:', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                  ...userBranches.map((branch) => ListTile(
                                    leading: Icon(
                                      branch['is_primary'] == true ? Icons.star : Icons.business,
                                      color: branch['is_primary'] == true ? Colors.amber : Colors.grey,
                                    ),
                                    title: Text(branch['branch_name'] ?? 'Unknown Branch'),
                                    subtitle: Text('Role: ${branch['role'] ?? 'Unknown'}'),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: isSuperadmin
                                          ? () => removeUserBranchRole(
                                                user['user_id'].toString(),
                                                branch['branch_id'].toString(),
                                                branch['role'],
                                              )
                                          : null,
                                    ),
                                  )),
                                ],

                                // Add new branch/role button
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          icon: const Icon(Icons.add),
                                          label: const Text('Tambah Branch & Role'),
                                          onPressed: isSuperadmin
                                              ? () => showAddBranchRoleDialog(user['user_id'].toString())
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.edit),
                                        tooltip: 'Edit User',
                                        onPressed: isSuperadmin ? () => showUserForm(user: user) : null,
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.toggle_on_outlined),
                                        tooltip: 'Ubah Status',
                                        onPressed: canSuperadminOrManajer
                                            ? () async {
                                                final current = (user['status'] ?? 'active').toString().trim().toLowerCase();
                                                String selected = current == 'inactive' ? 'inactive' : 'active';

                                                final ok = await showDialog<bool>(
                                                  context: context,
                                                  builder: (context) => StatefulBuilder(
                                                    builder: (context, setLocal) {
                                                      return AlertDialog(
                                                        title: const Text('Ubah Status'),
                                                        content: Column(
                                                          mainAxisSize: MainAxisSize.min,
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text('User: ${user['username'] ?? ''}'),
                                                            const SizedBox(height: 12),
                                                            DropdownButtonFormField<String>(
                                                              value: selected,
                                                              decoration: const InputDecoration(labelText: 'Status'),
                                                              items: const [
                                                                DropdownMenuItem(value: 'active', child: Text('Aktif')),
                                                                DropdownMenuItem(value: 'inactive', child: Text('Nonaktif')),
                                                              ],
                                                              onChanged: (v) {
                                                                if (v != null) setLocal(() => selected = v);
                                                              },
                                                            ),
                                                          ],
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () => Navigator.pop(context, false),
                                                            child: const Text('Batal'),
                                                          ),
                                                          ElevatedButton(
                                                            onPressed: () => Navigator.pop(context, true),
                                                            child: const Text('Simpan'),
                                                          ),
                                                        ],
                                                      );
                                                    },
                                                  ),
                                                );

                                                if (ok == true) {
                                                  await updateUserStatus(user['user_id'].toString(), selected);
                                                }
                                              }
                                            : null,
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.lock_reset),
                                        tooltip: 'Ubah Password',
                                        onPressed: canSuperadminOrManajer
                                            ? () async {
                                                final passKey = GlobalKey<FormState>();
                                                String p1 = '';
                                                String p2 = '';

                                                final ok = await showDialog<bool>(
                                                  context: context,
                                                  builder: (context) => AlertDialog(
                                                    title: const Text('Ubah Password'),
                                                    content: Form(
                                                      key: passKey,
                                                      child: Column(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Text('User: ${user['username'] ?? ''}'),
                                                          const SizedBox(height: 12),
                                                          TextFormField(
                                                            decoration: const InputDecoration(labelText: 'Password baru'),
                                                            obscureText: true,
                                                            validator: (v) {
                                                              final s = (v ?? '').trim();
                                                              if (s.isEmpty) return 'Password wajib diisi';
                                                              if (s.length < 4) return 'Minimal 4 karakter';
                                                              return null;
                                                            },
                                                            onChanged: (v) => p1 = v,
                                                          ),
                                                          TextFormField(
                                                            decoration: const InputDecoration(labelText: 'Ulangi password baru'),
                                                            obscureText: true,
                                                            validator: (v) {
                                                              final s = (v ?? '').trim();
                                                              if (s.isEmpty) return 'Konfirmasi password wajib diisi';
                                                              if (s != p1) return 'Password tidak sama';
                                                              return null;
                                                            },
                                                            onChanged: (v) => p2 = v,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () => Navigator.pop(context, false),
                                                        child: const Text('Batal'),
                                                      ),
                                                      ElevatedButton(
                                                        onPressed: () {
                                                          if (passKey.currentState?.validate() ?? false) {
                                                            Navigator.pop(context, true);
                                                          }
                                                        },
                                                        child: const Text('Simpan'),
                                                      ),
                                                    ],
                                                  ),
                                                );

                                                if (ok == true) {
                                                  await updateUserPassword(
                                                    user['user_id'].toString(),
                                                    p2.trim(),
                                                  );
                                                }
                                              }
                                            : null,
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete),
                                        tooltip: 'Hapus User',
                                        onPressed: isSuperadmin
                                            ? () async {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: const Text('Konfirmasi'),
                                              content: const Text('Yakin ingin menghapus user ini?'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(context, false),
                                                  child: const Text('Batal'),
                                                ),
                                                TextButton(
                                                  onPressed: () => Navigator.pop(context, true),
                                                  child: const Text('Hapus'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            await deleteUser(user['user_id'].toString());
                                          }
                                        }
                                            : null,
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
    );
  }
}
