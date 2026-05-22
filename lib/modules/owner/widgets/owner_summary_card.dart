import 'package:flutter/material.dart';

/// Kartu ringkasan Owner — tap untuk halaman detail.
class OwnerSummaryCard extends StatelessWidget {
  const OwnerSummaryCard({
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
              if (!loading && secondaryText != null && secondaryText!.isNotEmpty) ...[
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
