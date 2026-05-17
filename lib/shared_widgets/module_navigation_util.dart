// Fungsi utilitas global untuk navigasi modul utama berdasarkan role
import 'package:flutter/material.dart';
import 'package:vanessa3/routes/app_routes.dart';

String getMainModuleForRole(String role) {
  final normalized = role.trim().toLowerCase();
  switch (normalized) {
    case 'cs':
      return 'cs';
    case 'kasir':
      return 'kasir';
    case 'superadmin':
      return 'superadmin';
    case 'admin_toko':
      return 'admin_toko';
    case 'admin_workshop':
      return 'admin_workshop';
    case 'admin_warehouse':
      return 'admin_warehouse';
    case 'tukang':
      return 'tukang';
    case 'manajer':
      return 'manajer';
    case 'stockist':
      return 'stockist';
    default:
      return 'dashboard';
  }
}

void navigateToMainModule(BuildContext context, String mainModule) {
  final navigator = Navigator.of(context);
  final normalized = mainModule.trim().toLowerCase();
  switch (normalized) {
    case 'cs':
      navigator.pushReplacementNamed(AppRoutes.cs);
      break;
    case 'kasir':
      navigator.pushReplacementNamed(AppRoutes.kasir);
      break;
    case 'superadmin':
      navigator.pushReplacementNamed(AppRoutes.superadmin);
      break;
    case 'admin_toko':
      navigator.pushReplacementNamed(AppRoutes.adminToko);
      break;
    case 'admin_workshop':
      navigator.pushReplacementNamed(AppRoutes.adminWorkshop);
      break;
    case 'admin_warehouse':
      navigator.pushReplacementNamed(AppRoutes.adminWarehouse);
      break;
    case 'tukang':
      navigator.pushReplacementNamed(AppRoutes.tukang);
      break;
    case 'manajer':
      navigator.pushReplacementNamed(AppRoutes.manajer);
      break;
    case 'stockist':
      navigator.pushReplacementNamed(AppRoutes.stockist);
      break;
    default:
      navigator.pushReplacementNamed(AppRoutes.dashboard);
  }
}
