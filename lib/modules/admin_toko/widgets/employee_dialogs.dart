import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/modules/admin_toko/logic/employee_role_utils.dart';
import 'package:vanessa3/providers/user_state_provider.dart';

class AddEmployeeDialog extends ConsumerStatefulWidget {
  const AddEmployeeDialog({super.key, required this.onSaved});

  final VoidCallback onSaved;

  @override
  ConsumerState<AddEmployeeDialog> createState() => _AddEmployeeDialogState();
}

class _AddEmployeeDialogState extends ConsumerState<AddEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedRole = 'cs';

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
                items: EmployeeRoleUtils.assignableRoles
                    .map(
                      (role) => DropdownMenuItem(
                        value: role,
                        child: Text(EmployeeRoleUtils.label(role)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _selectedRole = value);
                },
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

  Future<void> _submitEmployee() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final branchId = ref.read(userStateProvider).branch;
      final employeeData = {
        'username': _usernameController.text,
        'password': _passwordController.text,
        'role': _selectedRole,
        'branch_id': branchId,
        'status': 'active',
      };

      final response = await ApiClient.post(
        '/employees',
        body: jsonEncode(employeeData),
      );

      if (!mounted) return;
      if (response.statusCode == 201 || response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Karyawan berhasil ditambahkan')),
        );
        widget.onSaved();
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal menambahkan karyawan: ${response.statusCode}',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error')),
      );
    }
  }
}

class EditEmployeeDialog extends StatefulWidget {
  const EditEmployeeDialog({
    super.key,
    required this.employee,
    required this.onSaved,
  });

  final Map<String, dynamic> employee;
  final VoidCallback onSaved;

  @override
  State<EditEmployeeDialog> createState() => _EditEmployeeDialogState();
}

class _EditEmployeeDialogState extends State<EditEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _username;
  late String _selectedRole;

  @override
  void initState() {
    super.initState();
    _username = widget.employee['username']?.toString() ?? '';
    _selectedRole = widget.employee['role']?.toString() ?? 'cs';
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
                onChanged: (value) => _username = value,
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
                items: EmployeeRoleUtils.assignableRoles
                    .map(
                      (role) => DropdownMenuItem(
                        value: role,
                        child: Text(EmployeeRoleUtils.label(role)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _selectedRole = value);
                },
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

  Future<void> _updateEmployee() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final response = await ApiClient.put(
        '/employees/${widget.employee['user_id']}',
        body: jsonEncode({'username': _username, 'role': _selectedRole}),
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Karyawan berhasil diperbarui')),
        );
        widget.onSaved();
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal memperbarui karyawan: ${response.statusCode}',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error')),
      );
    }
  }
}

void showDeleteEmployeeConfirmation(
  BuildContext context, {
  required Map<String, dynamic> employee,
  required Future<void> Function() onConfirmDelete,
}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Konfirmasi Hapus'),
      content: Text(
        'Apakah Anda yakin ingin menghapus karyawan ${employee['username']}?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            await onConfirmDelete();
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Hapus'),
        ),
      ],
    ),
  );
}
