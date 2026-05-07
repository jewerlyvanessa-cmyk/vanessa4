import 'package:flutter/material.dart';

/// Label ringkasan untuk nilai filter (`all` → Semua).
String stockUiFilterScopeLabel(String selectedStatus) {
  if (selectedStatus == 'all') return 'Semua';
  return stockItemStatusLabel(selectedStatus);
}

/// Label status untuk tampilan (baris item / filter).
String stockItemStatusLabel(String status) {
  switch (status) {
    case 'ready':
      return 'Ready';
    case 'reserved':
      return 'Reserved';
    case 'sold':
      return 'Sold';
    case 'buyback':
      return 'Buyback';
    case 'on-service':
      return 'On Service';
    case 'on-custom':
      return 'On Custom';
    default:
      return status;
  }
}

/// Quantity baris stok untuk filter/tampilan (`quantity` atau `qty`).
int stockItemQuantity(dynamic item) {
  final raw = item['quantity'] ?? item['qty'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? 1;
}

/// Cocok untuk filter status [selectedStatus] (bukan `'all'`).
bool stockItemVisibleForStatusFilter(dynamic item, String selectedStatus) {
  if ((item['status'] ?? '').toString() != selectedStatus) return false;
  // Ready dengan qty 0 tetap `status` ready di DB, tapi tidak dianggap stok siap.
  if (selectedStatus == 'ready' && stockItemQuantity(item) <= 0) return false;
  return true;
}

int stockListSumQuantity(List<dynamic> items) {
  var s = 0;
  for (final item in items) {
    final q = item['quantity'];
    if (q is int) {
      s += q;
    } else {
      s += int.tryParse(q?.toString() ?? '') ?? 1;
    }
  }
  return s;
}

double stockListSumWeightGram(List<dynamic> items) {
  var total = 0.0;
  for (final item in items) {
    final rawWeight = item['weight'];
    final rawQty = item['quantity'];
    final weightPerItem = rawWeight is num
        ? rawWeight.toDouble()
        : double.tryParse(rawWeight?.toString() ?? '') ?? 0.0;
    final qty = rawQty is int
        ? rawQty
        : int.tryParse(rawQty?.toString() ?? '') ?? 1;
    if (weightPerItem > 0 && qty > 0) {
      total += weightPerItem * qty;
    }
  }
  return total;
}

String stockListFormatWeightGram(double g) {
  if (g >= 1000) return '${(g / 1000).toStringAsFixed(2)} kg';
  if (g <= 0) return '0 g';
  return '${g.toStringAsFixed(1)} g';
}

/// Tombol filter status ([Wrap], turun ke baris berikut jika lebar tidak cukup) + ringkasan SKU/Qty/Berat.
class StockStatusFilterSummaryHeader extends StatelessWidget {
  const StockStatusFilterSummaryHeader({
    super.key,
    required this.selectedStatus,
    required this.onStatusChanged,
    required this.summaryItems,
    this.filterLabel = 'Filter status',
  });

  final String selectedStatus;
  final ValueChanged<String> onStatusChanged;
  final List<dynamic> summaryItems;
  final String filterLabel;

  static const List<(String value, String label)> _statusOptions = [
    ('all', 'Semua'),
    ('ready', 'Ready'),
    ('reserved', 'Reserved'),
    ('sold', 'Sold'),
    ('buyback', 'Buyback'),
    ('on-service', 'On Service'),
    ('on-custom', 'On Custom'),
  ];

  Widget _metric(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                height: 1.15,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusFilterChips(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          filterLabel,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.start,
          children: [
            for (final e in _statusOptions)
              ChoiceChip(
                label: Text(e.$2),
                selected: selectedStatus == e.$1,
                onSelected: (selected) {
                  if (selected) onStatusChanged(e.$1);
                },
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = stockUiFilterScopeLabel(selectedStatus);
    final count = summaryItems.length;
    final qty = stockListSumQuantity(summaryItems);
    final w = stockListSumWeightGram(summaryItems);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statusFilterChips(context),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _metric(context, 'SKU ($scope)', '$count'),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _metric(context, 'Qty ($scope)', '$qty'),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _metric(
                context,
                'Berat ($scope)',
                stockListFormatWeightGram(w),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
