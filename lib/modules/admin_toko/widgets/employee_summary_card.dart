import 'package:flutter/material.dart';

class EmployeeSummaryCard extends StatelessWidget {
  const EmployeeSummaryCard({
    super.key,
    required this.count,
    required this.icon,
    required this.color,
  });

  final int count;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const Spacer(),
            Text(
              count.toString(),
              style: tt.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
