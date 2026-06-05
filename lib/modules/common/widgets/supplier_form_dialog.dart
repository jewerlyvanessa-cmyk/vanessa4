import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:vanessa3/core/network/api_client.dart';

/// Dialog tambah / ubah supplier. Mengembalikan row supplier jika berhasil.
Future<Map<String, dynamic>?> showSupplierFormDialog(
  BuildContext context, {
  Map<String, dynamic>? existing,
  String? initialName,
  bool compact = false,
}) {
  return showDialog<Map<String, dynamic>?>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _SupplierFormDialog(
      existing: existing,
      initialName: initialName,
      compact: compact,
    ),
  );
}

class _SupplierFormDialog extends StatefulWidget {
  const _SupplierFormDialog({
    this.existing,
    this.initialName,
    this.compact = false,
  });

  final Map<String, dynamic>? existing;
  final String? initialName;
  final bool compact;

  @override
  State<_SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends State<_SupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _contactCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _notesCtrl;
  late String _status;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(
      text: existing?['name']?.toString() ?? widget.initialName ?? '',
    );
    _codeCtrl = TextEditingController(text: existing?['code']?.toString() ?? '');
    _contactCtrl = TextEditingController(
      text: existing?['contact_name']?.toString() ?? '',
    );
    _phoneCtrl =
        TextEditingController(text: existing?['phone']?.toString() ?? '');
    _emailCtrl =
        TextEditingController(text: existing?['email']?.toString() ?? '');
    _addressCtrl =
        TextEditingController(text: existing?['address']?.toString() ?? '');
    _notesCtrl =
        TextEditingController(text: existing?['notes']?.toString() ?? '');
    _status = (existing?['status'] ?? 'active').toString();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _contactCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _close() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final body = jsonEncode({
      'name': _nameCtrl.text.trim(),
      'code': _codeCtrl.text.trim(),
      'contact_name': _contactCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'notes': _notesCtrl.text.trim(),
      'status': _status,
    });
    final id = widget.existing?['supplier_id']?.toString();
    try {
      final res = id == null
          ? await ApiClient.post('/api/suppliers', body: body)
          : await ApiClient.put('/api/suppliers/$id', body: body);
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          Navigator.of(context).pop(Map<String, dynamic>.from(decoded));
        }
        return;
      }
      var msg = 'Gagal menyimpan';
      try {
        final d = jsonDecode(res.body);
        if (d is Map) msg = (d['error'] ?? msg).toString();
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit supplier' : 'Tambah supplier baru'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                autofocus: !_isEdit,
                decoration: const InputDecoration(
                  labelText: 'Nama supplier *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              if (!widget.compact) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _codeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Kode (opsional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _contactCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama kontak',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telepon',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _addressCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Alamat',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Catatan',
                    border: OutlineInputBorder(),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telepon (opsional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (!widget.compact && _isEdit) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Aktif')),
                    DropdownMenuItem(
                      value: 'inactive',
                      child: Text('Nonaktif'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _status = v);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _close,
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
        ),
      ],
    );
  }
}
