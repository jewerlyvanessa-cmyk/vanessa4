import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/utils/network_config.dart';

class EmployeeManagementPage extends ConsumerStatefulWidget {
  const EmployeeManagementPage({super.key});

  @override
  ConsumerState<EmployeeManagementPage> createState() =>
      _EmployeeManagementPageState();
}

class _EmployeeManagementPageState
    extends ConsumerState<EmployeeManagementPage> {
  List<dynamic> _allEmployees = []; // Store all employees for summary
  List<dynamic> _employees = []; // Filtered list for display
  bool _isLoading = true;
  String _error = '';

  List<Map<String, dynamic>> _asEmployeeMaps(List<dynamic> list) {
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  String _userKeyForRow(Map<String, dynamic> row) {
    final userId = (row['user_id'] ?? row['id'] ?? row['userId'] ?? '').toString().trim();
    if (userId.isNotEmpty) return 'id:$userId';
    final username = (row['username'] ?? row['name'] ?? '').toString().trim().toLowerCase();
    return 'u:$username';
  }

  List<_EmployeeGroup> _groupByUser(List<Map<String, dynamic>> rows) {
    final Map<String, List<Map<String, dynamic>>> byUser = {};
    for (final row in rows) {
      final key = _userKeyForRow(row);
      byUser.putIfAbsent(key, () => []);
      byUser[key]!.add(row);
    }

    final groups = byUser.entries.map((e) {
      // Use the most complete row as "user" row.
      final items = e.value;
      items.sort((a, b) {
        final au = (a['username'] ?? '').toString().length;
        final bu = (b['username'] ?? '').toString().length;
        return bu.compareTo(au);
      });
      return _EmployeeGroup(user: items.first, assignments: items);
    }).toList();

    groups.sort((a, b) {
      final an = (a.user['username'] ?? '').toString().toLowerCase();
      final bn = (b.user['username'] ?? '').toString().toLowerCase();
      return an.compareTo(bn);
    });
    return groups;
  }

  int _countUniqueUsers(Iterable<Map<String, dynamic>> rows) {
    final keys = rows.map(_userKeyForRow).where((k) => k != 'u:').toSet();
    return keys.length;
  }

  int _countUniqueUsersByStatus(List<Map<String, dynamic>> rows, String status) {
    final keys = <String>{};
    for (final row in rows) {
      final rowStatus = (row['status'] ?? '').toString();
      if (rowStatus == status) {
        keys.add(_userKeyForRow(row));
      }
    }
    keys.remove('u:');
    return keys.length;
  }

  int _countUniqueUsersWithRole(List<Map<String, dynamic>> rows, String role) {
    final keys = <String>{};
    for (final row in rows) {
      final rowRole = (row['role'] ?? '').toString();
      if (rowRole == role) {
        keys.add(_userKeyForRow(row));
      }
    }
    keys.remove('u:');
    return keys.length;
  }

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;

      final response = await http.get(
        Uri.parse('$baseUrl/employees?branch_id=${userState.branch}'),
        headers: NetworkConfig.defaultHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Store all employees for summary cards
        final allEmployees = List<dynamic>.from(data);
        // Filter to only show active employees in the list
        final activeEmployees = allEmployees
            .where((employee) => employee['status'] == 'active')
            .toList();

        setState(() {
          _allEmployees = allEmployees;
          _employees = activeEmployees;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Gagal memuat data karyawan';
          _isLoading = false;
        });
      }
    } catch (error) {
      setState(() {
        _error = 'Error: $error';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Karyawan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEmployees,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadEmployees,
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            )
          : Builder(
              builder: (context) {
                final allRows = _asEmployeeMaps(_allEmployees);
                final activeRows = allRows
                    .where((e) => (e['status'] ?? '').toString() == 'active')
                    .toList();

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary Cards
                      Row(
                        children: [
                          Expanded(
                            child: _buildSummaryCard(
                              'Total Karyawan',
                              _countUniqueUsers(allRows),
                              Icons.people,
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildSummaryCard(
                              'Aktif',
                              _countUniqueUsersByStatus(allRows, 'active'),
                              Icons.check_circle,
                              Colors.green,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child: _buildSummaryCard(
                              'Tidak Aktif',
                              _countUniqueUsersByStatus(allRows, 'inactive'),
                              Icons.cancel,
                              Colors.red,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildSummaryCard(
                              'CS',
                              _countUniqueUsersWithRole(activeRows, 'cs'),
                              Icons.support_agent,
                              Colors.purple,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Employees List
                      Text(
                        'Daftar Karyawan Aktif (${_countUniqueUsers(activeRows)})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),

                      if (_employees.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('Belum ada data karyawan'),
                          ),
                        )
                      else
                        Builder(
                          builder: (context) {
                            final groups = _groupByUser(activeRows);

                            return ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: groups.length,
                              itemBuilder: (context, index) {
                                final group = groups[index];
                                final user = group.user;
                                final username =
                                    (user['username'] ?? 'N/A').toString();
                                final status =
                                    (user['status'] ?? 'active').toString();
                                final assignments = group.assignments;

                                final roles = assignments
                                    .map(
                                      (a) =>
                                          (a['role'] ?? '').toString().trim(),
                                    )
                                    .where((r) => r.isNotEmpty)
                                    .toSet()
                                    .toList()
                                  ..sort();

                                final primaryRole = roles.isNotEmpty
                                    ? roles.first
                                    : (user['role'] ?? '');
                                final actionTarget = <String, dynamic>{
                                  ...user,
                                  if (primaryRole.toString().isNotEmpty)
                                    'role': primaryRole,
                                };

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ExpansionTile(
                                    leading: CircleAvatar(
                                      backgroundColor: _getRoleColor(
                                        primaryRole.toString(),
                                      ),
                                      child: Text(
                                        username.isNotEmpty
                                            ? username
                                                .substring(0, 1)
                                                .toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    title: Text(username),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Status: ${status == 'active' ? 'Aktif' : 'Tidak Aktif'}',
                                        ),
                                        Text(
                                          'Role: ${roles.isEmpty ? _getRoleLabel(primaryRole.toString()) : roles.map(_getRoleLabel).join(', ')}',
                                        ),
                                      ],
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (action) =>
                                          _handleEmployeeAction(
                                            actionTarget,
                                            action,
                                          ),
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit'),
                                        ),
                                        PopupMenuItem(
                                          value: 'toggle_status',
                                          child: Text('Ubah Status'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Hapus'),
                                        ),
                                      ],
                                    ),
                                    children: [
                                      const Divider(height: 1),
                                      ...assignments.map((a) {
                                        final role =
                                            (a['role'] ?? '').toString();
                                        final roleLabel = _getRoleLabel(role);
                                        final rowStatus =
                                            (a['status'] ?? status).toString();
                                        final userId = (a['user_id'] ??
                                                user['user_id'] ??
                                                '')
                                            .toString();
                                        return ListTile(
                                          leading: Icon(
                                            Icons.badge,
                                            color: _getRoleColor(role),
                                          ),
                                          title: Text(roleLabel),
                                          subtitle: Text('User ID: $userId'),
                                          trailing: Text(
                                            rowStatus == 'active'
                                                ? 'aktif'
                                                : 'nonaktif',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: rowStatus == 'active'
                                                  ? Colors.green
                                                  : Colors.red,
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    int count,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Color _getRoleColor(String? role) {
    switch (role) {
      case 'cs':
        return Colors.blue;
      case 'kasir':
        return Colors.green;
      case 'admin_toko':
        return Colors.orange;
      case 'admin_workshop':
        return Colors.purple;
      case 'tukang':
        return Colors.red;
      case 'manajer':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _getRoleLabel(String? role) {
    switch (role) {
      case 'cs':
        return 'Customer Service';
      case 'kasir':
        return 'Kasir';
      case 'admin_toko':
        return 'Admin Toko';
      case 'admin_workshop':
        return 'Admin Workshop';
      case 'tukang':
        return 'Tukang';
      case 'manajer':
        return 'Manajer';
      case 'superadmin':
        return 'Super Admin';
      default:
        return 'Unknown';
    }
  }

  void _handleEmployeeAction(Map<String, dynamic> employee, String action) {
    switch (action) {
      case 'edit':
        _showEditEmployeeDialog(employee);
        break;
      case 'toggle_status':
        _toggleEmployeeStatus(employee);
        break;
      case 'delete':
        _showDeleteConfirmation(employee);
        break;
    }
  }

  void _showEditEmployeeDialog(Map<String, dynamic> employee) {
    showDialog(
      context: context,
      builder: (context) => EditEmployeeDialog(employee: employee),
    ).then((_) => _loadEmployees());
  }

  Future<void> _toggleEmployeeStatus(Map<String, dynamic> employee) async {
    try {
      final baseUrl = NetworkConfig.baseUrl;

      final newStatus = employee['status'] == 'active' ? 'inactive' : 'active';

      final response = await http.put(
        Uri.parse('$baseUrl/employees/${employee['user_id']}'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({'status': newStatus}),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Status karyawan berhasil diubah menjadi $newStatus',
              ),
            ),
          );
        }
        _loadEmployees();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal mengubah status karyawan')),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $error')));
      }
    }
  }

  void _showDeleteConfirmation(Map<String, dynamic> employee) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Hapus'),
        content: Text(
          'Apakah Anda yakin ingin menghapus karyawan ${employee['username']}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteEmployee(employee);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEmployee(Map<String, dynamic> employee) async {
    try {
      final baseUrl = NetworkConfig.baseUrl;

      final response = await http.delete(
        Uri.parse('$baseUrl/employees/${employee['user_id']}'),
        headers: NetworkConfig.defaultHeaders,
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Karyawan berhasil dihapus')),
          );
        }
        _loadEmployees();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal menghapus karyawan')),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $error')));
      }
    }
  }
}

class _EmployeeGroup {
  final Map<String, dynamic> user;
  final List<Map<String, dynamic>> assignments;
  const _EmployeeGroup({required this.user, required this.assignments});
}

class AddEmployeeDialog extends StatefulWidget {
  const AddEmployeeDialog({super.key});

  @override
  State<AddEmployeeDialog> createState() => _AddEmployeeDialogState();
}

class _AddEmployeeDialogState extends State<AddEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedRole = 'cs';

  final List<String> _roles = [
    'cs',
    'kasir',
    'admin_toko',
    'admin_workshop',
    'tukang',
    'manajer',
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tambah Karyawan'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Username wajib diisi' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Password wajib diisi' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                ),
                initialValue: _selectedRole,
                items: _roles.map((role) {
                  return DropdownMenuItem(
                    value: role,
                    child: Text(_getRoleLabel(role)),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedRole = value!),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        ElevatedButton(onPressed: _submitEmployee, child: const Text('Tambah')),
      ],
    );
  }

  String _getRoleLabel(String role) {
    switch (role) {
      case 'cs':
        return 'Customer Service';
      case 'kasir':
        return 'Kasir';
      case 'admin_toko':
        return 'Admin Toko';
      case 'admin_workshop':
        return 'Admin Workshop';
      case 'tukang':
        return 'Tukang';
      case 'manajer':
        return 'Manajer';
      default:
        return role;
    }
  }

  Future<void> _submitEmployee() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final baseUrl = NetworkConfig.baseUrl;

      final userState = context
          .findAncestorStateOfType<_EmployeeManagementPageState>()
          ?.ref
          .read(userStateProvider);

      final employeeData = {
        'username': _usernameController.text,
        'password': _passwordController.text,
        'role': _selectedRole,
        'branch_id': userState?.branch ?? '',
        'status': 'active',
      };

      final response = await http.post(
        Uri.parse('$baseUrl/employees'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode(employeeData),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Karyawan berhasil ditambahkan')),
          );
        }
        // Refresh the employee list
        if (mounted) {
          context
              .findAncestorStateOfType<_EmployeeManagementPageState>()
              ?._loadEmployees();
          Navigator.of(context).pop();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Gagal menambahkan karyawan: ${response.statusCode}',
              ),
            ),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $error')));
      }
    }
  }
}

class EditEmployeeDialog extends StatefulWidget {
  final Map<String, dynamic> employee;

  const EditEmployeeDialog({super.key, required this.employee});

  @override
  State<EditEmployeeDialog> createState() => _EditEmployeeDialogState();
}

class _EditEmployeeDialogState extends State<EditEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _username;
  late String _selectedRole;

  final List<String> _roles = [
    'cs',
    'kasir',
    'admin_toko',
    'admin_workshop',
    'tukang',
    'manajer',
  ];

  @override
  void initState() {
    super.initState();
    _username = widget.employee['username'] ?? '';
    _selectedRole = widget.employee['role'] ?? 'cs';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Karyawan'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
                initialValue: _username,
                onChanged: (value) => setState(() => _username = value),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Username wajib diisi' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                ),
                initialValue: _selectedRole,
                items: _roles.map((role) {
                  return DropdownMenuItem(
                    value: role,
                    child: Text(_getRoleLabel(role)),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedRole = value!),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        ElevatedButton(onPressed: _updateEmployee, child: const Text('Update')),
      ],
    );
  }

  String _getRoleLabel(String role) {
    switch (role) {
      case 'cs':
        return 'Customer Service';
      case 'kasir':
        return 'Kasir';
      case 'admin_toko':
        return 'Admin Toko';
      case 'admin_workshop':
        return 'Admin Workshop';
      case 'tukang':
        return 'Tukang';
      case 'manajer':
        return 'Manajer';
      default:
        return role;
    }
  }

  Future<void> _updateEmployee() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final baseUrl = NetworkConfig.baseUrl;

      final employeeData = {'username': _username, 'role': _selectedRole};

      final response = await http.put(
        Uri.parse('$baseUrl/employees/${widget.employee['user_id']}'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode(employeeData),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Karyawan berhasil diperbarui')),
          );
        }
        // Refresh the employee list
        if (mounted) {
          context
              .findAncestorStateOfType<_EmployeeManagementPageState>()
              ?._loadEmployees();
          Navigator.of(context).pop();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Gagal memperbarui karyawan: ${response.statusCode}',
              ),
            ),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $error')));
      }
    }
  }
}
