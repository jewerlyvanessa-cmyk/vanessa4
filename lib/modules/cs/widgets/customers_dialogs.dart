import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/modules/cs/logic/customers_utils.dart';
import 'package:vanessa3/modules/cs/widgets/customer_transactions_sheet.dart';
import 'package:vanessa3/providers/customers_provider.dart';
import 'package:vanessa3/providers/user_state_provider.dart';

void showAddCustomerDialog(BuildContext pageContext, WidgetRef ref) {
  final customersNotifier = ref.read(customersProvider.notifier);
  final branchId = ref.read(userStateProvider).branch;
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();

  showDialog<void>(
    context: pageContext,
    builder: (dialogContext) {
      final formKey = GlobalKey<FormState>();
      var saving = false;
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Tambah Pelanggan'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Nama *'),
                      textCapitalization: TextCapitalization.words,
                      validator: CustomersUtils.validateName,
                      enabled: !saving,
                    ),
                    TextFormField(
                      controller: phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Nomor Telepon (opsional)',
                      ),
                      validator: CustomersUtils.validatePhone,
                      keyboardType: TextInputType.phone,
                      enabled: !saving,
                    ),
                    TextFormField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email (opsional)',
                      ),
                      validator: CustomersUtils.validateEmail,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !saving,
                    ),
                    TextFormField(
                      controller: addressController,
                      decoration: const InputDecoration(
                        labelText: 'Alamat (opsional)',
                      ),
                      validator: CustomersUtils.validateAddress,
                      maxLines: 3,
                      enabled: !saving,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        setDialogState(() => saving = true);
                        final ok = await customersNotifier.addCustomer(
                          name: nameController.text,
                          phone: phoneController.text,
                          email: emailController.text,
                          address: addressController.text,
                          branchId: branchId,
                        );
                        if (!dialogContext.mounted) return;
                        if (ok) {
                          Navigator.of(dialogContext).pop();
                          if (!pageContext.mounted) return;
                          ScaffoldMessenger.of(pageContext).showSnackBar(
                            const SnackBar(
                              content: Text('Pelanggan berhasil ditambahkan'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } else {
                          setDialogState(() => saving = false);
                          final err = ref.read(customersProvider).error;
                          ScaffoldMessenger.of(pageContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                err ?? 'Gagal menambah pelanggan',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Simpan'),
              ),
            ],
          );
        },
      );
    },
  );
}

void showEditCustomerDialog(
  BuildContext context,
  Map<String, dynamic> customer,
  WidgetRef ref,
) {
  final customersNotifier = ref.read(customersProvider.notifier);
  final nameController = TextEditingController(text: customer['name'] ?? '');
  final emailController = TextEditingController(text: customer['email'] ?? '');
  final phoneController = TextEditingController(text: customer['phone'] ?? '');
  final addressController =
      TextEditingController(text: customer['address'] ?? '');

  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final formKey = GlobalKey<FormState>();
      return AlertDialog(
        title: const Text('Edit Pelanggan'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nama'),
                  validator: CustomersUtils.validateName,
                ),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email (opsional)',
                  ),
                  validator: CustomersUtils.validateEmail,
                  keyboardType: TextInputType.emailAddress,
                ),
                TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Nomor Telepon (opsional)',
                  ),
                  validator: CustomersUtils.validatePhone,
                  keyboardType: TextInputType.phone,
                ),
                TextFormField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'Alamat (opsional)',
                  ),
                  validator: CustomersUtils.validateAddress,
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final id = customer['customer_id']?.toString() ?? '';
              final success = await customersNotifier.editCustomer(
                id,
                nameController.text.trim(),
                emailController.text.trim(),
                phoneController.text.trim(),
                addressController.text.trim(),
              );
              if (!dialogContext.mounted) return;
              if (success) {
                Navigator.of(dialogContext).pop();
              } else {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Gagal menyimpan perubahan customer!'),
                  ),
                );
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      );
    },
  );
}

void showDeleteCustomerConfirmation(
  BuildContext context,
  Map<String, dynamic> customer,
  WidgetRef ref,
) {
  final customersNotifier = ref.read(customersProvider.notifier);
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Hapus Pelanggan'),
      content: Text(
        'Apakah Anda yakin ingin menghapus pelanggan "${customer['name']}"?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            await customersNotifier.deleteCustomer(
              customer['customer_id']?.toString() ?? '',
            );
          },
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Hapus'),
        ),
      ],
    ),
  );
}

/// Tangani aksi menu baris pelanggan (transactions / edit / delete).
void handleCustomerRowAction(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> customer,
  String action,
) {
  switch (action) {
    case 'transactions':
      if (!CustomersUtils.canSeeGlobalTransactions(
        ref.read(userStateProvider).role,
      )) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Riwayat transaksi hanya untuk Superadmin, Manajer & Admin Toko',
            ),
          ),
        );
        return;
      }
      showCustomerTransactionsSheet(context, customer);
      break;
    case 'edit':
      showEditCustomerDialog(context, customer, ref);
      break;
    case 'delete':
      showDeleteCustomerConfirmation(context, customer, ref);
      break;
  }
}
