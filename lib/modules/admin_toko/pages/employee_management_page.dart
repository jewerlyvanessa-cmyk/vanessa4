import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/modules/admin_toko/widgets/employee_assignments_sheet.dart';
import 'package:vanessa3/modules/admin_toko/widgets/employee_dialogs.dart';
import 'package:vanessa3/modules/admin_toko/widgets/employees_management_body.dart';
import 'package:vanessa3/providers/user_state_provider.dart';

class EmployeeManagementPage extends ConsumerStatefulWidget {
  const EmployeeManagementPage({super.key});

  @override
  ConsumerState<EmployeeManagementPage> createState() =>
      _EmployeeManagementPageState();
}

class _EmployeeManagementPageState
    extends ConsumerState<EmployeeManagementPage> {
  List<dynamic> _allEmployees = [];
  bool _isLoading = true;
  String _error = '';

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
        setState(() {
          _allEmployees = List<dynamic>.from(data);
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

  void _showAddEmployeeDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AddEmployeeDialog(onSaved: _loadEmployees),
    );
  }

  void _handleEmployeeAction(Map<String, dynamic> employee, String action) {
    switch (action) {
      case 'edit':
        showDialog<void>(
          context: context,
          builder: (context) => EditEmployeeDialog(
            employee: employee,
            onSaved: _loadEmployees,
          ),
        );
        break;
      case 'toggle_status':
        _toggleEmployeeStatus(employee);
        break;
      case 'delete':
        showDeleteEmployeeConfirmation(
          context,
          employee: employee,
          onConfirmDelete: () => _deleteEmployee(employee),
        );
        break;
    }
  }

  Future<void> _toggleEmployeeStatus(Map<String, dynamic> employee) async {
    try {
      final newStatus =
          employee['status'] == 'active' ? 'inactive' : 'active';

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
        await _loadEmployees();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal mengubah status karyawan')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $error')),
        );
      }
    }
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
        await _loadEmployees();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menghapus karyawan')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $error')),
        );
      }
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddEmployeeDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Tambah'),
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
              : EmployeesManagementBody(
                  allEmployees: _allEmployees,
                  onEmployeeAction: _handleEmployeeAction,
                  onShowDetail: (username, status, assignments) {
                    showEmployeeAssignmentsSheet(
                      context,
                      username: username,
                      defaultStatus: status,
                      assignments: assignments,
                    );
                  },
                ),
    );
  }
}
