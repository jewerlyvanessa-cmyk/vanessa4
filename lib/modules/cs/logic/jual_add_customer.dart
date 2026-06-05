import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/providers/customers_provider.dart';

/// Dialog tambah customer dari form Jual CS.
abstract final class JualAddCustomer {
  JualAddCustomer._();

  static Future<Map<String, dynamic>?> showDialogAndCreate({
    required BuildContext context,
    required WidgetRef ref,
    required String initialName,
    required TextEditingController syncController,
  }) async {
    final nameController = TextEditingController(text: initialName);
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Customer Baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nama'),
            ),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email (opsional)',
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'No. Telepon (opsional)',
              ),
            ),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Alamat'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (confirmed != true) return null;

    try {
      final response = await ApiClient.post(
        '/api/customers',
        body: jsonEncode({
          'name': nameController.text,
          'email': emailController.text.trim().isEmpty
              ? null
              : emailController.text.trim(),
          'phone': phoneController.text.trim().isEmpty
              ? null
              : phoneController.text.trim(),
          'address': addressController.text.trim().isEmpty
              ? null
              : addressController.text.trim(),
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data is Map && data['data'] is Map) {
          final customer = Map<String, dynamic>.from(data['data'] as Map);
          syncController.text =
              customer['name']?.toString() ?? customer['nama']?.toString() ?? '';
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(customersProvider.notifier).fetchCustomers();
          });
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Customer berhasil ditambahkan')),
            );
          }
          return customer;
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
    return null;
  }
}
