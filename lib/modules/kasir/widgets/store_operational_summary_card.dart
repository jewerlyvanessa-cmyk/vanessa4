import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

class StoreOperationalSummaryCard extends StatelessWidget {
  const StoreOperationalSummaryCard({
    super.key,
    required this.sumIncome,
    required this.sumExpense,
    required this.sumNet,
    required this.money,
  });

  final double sumIncome;
  final double sumExpense;
  final double sumNet;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pemasukan',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  Text(
                    money.format(sumIncome),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.green.shade700,
                      fontSize: AppTypography.body,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pengeluaran',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  Text(
                    money.format(sumExpense),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: cs.error,
                      fontSize: AppTypography.body,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Saldo',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  Text(
                    money.format(sumNet),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: sumNet >= 0 ? Colors.green.shade800 : cs.error,
                      fontSize: AppTypography.body,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
