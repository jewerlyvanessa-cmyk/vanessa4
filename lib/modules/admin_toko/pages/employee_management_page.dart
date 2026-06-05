import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

class EmployeeManagementPage extends ConsumerStatefulWidget {
  const EmployeeManagementPage({super.key});

  @override
  ConsumerState<EmployeeManagementPage> createState() =>
      _EmployeeManagementPageState();
}

class _EmployeeManagementPageState
    extends ConsumerState<EmployeeManagementPage> {
  List<dynamic> _allEmployees = []; // Store all employees for summary + table
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

      final response = await ApiClient.get(
        '/employees',
        query: {'branch_id': userState.branch.toString()},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Store all employees for summary cards
        final allEmployees = List<dynamic>.from(data);
        setState(() {
          _allEmployees = allEmployees;
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

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 600;
                    final pad = narrow ? 12.0 : 16.0;
                    const desktopTableW = 880.0;
                    final panelW = constraints.maxWidth;
                    final BoxConstraints tableBoxConstraints;
                    if (narrow) {
                      tableBoxConstraints =
                          BoxConstraints.tightFor(width: panelW - pad * 2);
                    } else if (panelW - pad * 2 >= desktopTableW) {
                      tableBoxConstraints =
                          BoxConstraints.tightFor(width: desktopTableW);
                    } else {
                      tableBoxConstraints =
                          const BoxConstraints(minWidth: desktopTableW);
                    }
                    final cs = Theme.of(context).colorScheme;
                    final groups = _groupByUser(activeRows);

final rows = <DataRow>[];
                    for (var i = 0; i < groups.length; i++) {
                      final group = groups[i];
                      final user = group.user;
                      final username = (user['username'] ?? 'N/A').toString();
                      final status = (user['status'] ?? 'active').toString();
                      final assignments = group.assignments;
                      final roles = assignments
                          .map((a) => (a['role'] ?? '').toString().trim())
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
                      final roleText = roles.isEmpty
                          ? _getRoleLabel(primaryRole.toString())
                          : roles.map(_getRoleLabel).join(', ');
                      final statusLabel =
                          status == 'active' ? 'Aktif' : 'Tidak aktif';

                      final menu = <PopupMenuEntry<String>>[
                        const PopupMenuItem(
                          value: 'detail',
                          child: Text('Detail penugasan'),
                        ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit'),
                        ),
                        const PopupMenuItem(
                          value: 'toggle_status',
                          child: Text('Ubah status'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Hapus'),
                        ),
                      ];

                      final actionCell = DataCell(
                        Align(
                          alignment: Alignment.centerRight,
                          child: PopupMenuButton<String>(
                            tooltip: 'Tindakan',
                            icon: const Icon(Icons.more_vert),
                            onSelected: (v) {
                              if (v == 'detail') {
                                _showAssignmentsSheet(
                                  context,
                                  username,
                                  status,
                                  assignments,
                                );
                              } else {
                                _handleEmployeeAction(actionTarget, v);
                              }
                            },
                            itemBuilder: (context) => menu,
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
                                      username,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      statusLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  actionCell,
                                ]
                              : [
                                  DataCell(
                                    Text(
                                      username,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(statusLabel)),
                                  DataCell(
                                    Text(
                                      roleText,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              narrow
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        IntrinsicHeight(
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Expanded(
                                                child: _buildSummaryCard(
                                                  context,
                                                  _countUniqueUsers(allRows),
                                                  Icons.people,
                                                  Colors.blue,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: _buildSummaryCard(
                                                  context,
                                                  _countUniqueUsersByStatus(
                                                    allRows,
                                                    'active',
                                                  ),
                                                  Icons.check_circle,
                                                  Colors.green,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        IntrinsicHeight(
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Expanded(
                                                child: _buildSummaryCard(
                                                  context,
                                                  _countUniqueUsersByStatus(
                                                    allRows,
                                                    'inactive',
                                                  ),
                                                  Icons.cancel,
                                                  Colors.red,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: _buildSummaryCard(
                                                  context,
                                                  _countUniqueUsersWithRole(
                                                    activeRows,
                                                    'cs',
                                                  ),
                                                  Icons.support_agent,
                                                  Colors.purple,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    )
                                  : IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            child: _buildSummaryCard(
                                              context,
                                              _countUniqueUsers(allRows),
                                              Icons.people,
                                              Colors.blue,
                                            ),
                                          ),
                                          SizedBox(width: narrow ? 8 : 16),
                                          Expanded(
                                            child: _buildSummaryCard(
                                              context,
                                              _countUniqueUsersByStatus(
                                                allRows,
                                                'active',
                                              ),
                                              Icons.check_circle,
                                              Colors.green,
                                            ),
                                          ),
                                          SizedBox(width: narrow ? 8 : 16),
                                          Expanded(
                                            child: _buildSummaryCard(
                                              context,
                                              _countUniqueUsersByStatus(
                                                allRows,
                                                'inactive',
                                              ),
                                              Icons.cancel,
                                              Colors.red,
                                            ),
                                          ),
                                          SizedBox(width: narrow ? 8 : 16),
                                          Expanded(
                                            child: _buildSummaryCard(
                                              context,
                                              _countUniqueUsersWithRole(
                                                activeRows,
                                                'cs',
                                              ),
                                              Icons.support_agent,
                                              Colors.purple,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                              const SizedBox(height: 12),
                              Text(
                                'Daftar karyawan aktif (${_countUniqueUsers(activeRows)})',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(pad, 0, pad, 8),
                            child: groups.isEmpty
                                ? const Center(
                                    child: Text('Belum ada data karyawan'),
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
                                                    narrow ? 52 : 60,
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
                                                            'Nama',
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
                                                          label: dataTableColumnLabel('Nama'),
                                                        ),
                                                        DataColumn(
                                                          label:
                                                              dataTableColumnLabel('Status'),
                                                        ),
                                                        DataColumn(
                                                          label: dataTableColumnLabel('Role'),
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
                );
              },
            ),
    );
  }

  void _showAssignmentsSheet(
    BuildContext context,
    String username,
    String defaultStatus,
    List<Map<String, dynamic>> assignments,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  username,
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Penugasan role',
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
                const Divider(height: 24),
                if (assignments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Tidak ada baris penugasan'),
                  )
                else
                  ...assignments.map((a) {
                    final role = (a['role'] ?? '').toString();
                    final rowStatus =
                        (a['status'] ?? defaultStatus).toString();
                    final userId = (a['user_id'] ?? '').toString();
                    return ListTile(
                      leading: Icon(
                        Icons.badge,
                        color: _getRoleColor(role),
                      ),
                      title: Text(_getRoleLabel(role)),
                      subtitle: Text('User ID: $userId'),
                      trailing: Text(
                        rowStatus == 'active' ? 'aktif' : 'nonaktif',
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
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    int count,
    IconData icon,
    Color color,
  ) {
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const Spacer(),
            Text(
              count.toString(),
              style: tt.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
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
      case 'admin_warehouse':
        return Colors.brown;
      case 'stockist':
        return Colors.blueGrey;
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
      case 'admin_warehouse':
        return 'Admin Warehouse';
      case 'stockist':
        return 'Stockist';
      case 'tukang':
        return 'Tukang';
      case 'manajer':
        return 'Manajer';
      case 'superadmin':
        return 'Super Admin';
      default:
        return role?.isNotEmpty == true ? role! : 'Unknown';
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
      final newStatus = employee['status'] == 'active' ? 'inactive' : 'active';

      final response = await ApiClient.put(
        '/employees/${employee['user_id']}',
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
      final response = await ApiClient.delete(
        '/employees/${employee['user_id']}',
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
    'admin_warehouse',
    'stockist',
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
      case 'admin_warehouse':
        return 'Admin Warehouse';
      case 'stockist':
        return 'Stockist';
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

      final response = await ApiClient.post(
        '/employees',
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
    'admin_warehouse',
    'stockist',
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
      case 'admin_warehouse':
        return 'Admin Warehouse';
      case 'stockist':
        return 'Stockist';
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
      final employeeData = {'username': _username, 'role': _selectedRole};

      final response = await ApiClient.put(
        '/employees/${widget.employee['user_id']}',
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
