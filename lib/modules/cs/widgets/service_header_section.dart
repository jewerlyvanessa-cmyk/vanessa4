import 'package:flutter/material.dart';
import 'package:vanessa3/widgets/pickup_branch_field.dart';

/// Header form service CS: mode, cabang pickup, dan nomor order.
class ServiceHeaderSection extends StatelessWidget {
  const ServiceHeaderSection({
    super.key,
    required this.modeToko,
    required this.notaOrderController,
    required this.orderBranchId,
    required this.branches,
    required this.pickupBranchId,
    required this.onModeChanged,
    required this.onPickupBranchChanged,
  });

  final String modeToko;
  final TextEditingController notaOrderController;
  final String orderBranchId;
  final List<Map<String, dynamic>> branches;
  final int? pickupBranchId;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<int?> onPickupBranchChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 120,
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
        const SizedBox(height: 12),
        PickupBranchField(
          orderBranchId: orderBranchId,
          branches: branches,
          value: pickupBranchId,
          onChanged: onPickupBranchChanged,
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
                decoration: const InputDecoration(
                  hintText: 'Order Number',
                  filled: true,
                  fillColor: Colors.grey,
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
