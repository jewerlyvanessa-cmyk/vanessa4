import 'package:flutter/material.dart';

/// Label dan warna role karyawan toko/workshop.
abstract final class EmployeeRoleUtils {
  EmployeeRoleUtils._();

  static const assignableRoles = [
    'cs',
    'kasir',
    'admin_toko',
    'admin_workshop',
    'admin_warehouse',
    'stockist',
    'tukang',
    'manajer',
  ];

  static String label(String? role) {
    switch (role) {
      case 'cs':
        return 'Customer Service';
      case 'kasir':
        return 'Kasir';
      case 'admin_toko':
        return 'Admin Toko';
      case 'admin_workshop':
        return 'Admin Workshop';
      case 'admin_warehouse':
        return 'Admin Warehouse';
      case 'stockist':
        return 'Stockist';
      case 'tukang':
        return 'Tukang';
      case 'manajer':
        return 'Manajer';
      case 'superadmin':
        return 'Super Admin';
      default:
        return role?.isNotEmpty == true ? role! : 'Unknown';
    }
  }

  static Color roleColor(String? role) {
    switch (role) {
      case 'cs':
        return Colors.blue;
      case 'kasir':
        return Colors.green;
      case 'admin_toko':
        return Colors.orange;
      case 'admin_workshop':
        return Colors.purple;
      case 'admin_warehouse':
        return Colors.brown;
      case 'stockist':
        return Colors.blueGrey;
      case 'tukang':
        return Colors.red;
      case 'manajer':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }
}
