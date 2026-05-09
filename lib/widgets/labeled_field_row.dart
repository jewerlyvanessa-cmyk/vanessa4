import 'package:flutter/material.dart';

/// Standard row layout: fixed-width label + field.
///
/// Use this to keep form alignment consistent across pages.
class LabeledFieldRow extends StatelessWidget {
  const LabeledFieldRow({
    super.key,
    required this.label,
    required this.child,
    this.labelWidth = 120,
    this.gap = 8,
    this.verticalPadding = 0,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final String label;
  final Widget child;
  final double labelWidth;
  final double gap;
  final double verticalPadding;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Row(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          SizedBox(
            width: labelWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: tt.bodyMedium,
              ),
            ),
          ),
          SizedBox(width: gap),
          Expanded(child: child),
        ],
      ),
    );
  }
}

