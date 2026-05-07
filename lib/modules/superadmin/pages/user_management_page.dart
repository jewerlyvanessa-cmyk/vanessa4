import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'user_api_service.dart';
import '../../../utils/network_config.dart';
import '../../../providers/user_state_provider.dart';
import 'package:vanessa3/core/theme/app_typography.dart';


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
    _bootstrap();
  }

  /// Cabang harus siap sebelum daftar user (form butuh opsi branch).
  Future<void> _bootstrap() async {
    await fetchBranches();
    await fetchUsers();
  }

  Future<void> _refreshUsersAndBranches() async {
    await fetchBranches();
    await fetchUsers();
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

    if (user != null) {
      final userBranches = user['branches'] as List<dynamic>? ?? [];
      Map<String, dynamic>? picked;
      for (final b in userBranches) {
        if (b is Map && b['is_primary'] == true) {
          picked = Map<String, dynamic>.from(b);
          break;
        }
      }
      picked ??= userBranches.isNotEmpty && userBranches.first is Map
          ? Map<String, dynamic>.from(userBranches.first as Map)
          : null;
      if (picked != null) {
        selectedBranchId = picked['branch_id']?.toString() ?? '';
        selectedRole = (picked['role'] ?? '').toString();
        isPrimary = picked['is_primary'] == true;
      }
    }

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                        key: ValueKey<String>('branch-$selectedBranchId-${branches.length}'),
                        initialValue: selectedBranchId.isNotEmpty ? selectedBranchId : null,
                        decoration: const InputDecoration(labelText: 'Branch'),
                        items: branches.map((branch) {
                          return DropdownMenuItem(
                            value: branch['branch_id'].toString(),
                            child: Text(_branchLabel(branch)),
                          );
                        }).toList(),
                        validator: (v) => v == null || v.isEmpty ? 'Branch wajib dipilih' : null,
                        onChanged: (v) => setDialogState(() => selectedBranchId = v ?? ''),
                      ),
                      DropdownButtonFormField<String>(
                        key: ValueKey<String>('role-$selectedRole'),
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
                        onChanged: (v) => setDialogState(() => selectedRole = v ?? ''),
                      ),
                      CheckboxListTile(
                        title: const Text('Primary Branch'),
                        value: isPrimary,
                        onChanged: (v) => setDialogState(() => isPrimary = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
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

                      final navigator = Navigator.of(dialogContext);

                      if (isEdit) {
                        await updateUser(user['user_id'].toString(), data);
                      } else {
                        await addUser(data);
                      }
                      if (navigator.canPop()) navigator.pop();
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

  Future<void> showAddBranchRoleDialog(String userId) async {
    final formKey = GlobalKey<FormState>();
    String selectedRole = '';
    String selectedBranchId = '';
    bool isPrimary = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Tambah Branch & Role'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>('add-br-$selectedBranchId-${branches.length}'),
                      initialValue: selectedBranchId.isNotEmpty ? selectedBranchId : null,
                      decoration: const InputDecoration(labelText: 'Branch'),
                      items: branches.map((branch) {
                        return DropdownMenuItem(
                          value: branch['branch_id'].toString(),
                          child: Text(_branchLabel(branch)),
                        );
                      }).toList(),
                      validator: (v) => v == null || v.isEmpty ? 'Branch wajib dipilih' : null,
                      onChanged: (v) => setDialogState(() => selectedBranchId = v ?? ''),
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>('add-role-$selectedRole'),
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
                      onChanged: (v) => setDialogState(() => selectedRole = v ?? ''),
                    ),
                    CheckboxListTile(
                      title: const Text('Primary Branch'),
                      value: isPrimary,
                      onChanged: (v) => setDialogState(() => isPrimary = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState?.validate() ?? false) {
                      final navigator = Navigator.of(dialogContext);
                      await addUserBranchRole(userId, {
                        'branch_id': selectedBranchId,
                        'role': selectedRole,
                        'is_primary': isPrimary,
                      });
                      if (navigator.canPop()) navigator.pop();
                    }
                  },
                  child: const Text('Tambah'),
                ),
              ],
            );
          },
        );
      },
    );
  }

