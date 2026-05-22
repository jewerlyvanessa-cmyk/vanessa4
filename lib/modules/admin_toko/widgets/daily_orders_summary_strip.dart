import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/modules/admin_toko/utils/daily_orders_payments_helpers.dart';

Widget dailyOrdersMiniChip(
  BuildContext context,
  String label,
  IconData icon, {
  Color? color,
}) {
  return Chip(
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 2),
    avatar: Icon(icon, size: 16, color: color),
    label: Text(label, style: TextStyle(fontSize: 12, color: color)),
    side: BorderSide(color: Colors.grey.shade400.withValues(alpha: 0.5)),
  );
}

Widget dailyOrdersSummaryFilterChip(
  BuildContext context, {
  required String label,
  required IconData icon,
  required bool selected,
  required ValueChanged<bool> onSelected,
  Color? iconColor,
}) {
  final cs = Theme.of(context).colorScheme;
  final accent = iconColor ?? cs.primary;
  return FilterChip(
    selected: selected,
    showCheckmark: false,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    labelPadding: const EdgeInsets.symmetric(horizontal: 2),
    avatar: Icon(
      icon,
      size: 16,
      color: selected ? cs.onSecondaryContainer : accent,
    ),
    label: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? cs.onSecondaryContainer : null,
      ),
    ),
    selectedColor: cs.secondaryContainer,
    side: BorderSide(
      color: selected
          ? cs.primary.withValues(alpha: 0.65)
          : Colors.grey.shade400.withValues(alpha: 0.5),
    ),
    onSelected: onSelected,
  );
}

/// Strip filter ringkas untuk Order Today (embed CS).
class DailyOrdersEmbedFilterStrip extends StatelessWidget {
  const DailyOrdersEmbedFilterStrip({
    super.key,
    required this.ordersRaw,
    required this.orderFilter,
    required this.onFilterChanged,
  });

  final List<dynamic> ordersRaw;
  final AdminOrderFilter orderFilter;
  final ValueChanged<AdminOrderFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final deduped = dedupeOrdersById(ordersRaw);
    final open = deduped
        .where((o) => isOpenOrderStatus(o['status']?.toString()))
        .length;
    final done = deduped
        .where((o) => isCompletedOrderStatus(o['status']?.toString()))
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          dailyOrdersSummaryFilterChip(
            context,
            label: 'Semua ${deduped.length}',
            icon: Icons.receipt_long_outlined,
            selected: orderFilter == AdminOrderFilter.all,
            onSelected: (_) => onFilterChanged(AdminOrderFilter.all),
          ),
          if (open > 0)
            dailyOrdersSummaryFilterChip(
              context,
              label: 'Belum selesai $open',
              icon: Icons.hourglass_top_outlined,
              selected: orderFilter == AdminOrderFilter.pending,
              onSelected: (sel) => onFilterChanged(
                sel ? AdminOrderFilter.pending : AdminOrderFilter.all,
              ),
              iconColor: Colors.orange.shade800,
            ),
          if (done > 0)
            dailyOrdersSummaryFilterChip(
              context,
              label: 'Selesai $done',
              icon: Icons.check_circle_outline,
              selected: orderFilter == AdminOrderFilter.completed,
              onSelected: (sel) => onFilterChanged(
                sel ? AdminOrderFilter.completed : AdminOrderFilter.all,
              ),
              iconColor: Colors.green.shade700,
            ),
        ],
      ),
    );
  }
}

/// Strip ringkasan order + pembayaran (admin toko / service-custom).
class DailyOrdersCompactSummaryStrip extends StatelessWidget {
  const DailyOrdersCompactSummaryStrip({
    super.key,
    required this.selectedDate,
    required this.dailyData,
    required this.orderFilter,
    required this.serviceCustomMode,
    required this.ordersOnly,
    required this.onFilterChanged,
    required this.onBatchSendToWorkshop,
    required this.onPrintSuratJalan,
  });

  final DateTime selectedDate;
  final Map<String, dynamic> dailyData;
  final AdminOrderFilter orderFilter;
  final bool serviceCustomMode;
  final bool ordersOnly;
  final ValueChanged<AdminOrderFilter> onFilterChanged;
  final VoidCallback onBatchSendToWorkshop;
  final VoidCallback onPrintSuratJalan;

