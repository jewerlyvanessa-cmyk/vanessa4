import 'package:flutter/material.dart';

class CustomersSummaryMetricCard extends StatelessWidget {
  const CustomersSummaryMetricCard({
    super.key,
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    this.compact = false,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconSize = compact ? 20.0 : 24.0;
    final iconInset = compact ? 8.0 : 10.0;
    final gap = compact ? 8.0 : 12.0;
    final radius = compact ? 14.0 : 16.0;
    final iconBoxRadius = compact ? 10.0 : 12.0;

    return Material(
      elevation: 0,
      color: cs.surfaceContainerLow.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(radius),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 10 : 12,
        ),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  accent.withValues(alpha: 0.22),
                  cs.surfaceContainerHigh,
                ),
                borderRadius: BorderRadius.circular(iconBoxRadius),
              ),
              child: Padding(
                padding: EdgeInsets.all(iconInset),
                child: Icon(icon, size: iconSize, color: accent),
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          fontSize: compact ? 11 : null,
                          height: 1.15,
                        ),
                  ),
                  SizedBox(height: compact ? 2 : 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: compact
                          ? Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.35,
                              )
                          : Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
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
