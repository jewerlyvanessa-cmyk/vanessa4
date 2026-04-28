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

  @override
  void initState() {
    super.initState();
    apiService = UserApiService(baseUrl: NetworkConfig.baseUrl);
    fetchUsers();
    fetchBranches();
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
    final success = await apiService.addUser(user);
    if (success) fetchUsers();
  }

  Future<void> updateUser(String id, Map<String, dynamic> user) async {
    final success = await apiService.updateUser(id, user);
    if (success) fetchUsers();
  }

  Future<void> deleteUser(String id) async {
    final success = await apiService.deleteUser(id);
    if (success) fetchUsers();
  }

  Future<void> addUserBranchRole(String userId, Map<String, dynamic> branchRole) async {
    final success = await apiService.addUserBranchRole(userId, branchRole);
    if (success) {
      fetchUsers();
      // If the user being modified is the current logged-in user, refresh their data
      final currentUserId = ref.read(userStateProvider).userId?.toString();
      if (currentUserId == userId) {
        await _refreshCurrentUserData();
      }
    }
  }

  Future<void> removeUserBranchRole(String userId, String branchId, String role) async {
    final success = await apiService.removeUserBranchRole(userId, branchId, role);
    if (success) {
      fetchUsers();
      // If the user being modified is the current logged-in user, refresh their data
      final currentUserId = ref.read(userStateProvider).userId?.toString();
      if (currentUserId == userId) {
        await _refreshCurrentUserData();
      }
    }
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
                        child: Text(branch['name'] ?? 'Unknown Branch'),
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
                      child: Text(branch['name'] ?? 'Unknown Branch'),
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
                            onPressed: () => showUserForm(),
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
                                      onPressed: () => removeUserBranchRole(
                                        user['user_id'].toString(),
                                        branch['branch_id'].toString(),
                                        branch['role'],
                                      ),
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
                                          onPressed: () => showAddBranchRoleDialog(user['user_id'].toString()),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.edit),
                                        tooltip: 'Edit User',
                                        onPressed: () => showUserForm(user: user),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete),
                                        tooltip: 'Hapus User',
                                        onPressed: () async {
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
                                        },
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
