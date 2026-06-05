import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/modules/kasir/logic/store_operational_utils.dart';

class StoreOperationalEntriesList extends StatelessWidget {
  const StoreOperationalEntriesList({
    super.key,
    required this.entries,
    required this.money,
    required this.timeFmt,
    required this.dateTimeFmt,
    required this.singleDayFilter,
    required this.showUserId,
    required this.onEntryTap,
  });

  final List<Map<String, dynamic>> entries;
  final NumberFormat money;
  final DateFormat timeFmt;
  final DateFormat dateTimeFmt;
  final bool singleDayFilter;
  final bool showUserId;
  final ValueChanged<Map<String, dynamic>> onEntryTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        for (final e in entries)
          Builder(
            builder: (context) {
              final amt = e['amount'];
              final cat = e['category']?.toString() ?? '—';
              final notes = e['notes']?.toString() ?? '';
              final income = StoreOperationalUtils.entryIsIncome(e);
              final created = e['created_at'];
              DateTime? dt;
              if (created is String) {
                dt = DateTime.tryParse(created);
              }
              final timeStr = dt != null
                  ? (singleDayFilter
                      ? timeFmt.format(dt.toLocal())
                      : dateTimeFmt.format(dt.toLocal()))
                  : '—';
              final value =
                  amt is num ? amt.toDouble() : double.tryParse('$amt') ?? 0;
              final hasUserId =
                  e['user_id']?.toString().trim().isNotEmpty ?? false;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => onEntryTap(e),
                  leading: CircleAvatar(
                    backgroundColor: income
                        ? Colors.green.shade50
                        : cs.errorContainer.withValues(alpha: 0.65),
                    foregroundColor: income ? Colors.green.shade800 : cs.error,
                    child: Icon(
                      income ? Icons.north_east : Icons.south_east,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    cat,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        income ? 'Pemasukan' : 'Pengeluaran',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: income
                                  ? Colors.green.shade700
                                  : cs.error,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (notes.isNotEmpty) Text(notes),
                      if (showUserId && hasUserId)
                        Text(
                          'User ID: ${e['user_id']}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                    ],
                  ),
                  isThreeLine:
                      notes.isNotEmpty || (showUserId && hasUserId),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        money.format(value),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: income ? Colors.green.shade800 : cs.error,
                          fontSize: AppTypography.body,
                        ),
                      ),
                      Text(
                        timeStr,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
