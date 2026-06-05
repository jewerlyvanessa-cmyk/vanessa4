import 'package:flutter/material.dart';

/// Field lookup nota lama pada form service CS.
class ServiceNotaLookupField extends StatelessWidget {
  const ServiceNotaLookupField({
    super.key,
    required this.notaLamaController,
    required this.onLookup,
    required this.onScanAndLookup,
    required this.onChanged,
  });

  final TextEditingController notaLamaController;
  final void Function(TextEditingController controller) onLookup;
  final void Function(TextEditingController controller) onScanAndLookup;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 120,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Nota Lama'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Autocomplete<String>(
            optionsBuilder: (_) => const Iterable<String>.empty(),
            onSelected: (selection) {
              notaLamaController.text = selection;
            },
            fieldViewBuilder: (context, _, focusNode, onFieldSubmitted) {
              return Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: notaLamaController,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Masukkan nomor nota lama...',
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 12,
                        ),
                      ),
                      onChanged: (_) => onChanged(),
                      onFieldSubmitted: (_) => onFieldSubmitted(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () => onLookup(notaLamaController),
                    tooltip: 'Cari berdasarkan nota lama',
                  ),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: () => onScanAndLookup(notaLamaController),
                    tooltip: 'Scan QR nota lama',
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
