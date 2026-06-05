import 'package:flutter/material.dart';
import 'package:vanessa3/modules/admin_toko/widgets/stock_mutation_summary_card.dart';

class StockMutationSummarySection extends StatelessWidget {
  const StockMutationSummarySection({
    super.key,
    required this.totalCount,
    required this.inCount,
    required this.outCount,
    required this.transferInCount,
    required this.transferOutCount,
    required this.selectedType,
    required this.onFilterSelected,
    required this.filteredCount,
    required this.periodLabel,
  });

  final int totalCount;
  final int inCount;
  final int outCount;
  final int transferInCount;
  final int transferOutCount;
  final String selectedType;
  final ValueChanged<String> onFilterSelected;
  final int filteredCount;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final narrowScreen = MediaQuery.sizeOf(context).width < 600;
    final gap = narrowScreen ? 10.0 : 16.0;

    Widget card(
      String filterType,
      String title,
      int count,
      IconData icon,
      Color color,
    ) {
      return StockMutationSummaryCard(
        title: title,
        count: count,
        icon: icon,
        color: color,
        filterType: filterType,
        isSelected: selectedType == filterType,
        onTap: () => onFilterSelected(filterType),
      );
    }

    return Padding(
      padding: EdgeInsets.all(narrowScreen ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: card(
                  'all',
                  'Total Mutasi',
                  totalCount,
                  Icons.swap_horiz,
                  Colors.blue,
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: card(
                  'in',
                  'Penambahan stok',
                  inCount,
                  Icons.arrow_downward,
                  Colors.green,
                ),
              ),
            ],
          ),
          SizedBox(height: gap),
          Row(
            children: [
              Expanded(
                child: card(
                  'out',
                  'Pengurangan stok',
                  outCount,
                  Icons.arrow_upward,
                  Colors.red,
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: card(
                  'transfer_in',
                  'Transfer masuk',
                  transferInCount,
                  Icons.call_received,
                  Colors.blue,
                ),
              ),
            ],
          ),
          SizedBox(height: gap),
          Row(
            children: [
              Expanded(
                child: card(
                  'transfer_out',
                  'Transfer keluar',
                  transferOutCount,
                  Icons.call_made,
                  Colors.orange,
                ),
              ),
            ],
          ),
          SizedBox(height: narrowScreen ? 14 : 20),
          Text(
            'Riwayat Mutasi ($filteredCount)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Periode: $periodLabel',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade700,
                ),
          ),
        ],
      ),
    );
  }
}
