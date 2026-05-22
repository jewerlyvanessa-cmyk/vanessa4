import 'package:flutter/material.dart';
import 'package:vanessa3/routes/app_routes.dart';

/// Clears the navigator stack and shows [AppRoutes.login].
void navigateToLoginClearingStack(
  GlobalKey<NavigatorState> navigatorKey, {
  String? message,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
    final text = message?.trim();
    if (text == null || text.isEmpty) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(text)));
  });
}
