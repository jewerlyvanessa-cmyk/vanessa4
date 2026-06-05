import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/modules/admin_workshop/logic/workshop_orders_utils.dart';

Future<void> updateWorkshopOrderStatus({
  required BuildContext context,
  required dynamic order,
  required String nextStatus,
  required String branchId,
  required VoidCallback onSuccess,
}) async {
  try {
    final oid = order['order_id']?.toString();
    if (oid == null || oid.isEmpty) return;
    final response = await ApiClient.put(
      '/workshop-orders/$oid/status',
      body: jsonEncode({
        'status': nextStatus,
        'branch_id': branchId,
      }),
    );
    if (response.statusCode == 200) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status order #$oid -> $nextStatus')),
        );
      }
      onSuccess();
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal update status: ${response.body}')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error update status: $e')),
      );
    }
  }
}

Future<void> showWorkshopStatusDialog({
  required BuildContext context,
  required dynamic order,
  required String role,
  required String branchId,
  required VoidCallback onSuccess,
}) async {
  final current = (order['status'] ?? '').toString().trim().toLowerCase();
  final canReceiveFromWarehouse = {'superadmin', 'manajer'}.contains(role);
  final canTechPut = WorkshopOrdersUtils.roleCanPutTechnicianWorkshopFlow(role);
  final canMarkReadyForPickup = {
    'admin_workshop',
    'admin_toko',
    'superadmin',
    'manajer',
  }.contains(role);

  final options = <String>[
    if (current == 'awaiting_warehouse' && canReceiveFromWarehouse)
      'sent-to-workshop',
    if (current == 'sent-to-workshop' && canTechPut) 'in_workshop',
    if (current == 'in_workshop' && canTechPut)
      ...['repairing', 'polishing', 'done_workshop'],
    if (current == 'repairing' && canTechPut)
      ...['polishing', 'done_workshop'],
    if ((current == 'polishing' || current == 'custom_work') && canTechPut)
      'done_workshop',
    if (current == 'done_workshop' && canMarkReadyForPickup)
      'ready_for_pickup',
  ];

  if (options.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada transisi status yang tersedia')),
      );
    }
    return;
  }

  final selected = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text('Update status #${order['order_id']}'),
      children: [
        for (final s in options)
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(s),
            child: Text(WorkshopOrdersUtils.statusLabel(s)),
          ),
      ],
    ),
  );

  if (selected != null && context.mounted) {
    await updateWorkshopOrderStatus(
      context: context,
      order: order,
      nextStatus: selected,
      branchId: branchId,
      onSuccess: onSuccess,
    );
  }
}
