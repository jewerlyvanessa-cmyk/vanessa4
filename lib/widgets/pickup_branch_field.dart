import 'package:flutter/material.dart';

/// Cabang pengambilan untuk order service/custom (`pickup_branch_id` pada POST /orders).
class PickupBranchField extends StatelessWidget {
  const PickupBranchField({
    super.key,
    this.labelWidth = 120,
    required this.orderBranchId,
    required this.branches,
    required this.value,
    required this.onChanged,
  });

  final double labelWidth;
  final String orderBranchId;
  final List<Map<String, dynamic>> branches;
  final int? value;
  final ValueChanged<int?> onChanged;

  static int? _parseBid(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final orderBid = _parseBid(orderBranchId);

    var orderName = 'cabang ini';
    if (orderBid != null && branches.isNotEmpty) {
      for (final b in branches) {
        if (_parseBid(b['branch_id']) == orderBid) {
          final n = b['name']?.toString().trim();
          if (n != null && n.isNotEmpty) orderName = n;
          break;
        }
      }
    }

    final items = <DropdownMenuItem<int?>>[
      DropdownMenuItem<int?>(
        value: null,
        child: Text(
          'Sama dengan cabang order ($orderName)',
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ];

    final seen = <int>{};
    for (final b in branches) {
      final id = _parseBid(b['branch_id']);
      if (id == null || id <= 0) continue;
      if (orderBid != null && id == orderBid) continue;
      if (seen.contains(id)) continue;
      seen.add(id);
      items.add(
        DropdownMenuItem<int?>(
          value: id,
          child: Text(
            b['name']?.toString() ?? 'Cabang $id',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    final multiCab = items.length > 1;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: labelWidth,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    'Cabang ambil',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Tooltip(
                  message:
                      'Jika pelunasan dicatat di kasir cabang lain, pilih cabang pengambilan. '
                      'Uang muka (DP) tetap di cabang order.',
                  child: const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.info_outline, size: 16, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<int?>(
            // Controlled selection (berubah saat user pilih cabang).
            // ignore: deprecated_member_use
            value: value,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            isExpanded: true,
            items: items,
            onChanged: multiCab ? onChanged : null,
          ),
        ),
      ],
    );
  }
}
