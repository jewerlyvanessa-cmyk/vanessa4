import 'package:flutter/material.dart';

/// Field autocomplete kode produk + scan QR pada form jual CS.
class JualItemCodeField extends StatelessWidget {
  const JualItemCodeField({
    super.key,
    required this.selectedItem,
    required this.itemSuggestions,
    required this.isLoadingSuggestions,
    required this.itemCodeController,
    required this.onSearch,
    required this.onItemSelected,
    required this.onAutocompleteControllerReady,
    required this.onTryAutoSelect,
    required this.onScanQr,
  });

  final Map<String, dynamic>? selectedItem;
  final List<Map<String, dynamic>> itemSuggestions;
  final bool isLoadingSuggestions;
  final TextEditingController itemCodeController;
  final ValueChanged<String> onSearch;
  final ValueChanged<Map<String, dynamic>> onItemSelected;
  final ValueChanged<TextEditingController> onAutocompleteControllerReady;
  final Future<void> Function(String code) onTryAutoSelect;
  final Future<void> Function(TextEditingController controller) onScanQr;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 100,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Kode Produk'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Autocomplete<Map<String, dynamic>>(
                  initialValue: selectedItem != null
                      ? TextEditingValue(
                          text: selectedItem!['kode_produk'] ??
                              selectedItem!['item_code'] ??
                              '',
                        )
                      : null,
                  optionsBuilder: (textEditingValue) {
                    onSearch(textEditingValue.text);
                    return itemSuggestions;
                  },
                  displayStringForOption: (option) {
                    final code =
                        option['kode_produk'] ?? option['item_code'] ?? '';
                    final name = option['name'] ?? '';
                    return '$code - $name';
                  },
                  onSelected: onItemSelected,
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    onAutocompleteControllerReady(controller);
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: 'Kode produk item',
                        suffixIcon: isLoadingSuggestions
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        itemCodeController.text = value;
                        onSearch(value);
                      },
                      onFieldSubmitted: (value) async {
                        onFieldSubmitted();
                        await onTryAutoSelect(value);
                      },
                      onEditingComplete: () async {
                        await onTryAutoSelect(controller.text);
                      },
                    );
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Scan QR Kode Produk',
                onPressed: () => onScanQr(itemCodeController),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
