import 'package:flutter/material.dart';

class StockMutationSummaryCard extends StatelessWidget {
  const StockMutationSummaryCard({
    super.key,
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    required this.filterType,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final int count;
  final IconData icon;
  final Color color;
  final String filterType;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final narrow = screenW < 600;
    final extraCompact = screenW < 420;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? color : Colors.transparent,
          width: isSelected ? 1.6 : 0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: extraCompact ? 8 : (narrow ? 10 : 16),
            horizontal: extraCompact ? 8 : (narrow ? 10 : 16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: extraCompact ? 30 : (narrow ? 34 : 38),
                height: extraCompact ? 30 : (narrow ? 34 : 38),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isSelected ? 0.22 : 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: extraCompact ? 18 : (narrow ? 20 : 22),
                ),
              ),
              SizedBox(width: extraCompact ? 8 : 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: extraCompact ? 11 : 12,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: extraCompact ? 6 : 10),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: extraCompact ? 18 : (narrow ? 20 : 24),
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
