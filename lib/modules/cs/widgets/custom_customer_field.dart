import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/providers/customers_provider.dart';

/// Bagian pemilihan customer pada form Custom CS.
class CustomCustomerField extends ConsumerWidget {
  const CustomCustomerField({
    super.key,
    required this.selectedCustomer,
    required this.onCustomerSelected,
    required this.onFieldChanged,
    required this.onAddCustomer,
    required this.onScanQr,
  });

  final Map<String, dynamic>? selectedCustomer;
  final ValueChanged<Map<String, dynamic>> onCustomerSelected;
  final VoidCallback onFieldChanged;
  final Future<void> Function(String initialName, TextEditingController controller)
      onAddCustomer;
  final Future<void> Function(TextEditingController controller) onScanQr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerList = ref.watch(customersProvider);

    return Row(
      children: [
        const SizedBox(
          width: 120,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Text('Customer'),
                Tooltip(
                  message:
                      'Cari berdasarkan nama atau nomor telepon (minimal 2 karakter)',
                  child: Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: customerList.isLoading
              ? const TextField(
                  decoration: InputDecoration(
                    labelText: 'Loading customers...',
                  ),
                  enabled: false,
                )
              : Autocomplete<Map<String, dynamic>>(
                  initialValue: selectedCustomer != null
                      ? TextEditingValue(
                          text: selectedCustomer!['name'] ??
                              selectedCustomer!['nama'] ??
                              '',
                        )
                      : null,
                  optionsBuilder: (textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return const Iterable<Map<String, dynamic>>.empty();
                    }
                    final input = textEditingValue.text.toLowerCase();
                    return customerList.customers.where((c) {
                      final name = (c['name'] ?? c['nama'] ?? '')
                          .toString()
                          .toLowerCase();
                      return name.contains(input);
                    });
                  },
                  displayStringForOption: (option) =>
                      option['name'] ?? option['nama'] ?? '',
                  onSelected: onCustomerSelected,
                  fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: controller,
                                focusNode: focusNode,
                                decoration: const InputDecoration(
                                  hintText: 'Cari customer...',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 12,
                                  ),
                                ),
                                onChanged: (_) => onFieldChanged(),
                                onFieldSubmitted: (_) => onSubmitted(),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Customer wajib dipilih';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.person_add, size: 20),
                              tooltip: 'Tambah Customer',
                              onPressed: () =>
                                  onAddCustomer(controller.text, controller),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            IconButton(
                              icon: const Icon(Icons.qr_code_scanner, size: 20),
                              tooltip: 'Scan QR Customer',
                              onPressed: () => onScanQr(controller),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                        if (selectedCustomer != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Phone: ${selectedCustomer!['phone'] ?? selectedCustomer!['no_hp'] ?? 'N/A'} | '
                            'Address: ${selectedCustomer!['address'] ?? selectedCustomer!['alamat'] ?? 'N/A'}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}
