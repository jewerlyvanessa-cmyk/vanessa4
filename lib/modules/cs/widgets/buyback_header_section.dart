import 'package:flutter/material.dart';

/// Header form buyback CS: mode toko/online dan nomor order otomatis.
class BuybackHeaderSection extends StatelessWidget {
  const BuybackHeaderSection({
    super.key,
    required this.modeToko,
    required this.notaOrderController,
    required this.onModeChanged,
  });

  final String modeToko;
  final TextEditingController notaOrderController;
  final ValueChanged<String> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 100,
              alignment: Alignment.centerLeft,
              child: const Text('Mode'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                spacing: 8.0,
                children: [
                  ChoiceChip(
                    label: const Text('TOKO'),
                    selected: modeToko == 'TOKO',
                    onSelected: (selected) {
                      if (selected) onModeChanged('TOKO');
                    },
                  ),
                  ChoiceChip(
                    label: const Text('ONLINE'),
                    selected: modeToko == 'ONLINE',
                    onSelected: (selected) {
                      if (selected) onModeChanged('ONLINE');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(
              width: 100,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Order Number'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: notaOrderController,
                readOnly: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: 'Nomor nota otomatis',
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