  @override
  Widget build(BuildContext context) {
    final ordersRaw = dailyData['orders'] as List<dynamic>? ?? [];
    final dedupedAll = dedupeOrdersById(ordersRaw);
    final stripOrders = serviceCustomMode
        ? dedupedAll.where(isServiceCustomOrder).toList()
        : dedupedAll;
    final totalOrders = stripOrders.length;
    final modeCounts = orderModeCounts(stripOrders);
    final completed = stripOrders
        .where((o) => isCompletedOrderStatus(o['status']?.toString()))
        .length;
    final pending = stripOrders
        .where((o) => isOpenOrderStatus(o['status']?.toString()))
        .length;
    final completedAmount = ordersOnly
        ? sumOrderAmountWhere(
            stripOrders,
            (o) => isCompletedOrderStatus(o['status']?.toString()),
          )
        : 0;
    final pendingAmount = ordersOnly
        ? sumOrderAmountWhere(
            stripOrders,
            (o) => isOpenOrderStatus(o['status']?.toString()),
          )
        : 0;
    final svcCustom = dedupedAll.where(isServiceCustomOrder).length;
    final kirimWorkshopCount = dedupedAll
        .where((o) => nextAdminTokoWorkshopStatus(o) == 'awaiting_warehouse')
        .length;

    final stripIds = stripOrders
        .map((o) => o['order_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final lineCount = countItemLineRowsForOrderIds(ordersRaw, stripIds);

    final pay = ordersOnly
        ? null
        : paymentTotalsFromDailyData(
            dailyData: dailyData,
            serviceCustomMode: serviceCustomMode,
          );
    final payIncome = pay?.income ?? 0;
    final payExpense = pay?.expense ?? 0;
    final payNet = pay?.net ?? 0;
    final payTrx = pay?.count ?? 0;

    final cs = Theme.of(context).colorScheme;
    final showModeChips = serviceCustomMode || totalOrders > 0;
    final orderChipSelected = serviceCustomMode
        ? (orderFilter == AdminOrderFilter.all ||
            orderFilter == AdminOrderFilter.serviceCustom)
        : orderFilter == AdminOrderFilter.all;

    final sudahKirimWorkshop = dedupedAll
        .where(
          (o) =>
              isServiceCustomOrder(o) &&
              (o['status'] ?? '').toString().trim().toLowerCase() ==
                  'awaiting_warehouse',
        )
        .toList();

    final rowChildren = <Widget>[
      Text(
        DateFormat('dd MMM yyyy', 'id_ID').format(selectedDate),
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      dailyOrdersSummaryFilterChip(
        context,
        label: 'Order $totalOrders',
        icon: Icons.receipt_long_outlined,
        selected: orderChipSelected,
        onSelected: (_) => onFilterChanged(AdminOrderFilter.all),
      ),
      if (showModeChips) ...[
        dailyOrdersSummaryFilterChip(
          context,
          label: 'Toko ${modeCounts.toko}',
          icon: Icons.storefront_outlined,
          selected: orderFilter == AdminOrderFilter.toko,
          onSelected: (sel) => onFilterChanged(
            sel ? AdminOrderFilter.toko : AdminOrderFilter.all,
          ),
        ),
        dailyOrdersSummaryFilterChip(
          context,
          label: 'Online ${modeCounts.online}',
          icon: Icons.language_outlined,
          selected: orderFilter == AdminOrderFilter.online,
          onSelected: (sel) => onFilterChanged(
            sel ? AdminOrderFilter.online : AdminOrderFilter.all,
          ),
        ),
      ],
      if (kIsWeb || serviceCustomMode)
        dailyOrdersMiniChip(
          context,
          '$lineCount baris item',
          Icons.view_list_outlined,
        ),
      dailyOrdersSummaryFilterChip(
        context,
        label: ordersOnly
            ? 'Selesai $completed · ${fmtDailyOrderMoney(completedAmount)}'
            : 'Selesai $completed',
        icon: Icons.check_circle_outline,
        selected: orderFilter == AdminOrderFilter.completed,
        onSelected: (sel) => onFilterChanged(
          sel ? AdminOrderFilter.completed : AdminOrderFilter.all,
        ),
        iconColor: Colors.green.shade700,
      ),
      dailyOrdersSummaryFilterChip(
        context,
        label: ordersOnly
            ? 'Pending $pending · ${fmtDailyOrderMoney(pendingAmount)}'
            : 'Pending $pending',
        icon: Icons.hourglass_top_outlined,
        selected: orderFilter == AdminOrderFilter.pending,
        onSelected: (sel) => onFilterChanged(
          sel ? AdminOrderFilter.pending : AdminOrderFilter.all,
        ),
        iconColor: Colors.orange.shade800,
      ),
      if (!serviceCustomMode && svcCustom > 0)
        dailyOrdersSummaryFilterChip(
          context,
          label: 'Service/Custom $svcCustom',
          icon: Icons.build_circle_outlined,
          selected: orderFilter == AdminOrderFilter.serviceCustom,
          onSelected: (sel) => onFilterChanged(
            sel ? AdminOrderFilter.serviceCustom : AdminOrderFilter.all,
          ),
          iconColor: Colors.deepOrange.shade800,
        ),
      if (kirimWorkshopCount > 0) ...[
        dailyOrdersSummaryFilterChip(
          context,
          label: 'Kirim workshop $kirimWorkshopCount',
          icon: Icons.local_shipping_outlined,
          selected: orderFilter == AdminOrderFilter.kirimWorkshop,
          onSelected: (sel) => onFilterChanged(
            sel ? AdminOrderFilter.kirimWorkshop : AdminOrderFilter.all,
          ),
          iconColor: Colors.brown.shade700,
        ),
        if (serviceCustomMode) ...[
          ActionChip(
            avatar: Icon(Icons.playlist_add_check, size: 18, color: cs.primary),
            label: Text('Kirim dokumen ($kirimWorkshopCount)'),
            onPressed: onBatchSendToWorkshop,
          ),
          if (sudahKirimWorkshop.isNotEmpty)
            ActionChip(
              avatar: Icon(Icons.print_outlined, size: 18, color: cs.primary),
              label: Text('Cetak surat jalan (${sudahKirimWorkshop.length})'),
              onPressed: onPrintSuratJalan,
            ),
        ],
      ],
      if (!ordersOnly) ...[
        dailyOrdersMiniChip(
          context,
          'Masuk ${fmtDailyOrderMoney(payIncome)}',
          Icons.south_west,
          color: Colors.green.shade800,
        ),
        if (payExpense > 0)
          dailyOrdersMiniChip(
            context,
            'Keluar ${fmtDailyOrderMoney(payExpense)}',
            Icons.north_east,
            color: Colors.red.shade700,
          ),
        dailyOrdersMiniChip(
          context,
          'Net ${fmtDailyOrderMoney(payNet)}',
          Icons.payments_outlined,
          color: cs.primary,
        ),
        dailyOrdersMiniChip(context, '$payTrx trx', Icons.swap_horiz_rounded),
      ],
    ];

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.start,
          children: rowChildren,
        ),
      ),
    );
  }
}
