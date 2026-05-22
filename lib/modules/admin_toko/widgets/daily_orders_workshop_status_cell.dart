import 'package:flutter/material.dart';
import 'package:vanessa3/modules/admin_toko/utils/daily_orders_payments_helpers.dart';
import 'package:vanessa3/utils/order_status_ui.dart';

/// Sel status order + tombol aksi workshop (kirim / terima) untuk admin toko.
class DailyOrdersWorkshopStatusCell extends StatelessWidget {
  const DailyOrdersWorkshopStatusCell({
    super.key,
    required this.row,
    required this.onWorkshopAction,
  });

  final Map<String, dynamic> row;
  final void Function(Map<String, dynamic> row, String nextStatus) onWorkshopAction;

  @override
  Widget build(BuildContext context) {
    final statusStr = row['status']?.toString();
    final nextStatus = nextAdminTokoWorkshopStatus(row);
    final statusWidget = Text(
      orderStatusLabel(statusStr),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: OrderStatusUi.color(statusStr),
        fontWeight: FontWeight.w600,
        fontSize: 12,
        height: 1.2,
      ),
    );
    if (nextStatus == null) return statusWidget;

    final IconData icon;
    switch (nextStatus) {
      case 'awaiting_warehouse':
        icon = Icons.local_shipping_outlined;
        break;
      case 'ready_for_pickup':
        icon = Icons.inventory_2_outlined;
        break;
      default:
        icon = Icons.more_horiz;
    }

    return Row(
      children: [
        Expanded(child: statusWidget),
        IconButton(
          icon: Icon(icon, size: 18),
          tooltip: adminTokoWorkshopActionLabel(nextStatus),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => onWorkshopAction(row, nextStatus),
        ),
      ],
    );
  }
}
