import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Pecahan tunai standar (Rupiah), terbesar dulu.
const List<int> kCashDenominations = [
  1000000,
  500000,
  100000,
  50000,
  20000,
  10000,
  5000,
];

final _rupiahFmt = NumberFormat('#,###', 'id_ID');

String formatCashDenomLabel(int nominal) => 'Rp ${_rupiahFmt.format(nominal)}';

/// Label singkat untuk tombol pecahan.
String cashDenomButtonLabel(int nominal) {
  if (nominal >= 1000000) return '${nominal ~/ 1000000} jt';
  if (nominal >= 1000) return '${nominal ~/ 1000} rb';
  return '$nominal';
}

/// Input pecahan tunai berupa tombol (ketuk = +1 lembar).
class CashDenominationInput extends StatelessWidget {
  const CashDenominationInput({
    super.key,
    required this.counts,
    required this.onCountsChanged,
  });

  final Map<int, int> counts;
  final void Function(Map<int, int> counts, double total) onCountsChanged;

  static double totalFromCounts(Map<int, int> counts) {
    var sum = 0.0;
    for (final d in kCashDenominations) {
      final n = counts[d] ?? 0;
      if (n > 0) sum += d * n;
    }
    return sum;
  }

  void _setCount(int denom, int next) {
    final c = Map<int, int>.from(counts);
    c[denom] = next < 0 ? 0 : next;
    onCountsChanged(c, totalFromCounts(c));
  }

  @override
  Widget build(BuildContext context) {
    final total = totalFromCounts(counts);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pecahan uang',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Ketuk tombol untuk menambah lembar',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 10,
          children: [
            for (final denom in kCashDenominations)
              _DenomButton(
                denom: denom,
                count: counts[denom] ?? 0,
                onAdd: () => _setCount(denom, (counts[denom] ?? 0) + 1),
                onRemove: () => _setCount(denom, (counts[denom] ?? 0) - 1),
              ),
          ],
        ),
        if (total > 0) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => onCountsChanged(
                {for (final d in kCashDenominations) d: 0},
                0,
              ),
              icon: const Icon(Icons.clear, size: 18),
              label: const Text('Reset pecahan'),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total dari pecahan',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  formatCashDenomLabel(total.round()),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DenomButton extends StatelessWidget {
  const _DenomButton({
    required this.denom,
    required this.count,
    required this.onAdd,
    required this.onRemove,
  });

  final int denom;
  final int count;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final short = cashDenomButtonLabel(denom);
    final full = formatCashDenomLabel(denom);

    return Material(
      color: count > 0
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minWidth: 88, minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                short,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: count > 0
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                ),
              ),
              Text(
                full,
                style: TextStyle(
                  fontSize: 10,
                  color: count > 0
                      ? scheme.onPrimaryContainer.withValues(alpha: 0.85)
                      : scheme.onSurfaceVariant,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: onRemove,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.remove,
                          size: 16,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '×$count',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Ringkasan pecahan untuk catatan pembayaran.
String cashDenominationNotesSummary(Map<int, int> counts) {
  final parts = <String>[];
  for (final d in kCashDenominations) {
    final n = counts[d] ?? 0;
    if (n <= 0) continue;
    final label = cashDenomButtonLabel(d);
    parts.add('$label×$n');
  }
  if (parts.isEmpty) return '';
  return 'pecahan: ${parts.join(', ')}';
}
