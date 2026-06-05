import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/providers/customers_provider.dart';

/// Bagian pemilihan customer pada form Buyback CS (locked dari lookup atau autocomplete).
class BuybackCustomerField extends ConsumerWidget {
  const BuybackCustomerField({
    super.key,
    required this.customerController,
    required this.phoneController,
    required this.addressController,
    required this.selectedCustomer,
    required this.isLockedFromLookup,
    required this.onCustomerSelected,
    required this.onFieldChanged,
    required this.onAddCustomer,
    required this.onScanQr,
  });

  final TextEditingController customerController;
  final TextEditingController phoneController;
  final TextEditingController addressController;
  final Map<String, dynamic>? selectedCustomer;
  final bool isLockedFromLookup;
  final ValueChanged<Map<String, dynamic>> onCustomerSelected;
  final VoidCallback onFieldChanged;
  final Future<void> Function(String initialName, TextEditingController controller)
      onAddCustomer;
  final Future<void> Function(TextEditingController controller) onScanQr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerList = ref.watch(customersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(
              width: 100,
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
              child: isLockedFromLookup && selectedCustomer != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: customerController,
                          readOnly: true,
                          decoration: InputDecoration(
                            hintText: 'Customer dari order jual',
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.grey[100],
                            suffixIcon: const Tooltip(
                              message: 'Customer otomatis dari nota lama',
                              child: Icon(Icons.lock_outline),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Phone: ${selectedCustomer!['phone'] ?? selectedCustomer!['no_hp'] ?? 'N/A'} | '
                          'Address: ${selectedCustomer!['address'] ?? selectedCustomer!['alamat'] ?? 'N/A'}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    )
                  : Row(
                      children: [
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
                                    if (textEditingValue.text == '') {
                                      return const Iterable<Map<String, dynamic>>.empty();
                                    }
                                    final input =
                                        textEditingValue.text.toLowerCase();
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
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                    vertical: 12,
                                                    horizontal: 12,
                                                  ),
                                                ),
                                                onChanged: (_) => onFieldChanged(),
                                                onFieldSubmitted: (_) =>
                                                    onFieldSubmitted(),
                                                validator: (value) {
                                                  if (value == null ||
                                                      value.isEmpty) {
                                                    return 'Customer wajib dipilih';
                                                  }
                                                  return null;
                                                },
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.person_add,
                                                size: 20,
                                              ),
                                              tooltip: 'Tambah Customer',
                                              onPressed: () => onAddCustomer(
                                                controller.text,
                                                controller,
                                              ),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.qr_code_scanner,
                                                size: 20,
                                              ),
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
                    ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
