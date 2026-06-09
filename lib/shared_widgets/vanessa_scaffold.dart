import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

/// [Scaffold] standar Vanessa — AppBar bebas penuh; body aman dari navigation bar.
class VanessaScaffold extends StatelessWidget {
  const VanessaScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset = true,
    this.drawer,
    this.endDrawer,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final bool resizeToAvoidBottomInset;
  final Widget? drawer;
  final Widget? endDrawer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      drawer: drawer,
      endDrawer: endDrawer,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: _wrapBottomBar(bottomNavigationBar),
      body: _wrapBody(body),
    );
  }

  Widget _wrapBody(Widget child) {
    if (kIsWeb) return child;
    return ResponsiveLayout.scaffoldBody(child);
  }

  Widget? _wrapBottomBar(Widget? bar) {
    if (bar == null) return null;
    return SafeArea(
      top: false,
      left: false,
      right: false,
      minimum: EdgeInsets.zero,
      child: bar,
    );
  }
}
