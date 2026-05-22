import 'package:flutter/material.dart';

import 'package:vanessa3/utils/responsive_layout.dart';

/// Grid responsif untuk [GlobalSummaryCard] — aman di web release (tanpa Wrap/lebar ∞).
class GlobalSummaryCardsLayout extends StatelessWidget {
  const GlobalSummaryCardsLayout({
    super.key,
    required this.cards,
  });

  final List<Widget> cards;

  static int _columnCount(double contentWidth) {
    if (contentWidth >= 900) return 3;
    if (contentWidth >= 520) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();

    final horizontalPad = ResponsiveLayout.roleMenuHorizontalPadding.horizontal;
    final contentWidth = MediaQuery.sizeOf(context).width - horizontalPad;
    final cols = _columnCount(contentWidth);
    const gap = 12.0;

    if (cols == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: gap),
            cards[i],
          ],
        ],
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += cols) {
      final end = (i + cols < cards.length) ? i + cols : cards.length;
      final slice = cards.sublist(i, end);
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var j = 0; j < cols; j++)
                Expanded(
                  child: j < slice.length
                      ? slice[j]
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// Kartu ringkasan global (penjualan / buyback / stok) — dipakai Owner & Manajer.
class GlobalSummaryCard extends StatelessWidget {
  const GlobalSummaryCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.primaryText,
    this.secondaryText,
    this.loading = false,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String primaryText;
  final String? secondaryText;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 26),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color.withValues(alpha: 0.95),
                      ),
                    ),
                  ),
                  if (onTap != null && !loading)
                    Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (loading)
                const SizedBox(
                  height: 28,
                  width: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  primaryText,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              if (!loading &&
                  secondaryText != null &&
                  secondaryText!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  secondaryText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
