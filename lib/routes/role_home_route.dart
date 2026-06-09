import 'package:vanessa3/routes/app_routes.dart';

/// Rute home setelah login / restore sesi, berdasarkan peran aktif.
String homeRouteForRole(String role) {
  return switch (role.trim().toLowerCase()) {
    'cs' => AppRoutes.cs,
    'kasir' => AppRoutes.kasir,
    'superadmin' => AppRoutes.superadmin,
    'admin_toko' => AppRoutes.adminToko,
    'admin_workshop' => AppRoutes.adminWorkshop,
    'admin_warehouse' => AppRoutes.adminWarehouse,
    'tukang' => AppRoutes.tukang,
    'manajer' => AppRoutes.manajer,
    'owner' => AppRoutes.owner,
    'stockist' => AppRoutes.stockist,
    _ => AppRoutes.dashboard,
  };
}