String _branchAssignmentsSummary(Map<String, dynamic> user) {
    final userBranches = user['branches'] as List<dynamic>? ?? [];
    if (userBranches.isEmpty) return '—';
    final parts = <String>[];
    for (final b in userBranches.take(3)) {
      if (b is! Map) continue;
      final bn = b['branch_name']?.toString() ?? '';
      final r = b['role']?.toString() ?? '';
      final star = b['is_primary'] == true ? '★ ' : '';
      parts.add('$star$bn${r.isNotEmpty ? ' · $r' : ''}');
    }
    var s = parts.join('; ');
    if (userBranches.length > 3) s += ' (+${userBranches.length - 3})';
    return s;
  }

  Future<void> _openBranchesSheet(
    Map<String, dynamic> user,
    bool isSuperadmin,
  ) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final userBranches = user['branches'] as List<dynamic>? ?? [];
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.28,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  user['username']?.toString() ?? 'User',
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cabang & role',
                  style: Theme.of(sheetContext).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                if (userBranches.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Belum ada penugasan cabang'),
                  )
                else
                  ...userBranches.map((branch) {
                    if (branch is! Map) return const SizedBox.shrink();
                    return ListTile(
                      leading: Icon(
                        branch['is_primary'] == true
                            ? Icons.star
                            : Icons.business,
                        color: branch['is_primary'] == true
                            ? Colors.amber
                            : Colors.grey,
                      ),
                      title: Text(branch['branch_name']?.toString() ?? '—'),
                      subtitle: Text('Role: ${branch['role'] ?? '—'}'),
                      trailing: isSuperadmin
                          ? IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                Navigator.pop(sheetContext);
                                await removeUserBranchRole(
                                  user['user_id'].toString(),
                                  branch['branch_id'].toString(),
                                  branch['role']?.toString() ?? '',
                                );
                              },
                            )
                          : null,
                    );
                  }),
                if (isSuperadmin) ...[
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah cabang & role'),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      showAddBranchRoleDialog(user['user_id'].toString());
                    },
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleUserMenuAction(
    String action,
    Map<String, dynamic> user,
    bool isSuperadmin,
    bool canSuperadminOrManajer,
  ) async {
    switch (action) {
      case 'branches':
        await _openBranchesSheet(user, isSuperadmin);
        break;
      case 'edit':
        if (isSuperadmin) await showUserForm(user: user);
        break;
      case 'add_branch':
        if (isSuperadmin) {
          await showAddBranchRoleDialog(user['user_id'].toString());
        }
        break;
      case 'status':
        if (!canSuperadminOrManajer) return;
        final current =
            (user['status'] ?? 'active').toString().trim().toLowerCase();
        var selected = current == 'inactive' ? 'inactive' : 'active';
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
                      key: ValueKey<String>(selected),
                      initialValue: selected,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const [
                        DropdownMenuItem(value: 'active', child: Text('Aktif')),
                        DropdownMenuItem(
                          value: 'inactive',
                          child: Text('Nonaktif'),
                        ),
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
        break;
      case 'password':
        if (!canSuperadminOrManajer) return;
        final passKey = GlobalKey<FormState>();
        var p1 = '';
        var p2 = '';
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
                    decoration:
                        const InputDecoration(labelText: 'Password baru'),
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
                    decoration: const InputDecoration(
                      labelText: 'Ulangi password baru',
                    ),
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
          await updateUserPassword(user['user_id'].toString(), p2.trim());
        }
        break;
      case 'delete':
        if (!isSuperadmin) return;
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
        break;
    }
  }

  List<PopupMenuEntry<String>> _userTableMenuItems(
    BuildContext context,
    bool isSuperadmin,
    bool canSuperadminOrManajer,
  ) {
    final cs = Theme.of(context).colorScheme;
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(
        value: 'branches',
        child: Text('Cabang & role'),
      ),
    ];
    if (isSuperadmin) {
      items.add(const PopupMenuItem(value: 'edit', child: Text('Edit user')));
      items.add(
        const PopupMenuItem(
          value: 'add_branch',
          child: Text('Tambah cabang & role'),
        ),
      );
    }
    if (canSuperadminOrManajer) {
      items.add(const PopupMenuItem(value: 'status', child: Text('Ubah status')));
      items.add(
        const PopupMenuItem(value: 'password', child: Text('Ubah password')),
      );
    }
    if (isSuperadmin) {
      items.add(const PopupMenuDivider());
      items.add(
        PopupMenuItem(
          value: 'delete',
          child: Text('Hapus', style: TextStyle(color: cs.error)),
        ),
      );
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final isSuperadmin = ref.watch(userStateProvider).role.toString().trim().toLowerCase() ==
        'superadmin';
    final canSuperadminOrManajer = ref.watch(userStateProvider).role.toString().trim().toLowerCase() ==
            'superadmin' ||
        ref.watch(userStateProvider).role.toString().trim().toLowerCase() ==
            'manajer';
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen User'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshUsersAndBranches,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text('Error: $error'))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 600;
                    final pad = narrow ? 12.0 : 16.0;
                    const desktopTableW = 920.0;
                    final panelW = constraints.maxWidth;
                    final BoxConstraints tableBoxConstraints;
                    if (narrow) {
                      tableBoxConstraints = BoxConstraints.tightFor(width: panelW - pad * 2);
                    } else if (panelW - pad * 2 >= desktopTableW) {
                      tableBoxConstraints =
                          BoxConstraints.tightFor(width: desktopTableW);
                    } else {
                      tableBoxConstraints =
                          const BoxConstraints(minWidth: desktopTableW);
                    }

                    final menuItems =
                        _userTableMenuItems(context, isSuperadmin, canSuperadminOrManajer);

                    final rows = <DataRow>[];
                    for (var i = 0; i < users.length; i++) {
                      final user = users[i];
                      final userBranches =
                          user['branches'] as List<dynamic>? ?? [];
                      final statusStr =
                          (user['status'] ?? '—').toString();
                      final userMap =
                          Map<String, dynamic>.from(user as Map);

                      final actionCell = DataCell(
                        Align(
                          alignment: Alignment.centerRight,
                          child: PopupMenuButton<String>(
                            tooltip: 'Tindakan',
                            icon: const Icon(Icons.more_vert),
                            onSelected: (v) => _handleUserMenuAction(
                              v,
                              userMap,
                              isSuperadmin,
                              canSuperadminOrManajer,
                            ),
                            itemBuilder: (context) => menuItems,
                          ),
                        ),
                      );

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
                          cells: narrow
                              ? [
                                  DataCell(
                                    Text(
                                      user['username']?.toString() ?? '—',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      statusStr,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                  ),
                                  actionCell,
                                ]
                              : [
                                  DataCell(
                                    Text(
                                      user['username']?.toString() ?? '—',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      statusStr,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      '${userBranches.length} cabang',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      _branchAssignmentsSummary(userMap),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  actionCell,
                                ],
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(pad, pad, pad, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Total user: ${users.length}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.add),
                                label: const Text('Tambah user'),
                                onPressed:
                                    isSuperadmin ? () => showUserForm() : null,
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(pad, 0, pad, 8),
                            child: users.isEmpty
                                ? const Center(
                                    child: Text('Belum ada data user'),
                                  )
                                : Material(
                                    elevation: 0,
                                    color: cs.surfaceContainerLow
                                        .withValues(alpha: 0.65),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: cs.outlineVariant
                                            .withValues(alpha: 0.45),
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Scrollbar(
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.vertical,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Align(
                                            alignment: Alignment.topLeft,
                                            child: ConstrainedBox(
                                              constraints: tableBoxConstraints,
                                              child: DataTable(
                                                headingRowColor:
                                                    WidgetStateProperty.all(
                                                  cs.surfaceContainerHigh,
                                                ),
dataRowMinHeight:
                                                    narrow ? 40 : 44,
                                                dataRowMaxHeight:
                                                    narrow ? 52 : 64,
                                                columnSpacing:
                                                    narrow ? 8 : 14,
                                                horizontalMargin:
                                                    narrow ? 8 : 12,
                                                showCheckboxColumn: false,
                                                dividerThickness: 0.5,
                                                columns: narrow
                                                    ? [
                                                        DataColumn(
                                                          label: dataTableColumnLabel(
                                                            'Username',
                                                          ),
                                                        ),
                                                        DataColumn(
                                                          label: dataTableColumnLabel(
                                                            'Status',
                                                          ),
                                                        ),
                                                        const DataColumn(
                                                          label: SizedBox(
                                                            width: 44,
                                                          ),
                                                        ),
                                                      ]
                                                    : [
                                                        DataColumn(
                                                          label: dataTableColumnLabel(
                                                            'Username',
                                                          ),
                                                        ),
                                                        DataColumn(
                                                          label: dataTableColumnLabel(
                                                            'Status',
                                                          ),
                                                        ),
                                                        DataColumn(
                                                          label: dataTableColumnLabel(
                                                            'Cabang',
                                                          ),
                                                        ),
                                                        DataColumn(
                                                          label: dataTableColumnLabel(
                                                            'Penugasan',
                                                          ),
                                                        ),
                                                        const DataColumn(
                                                          label: SizedBox(
                                                            width: 48,
                                                          ),
                                                        ),
                                                      ],
                                                rows: rows,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }
}
