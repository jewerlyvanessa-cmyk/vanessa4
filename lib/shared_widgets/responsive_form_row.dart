import 'package:flutter/material.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

/// Baris label + field: horizontal di layar lebar, vertikal di layar sempit.
class ResponsiveFormRow extends StatelessWidget {
  const ResponsiveFormRow({
    super.key,
    required this.label,
    required this.child,
    this.actions = const [],
    this.helper,
    this.spacing = 12,
    this.stackBelowWidth = 480,
  });

  final String label;
  final Widget child;
  final List<Widget> actions;
  final Widget? helper;
  final double spacing;
  final double stackBelowWidth;

  @override
  Widget build(BuildContext context) {
    final stack = ResponsiveLayout.widthOf(context) < stackBelowWidth;
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500);

    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(height: 6),
          child,
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ],
          if (helper != null) ...[const SizedBox(height: 4), helper!],
          SizedBox(height: spacing),
        ],
      );
    }

    final labelW = ResponsiveLayout.labelColumnWidth(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: labelW,
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(label, style: labelStyle),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: child),
            ...actions,
          ],
        ),
        if (helper != null)
          Padding(
            padding: EdgeInsets.only(left: labelW + 8, top: 4),
            child: helper!,
          ),
        SizedBox(height: spacing),
      ],
    );
  }
}

/// Beberapa kartu ringkas: kolom di layar sempit, baris di layar lebar.
class ResponsiveMetricRow extends StatelessWidget {
  const ResponsiveMetricRow({
    super.key,
    required this.children,
    this.spacing = 8,
    this.stackBelowWidth = 520,
  });

  final List<Widget> children;
  final double spacing;
  final double stackBelowWidth;

  @override
  Widget build(BuildContext context) {
    final stack = ResponsiveLayout.widthOf(context) < stackBelowWidth;
    if (stack) {
      return Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            children[i],
          ],
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: spacing),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

/// Tombol aksi bawah form (Batal / Simpan): bertumpuk di layar sangat sempit.
class ResponsiveDualActions extends StatelessWidget {
  const ResponsiveDualActions({
    super.key,
    required this.secondary,
    required this.primary,
    this.stackBelowWidth = 400,
  });

  final Widget secondary;
  final Widget primary;
  final double stackBelowWidth;

  @override
  Widget build(BuildContext context) {
    final stack = ResponsiveLayout.widthOf(context) < stackBelowWidth;
    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [primary, const SizedBox(height: 10), secondary],
      );
    }
    return Row(
      children: [
        Expanded(child: secondary),
        const SizedBox(width: 12),
        Expanded(child: primary),
      ],
    );
  }
}

/// Scroll horizontal aman untuk [DataTable] / konten lebar.
class ResponsiveHorizontalScroll extends StatelessWidget {
  const ResponsiveHorizontalScroll({
    super.key,
    required this.child,
    this.minWidth,
  });

  final Widget child;
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minW = minWidth ?? constraints.maxWidth;
        return Scrollbar(
          thumbVisibility: ResponsiveLayout.isCompact(context),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: minW.clamp(constraints.maxWidth, double.infinity),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
