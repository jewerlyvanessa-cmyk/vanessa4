import 'package:flutter/material.dart';
import 'package:vanessa3/widgets/pickup_branch_field.dart';

class CustomHeaderSection extends StatelessWidget {
  const CustomHeaderSection({
    super.key,
    required this.modeToko,
    required this.onModeChanged,
    required this.orderBranchId,
    required this.branches,
    required this.pickupBranchId,
    required this.onPickupChanged,
    required this.notaOrderController,
  });

  final String modeToko;
  final ValueChanged<String> onModeChanged;
  final String orderBranchId;
  final List<Map<String, dynamic>> branches;
  final int? pickupBranchId;
  final ValueChanged<int?> onPickupChanged;
  final TextEditingController notaOrderController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(
              width: 120,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Mode'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('TOKO'),
                    selected: modeToko == 'TOKO',
                    onSelected: (_) => onModeChanged('TOKO'),
                  ),
                  ChoiceChip(
                    label: const Text('ONLINE'),
                    selected: modeToko == 'ONLINE',
                    onSelected: (_) => onModeChanged('ONLINE'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        PickupBranchField(
          orderBranchId: orderBranchId,
          branches: branches,
          value: pickupBranchId,
          onChanged: onPickupChanged,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const SizedBox(
              width: 120,
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
      ],
    );
  }
}
