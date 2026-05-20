import 'package:flutter/material.dart';

/// Dialog input kode QR/barcode manual (semua platform).
Future<String?> showQrManualEntryDialog(BuildContext context) async {
  final ctrl = TextEditingController();
  final value = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Input kode manual'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Kode QR / barcode',
          border: OutlineInputBorder(),
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return value;
}
