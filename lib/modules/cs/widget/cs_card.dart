import 'package:flutter/material.dart';

class CsCard extends StatelessWidget {
  final String title;
  final Widget? child;
  const CsCard({required this.title, this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (child != null) ...[
              const SizedBox(height: 8),
              child!,
            ]
          ],
        ),
      ),
    );
  }
}
