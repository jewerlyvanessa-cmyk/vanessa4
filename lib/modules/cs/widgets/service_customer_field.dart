import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/providers/customers_provider.dart';

/// Bagian pemilihan customer pada form Service CS.
class ServiceCustomerField extends ConsumerWidget {
  const ServiceCustomerField({
    super.key,
    required this.customerController,
    required this.selectedCustomer,
    required this.onCustomerSelected,
    required this.onFieldChanged,
    required this.onAutocompleteControllerReady,
    required this.onAddCustomer,
    required this.onScanQr,
  });

  final TextEditingController customerController;
  final Map<String, dynamic>? selectedCustomer;
  final ValueChanged<Map<String, dynamic>> onCustomerSelected;
  final VoidCallback onFieldChanged;
  final ValueChanged<TextEditingController> onAutocompleteControllerReady;
  final Future<void> Function(String initialName) onAddCustomer;
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
            child: Text('Customer'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: customerList.isLoading
                    ? const TextField(
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Loading customers...',
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
                          if (textEditingValue.text == '') {
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
                        fieldViewBuilder: (context, controller, focusNode,
                            onFieldSubmitted) {
                          onAutocompleteControllerReady(controller);
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
                                      onChanged: (_) {
                                        customerController.text = controller.text;
                                        onFieldChanged();
                                      },
                                      onFieldSubmitted: (_) => onFieldSubmitted(),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Nama customer wajib diisi';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  Builder(
                                    builder: (context) {
                                      final input = controller.text
                                          .trim()
                                          .toLowerCase();
                                      final exists = ref
                                          .read(customersProvider)
                                          .customers
                                          .any((c) {
                                            final name = (c['name'] ??
                                                    c['nama'] ??
                                                    '')
                                                .toString()
                                                .toLowerCase();
                                            return name == input &&
                                                input.isNotEmpty;
                                          });
                                      if (!exists && input.isNotEmpty) {
                                        return Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.person_add),
                                              tooltip: 'Tambah Customer',
                                              onPressed: () =>
                                                  onAddCustomer(controller.text),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.qr_code_scanner,
                                              ),
                                              tooltip: 'Scan QR Customer',
                                              onPressed: () => onScanQr(controller),
                                            ),
                                          ],
                                        );
                                      }
                                      return IconButton(
                                        icon: const Icon(Icons.qr_code_scanner),
                                        tooltip: 'Scan QR Customer',
                                        onPressed: () => onScanQr(controller),
                                      );
                                    },
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
          ),
        ),
      ],
    );
  }
}
