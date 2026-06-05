import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/modules/cs/pages/customers_page.dart';
import 'package:vanessa3/utils/logger.dart';

/// Bagian pemilihan customer pada form Jual CS (autocomplete + tambah + QR).
class JualCustomerField extends ConsumerWidget {
  const JualCustomerField({
    super.key,
    required this.autocompleteKey,
    required this.customerController,
    required this.phoneController,
    required this.addressController,
    required this.selectedCustomer,
    required this.onCustomerSelected,
    required this.onCustomerTextChanged,
    required this.onAddCustomer,
    required this.onScanQr,
  });

  final int autocompleteKey;
  final TextEditingController customerController;
  final TextEditingController phoneController;
  final TextEditingController addressController;
  final Map<String, dynamic>? selectedCustomer;
  final ValueChanged<Map<String, dynamic>> onCustomerSelected;
  final ValueChanged<String> onCustomerTextChanged;
  final Future<void> Function(String initialName, TextEditingController controller)
      onAddCustomer;
  final Future<void> Function(TextEditingController controller) onScanQr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerList = ref.watch(customersProvider);

    return Row(
      children: [
        const SizedBox(
          width: 100,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Customer'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: customerList.isLoading
              ? const TextField(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Loading customers...',
                  ),
                  enabled: false,
                )
              : customerList.error != null
                  ? TextField(
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: 'Error loading customers',
                        errorText: customerList.error,
                      ),
                      enabled: false,
                    )
                  : Autocomplete<Map<String, dynamic>>(
                      key: ValueKey(autocompleteKey),
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text == '') {
                          return const Iterable<Map<String, dynamic>>.empty();
                        }
                        final input = textEditingValue.text.toLowerCase();
                        return customerList.customers.where((c) {
                          final name = (c['name'] ?? c['nama'] ?? '')
                              .toString()
                              .toLowerCase();
                          Logger.logInfo(
                            'DEBUG: Checking customer: $name against input: $input',
                          );
                          return name.contains(input);
                        }).toList();
                      },
                      displayStringForOption: (option) =>
                          option['name'] ?? option['nama'] ?? '',
                      onSelected: onCustomerSelected,
                      fieldViewBuilder:
                          (context, controller, focusNode, onFieldSubmitted) {
                        if (controller.text != customerController.text) {
                          controller.text = customerController.text;
                          controller.selection = TextSelection.fromPosition(
                            TextPosition(offset: controller.text.length),
                          );
                        }
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
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(
                                        vertical: 12,
                                        horizontal: 12,
                                      ),
                                    ),
                                    onChanged: (value) {
                                      customerController.text = value;
                                      onCustomerTextChanged(value);
                                    },
                                    onFieldSubmitted: (value) =>
                                        onFieldSubmitted(),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Nama customer wajib diisi';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.person_add),
                                  tooltip: 'Tambah Customer',
                                  onPressed: () => onAddCustomer(
                                    controller.text,
                                    controller,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.qr_code_scanner),
                                  tooltip: 'Scan QR Customer',
                                  onPressed: () => onScanQr(controller),
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
