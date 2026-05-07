import 'package:flutter/material.dart';

import 'stock_inventory_grouped_table.dart';

/// Jumlah qty aggregate untuk ringkasan per jenis.
int sumStockQtyForMaps(List<Map<String, dynamic>> rows) {
  var s = 0;
  for (final r in rows) {
    final q = r['quantity'] ?? r['qty'];
    if (q is num) {
      s += q.round();
    } else {
      s += int.tryParse(q?.toString().trim() ?? '') ?? 0;
    }
  }
  return s;
}

List<dynamic> filterStockItemsByJenisLabel(List<dynamic> raw, String label) {
  return raw.where((it) {
    if (it is! Map) return false;
    final m = Map<String, dynamic>.from(it);
    return stockItemJenisLabel(m) == label;
  }).toList();
}

/// Awalnya hanya daftar **jenis**; ketuk jenis → [detailBuilder] dengan item terfilter.
class StockJenisTwoStepPanel extends StatelessWidget {
  const StockJenisTwoStepPanel({
    super.key,
    required this.filteredItems,
    required this.selectedJenisLabel,
    required this.onSelectedJenisLabelChanged,
    required this.detailBuilder,
    this.emptyMessage = 'Stok kosong',
    this.emptyDetailMessage = 'Tidak ada item untuk filter ini',
  });

  final List<dynamic> filteredItems;
  final String? selectedJenisLabel;
  final ValueChanged<String?> onSelectedJenisLabelChanged;
  final Widget Function(BuildContext context, List<dynamic> itemsForJenis)
      detailBuilder;
  final String emptyMessage;
  final String emptyDetailMessage;

  @override
  Widget build(BuildContext context) {
    if (filteredItems.isEmpty) {
      return Center(child: Text(emptyMessage));
    }
    if (selectedJenisLabel == null) {
      return _JenisPickerList(
        groups: groupStockItemsByJenis(filteredItems),
        onSelect: (label) => onSelectedJenisLabelChanged(label),
      );
    }
    final label = selectedJenisLabel!;
    final items = filterStockItemsByJenisLabel(filteredItems, label);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _JenisDetailBar(
          label: label,
          onBack: () => onSelectedJenisLabelChanged(null),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(emptyDetailMessage))
              : detailBuilder(context, items),
        ),
      ],
    );
  }
}

class _JenisPickerList extends StatelessWidget {
  const _JenisPickerList({
    required this.groups,
    required this.onSelect,
  });

  final List<MapEntry<String, List<Map<String, dynamic>>>> groups;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final e = groups[i];
        final label = e.key;
        final rows = e.value;
        final n = rows.length;
        final qtySum = sumStockQtyForMaps(rows);
        return Material(
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onSelect(label),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.category_outlined, color: scheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$n item • total qty $qtySum',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _JenisDetailBar extends StatelessWidget {
  const _JenisDetailBar({
    required this.label,
    required this.onBack,
  });

  final String label;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Semua jenis',
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
            ),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
