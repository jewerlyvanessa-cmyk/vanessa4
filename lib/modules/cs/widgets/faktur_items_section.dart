import 'package:flutter/material.dart';
import 'package:vanessa3/modules/cs/widgets/faktur_item_card.dart';

class FakturItemsSection extends StatelessWidget {
  const FakturItemsSection({
    super.key,
    required this.items,
    required this.dense,
  });

  final List<dynamic> items;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Detail Item',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        SizedBox(height: dense ? 4 : 8),
        if (items.isEmpty)
          Card(
            child: Padding(
              padding: EdgeInsets.all(dense ? 10 : 16),
              child: const Text('Tidak ada item dalam order ini'),
            ),
          )
        else
          ...items.map(
            (item) => FakturItemCard(item: item, dense: dense),
          ),
      ],
    );
  }
}
