import 'package:flutter/material.dart';
import 'package:vanessa3/routes/app_routes.dart';

/// Navigasi terpusat ke rute bernama [AppRoutes].
void pushAppRoute(BuildContext context, String route) {
  Navigator.pushNamed(context, route);
}

/// Halaman bayar per order (butuh data order).
Future<T?> pushKasirPayment<T extends Object?>(
  BuildContext context,
  Map<String, dynamic> order,
) {
  return Navigator.pushNamed<T>(
    context,
    AppRoutes.kasirPayment,
    arguments: order,
  );
}
