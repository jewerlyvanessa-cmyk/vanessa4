import 'package:flutter/material.dart';

/// Bagian lookup nota lama + nota jual pada form buyback CS.
class BuybackNotaLookupSection extends StatelessWidget {
  const BuybackNotaLookupSection({
    super.key,
    required this.notaLamaController,
    required this.nomorNotaController,
    required this.isManualEntry,
    required this.isLookingUpItem,
    required this.onLookup,
    required this.onScanNotaLama,
    required this.onNotaLamaChanged,
  });

  final TextEditingController notaLamaController;
  final TextEditingController nomorNotaController;
  final bool isManualEntry;
  final bool isLookingUpItem;
  final VoidCallback onLookup;
  final VoidCallback onScanNotaLama;
  final VoidCallback onNotaLamaChanged;

  @override
  Widget build(BuildContext context) {
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
                    Text('Nota Lama'),
                    Tooltip(
                      message:
                          'Masukkan nomor nota lama untuk mencari item dari penjualan sebelumnya',
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
              child: Autocomplete<String>(
                optionsBuilder: (_) => const Iterable<String>.empty(),
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  return TextFormField(
                    controller: notaLamaController,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      hintText: 'Masukkan nomor nota lama...',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: isLookingUpItem ? null : onLookup,
                            tooltip: 'Cari berdasarkan nota lama',
                          ),
                          IconButton(
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: isLookingUpItem ? null : onScanNotaLama,
                            tooltip: 'Scan QR nota lama',
                          ),
                        ],
                      ),
                    ),
                    onChanged: (_) => onNotaLamaChanged(),
                    onFieldSubmitted: (_) => onFieldSubmitted(),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Nota Jual')),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: nomorNotaController,
                readOnly: !isManualEntry,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: 'Nomor nota jual akan muncul setelah lookup',
                  filled: !isManualEntry,
                  fillColor: !isManualEntry ? Colors.grey[100] : null,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
