import 'package:flutter/material.dart';

/// Pemilihan tipe stok (STOK / UNREGISTERED / QSR) pada form jual CS.
class JualStockTypeSection extends StatelessWidget {
  const JualStockTypeSection({
    super.key,
    required this.saleType,
    required this.onSaleTypeChanged,
  });

  final String saleType;
  final ValueChanged<String> onSaleTypeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tipe Stok'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: [
            ChoiceChip(
              label: const Text('STOK'),
              selected: saleType == 'from_stock',
              onSelected: (selected) {
                if (selected) onSaleTypeChanged('from_stock');
              },
            ),
            ChoiceChip(
              label: const Text('UNREGISTERED'),
              selected: saleType == 'unregistered',
              onSelected: (selected) {
                if (selected) onSaleTypeChanged('unregistered');
              },
            ),
            ChoiceChip(
              label: const Text('QSR (Cepat)'),
              selected: saleType == 'qsr',
              onSelected: (selected) {
                if (selected) onSaleTypeChanged('qsr');
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (saleType == 'qsr')
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Text(
              'QSR (Quick Stock Registration): Daftarkan barang baru ke stok dan jual langsung. Foto wajib diisi.',
              style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}
