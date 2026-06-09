import 'package:flutter/material.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

/// Body halaman menu utama role — aman dari navigation bar bawah.
class RoleMenuBody extends StatelessWidget {
  const RoleMenuBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout.scaffoldBody(child);
  }
}
