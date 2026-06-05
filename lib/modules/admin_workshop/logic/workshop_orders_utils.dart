import 'package:flutter/material.dart';
import 'package:vanessa3/modules/admin_workshop/logic/workshop_orders_types.dart';
import 'package:vanessa3/utils/order_status_ui.dart';

abstract final class WorkshopOrdersUtils {
  WorkshopOrdersUtils._();

  static bool isInProgressStatus(String s) =>
      s == 'repairing' ||
      s == 'polishing' ||
      s == 'custom_work' ||
      s == 'in_workshop';

  static bool roleCanPutTechnicianWorkshopFlow(String role) =>
      {'superadmin', 'manajer', 'tukang'}.contains(role);

  static Color statusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'repairing':
      case 'polishing':
      case 'custom_work':
        return Colors.orange;
      default:
        return OrderStatusUi.color(status);
    }
  }

  static String statusLabel(String? status) {
    switch (status) {
      case 'all':
        return 'Semua Status';
      case 'pending':
        return 'Baru masuk';
      case 'in_progress':
        return 'Dalam Proses';
      case 'repairing':
        return 'Dikerjakan';
      case 'polishing':
        return 'Poles/Finishing';
      case 'custom_work':
        return 'Custom Work';
      case 'ready_for_pickup':
        return 'Kirim ke Toko (Siap Diambil)';
      default:
        return OrderStatusUi.label(status);
    }
  }

  static String scopeSubtitle(String scope) {
    switch (scope) {
      case 'local':
        return 'Hanya order dibuat di cabang ini (sama antrian, disaring)';
      case 'cross_branch':
        return 'Hanya kiriman dari cabang lain (sama antrian, disaring)';
      default:
        return 'Sama dengan antrian kerja tukang (belum selesai workshop)';
    }
  }

  static String emptyListMessage({
    required WorkshopOrdersViewMode viewMode,
    required String selectedStatus,
    required String scope,
  }) {
    if (viewMode == WorkshopOrdersViewMode.inProgress) {
      return 'Tidak ada pekerjaan yang sedang dikerjakan tukang di cabang ini.';
    }
    final filt = selectedStatus == 'all'
        ? ''
        : ' (filter: ${statusLabel(selectedStatus)})';
    if (scope == 'local') {
      return 'Tidak ada order antrian cabang ini$filt';
    }
    if (scope == 'cross_branch') {
      return 'Tidak ada kiriman cabang lain di antrian$filt';
    }
    return 'Tidak ada order di antrian kerja$filt.\n'
        'Order menunggu persetujuan workshop: buka menu TOKO → Service dari toko, '
        'lalu setujui agar masuk antrian ini.';
  }
}
