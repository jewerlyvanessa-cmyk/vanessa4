import 'package:flutter/material.dart';

/// Shared status presentation across the app.
///
/// Keep this as the single source of truth so status labels/colors stay consistent
/// in CS/Admin/Tukang modules.
class OrderStatusUi {
  static String label(String? status) {
    switch (status?.toLowerCase()) {
      case 'draft':
        return 'Draft';
      case 'pending':
        return 'Pending';
      case 'confirmed':
        return 'Konfirmasi toko';
      case 'awaiting_warehouse':
        return 'Menunggu gudang';
      case 'reserved':
        return 'Reserved';
      case 'sold':
        return 'Terjual';
      case 'buyback':
        return 'Buyback';
      case 'on-service':
        return 'Sedang Service';
      case 'production':
        return 'Produksi';
      case 'completed':
        return 'Selesai';
      case 'cancelled':
        return 'Dibatalkan';
      // Workshop lifecycle (seen in admin_workshop / tukang)
      case 'sent-to-workshop':
        return 'Ke Workshop';
      case 'in_workshop':
        return 'Di Workshop';
      case 'done_workshop':
        return 'Selesai Workshop';
      case 'ready_for_pickup':
        return 'Siap Diambil';
      default:
        final s = status?.toString().trim();
        return (s == null || s.isEmpty) ? '—' : s;
    }
  }

  static Color color(String? status) {
    switch (status?.toLowerCase()) {
      case 'draft':
        return Colors.grey;
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.amber.shade800;
      case 'awaiting_warehouse':
        return Colors.deepOrange;
      case 'reserved':
        return Colors.blue;
      case 'sold':
      case 'completed':
        return Colors.green;
      case 'buyback':
        return Colors.teal;
      case 'on-service':
        return Colors.orange;
      case 'production':
        return Colors.purple;
      case 'cancelled':
        return Colors.red;
      case 'sent-to-workshop':
        return Colors.indigo;
      case 'in_workshop':
        return Colors.deepPurple;
      case 'done_workshop':
        return Colors.blueGrey;
      case 'ready_for_pickup':
        return Colors.green.shade700;
      default:
        return Colors.grey;
    }
  }
}

