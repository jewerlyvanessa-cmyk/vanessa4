import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/providers/workshop_dashboard_provider.dart';

Future<void> showAssignTechnicianDialog({
  required BuildContext context,
  required WidgetRef ref,
  required dynamic order,
  required String branch,
  required String? sessionBlockReason,
  required Future<void> Function() onReload,
}) async {
  if (sessionBlockReason != null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sessionBlockReason)),
      );
    }
    return;
  }
  if (branch.isEmpty) return;

  final oid = int.tryParse(order['order_id']?.toString() ?? '');
  if (oid == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID order tidak valid')),
      );
    }
    return;
  }

  List<Map<String, dynamic>> technicians = [];
  try {
    technicians = await ApiService.getTechnicians(branch);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat tukang: $e')),
      );
    }
    return;
  }

  if (!context.mounted) return;
  if (technicians.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Tidak ada tukang aktif di cabang ini. Tambahkan lewat menu Karyawan.',
        ),
      ),
    );
    return;
  }

  int? selectedTechId;
  var startImmediately = false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        return AlertDialog(
          title: Text('Assign tukang — order #$oid'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Pilih tukang yang mengerjakan order ini. '
                  'Order akan hilang dari antrian dan muncul di Update Progress tukang.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: (technicians.length * 72.0).clamp(120.0, 280.0),
                  child: ListView.builder(
                    itemCount: technicians.length,
                    itemBuilder: (context, index) {
                      final t = technicians[index];
                      final tid = int.tryParse(t['user_id']?.toString() ?? '');
                      final name = (t['username'] ?? 'Tukang').toString();
                      final activeOrders =
                          int.tryParse(t['active_orders']?.toString() ?? '0') ??
                              0;
                      final selected = tid != null && selectedTechId == tid;
                      return ListTile(
                        selected: selected,
                        leading: Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: selected
                              ? Theme.of(ctx).colorScheme.primary
                              : null,
                        ),
                        title: Text(name),
                        subtitle: Text(
                          activeOrders > 0
                              ? 'Sedang $activeOrders pekerjaan aktif'
                              : 'Belum ada pekerjaan aktif',
                        ),
                        onTap: tid == null
                            ? null
                            : () => setDialogState(() => selectedTechId = tid),
                      );
                    },
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Langsung mulai kerja'),
                  subtitle: const Text(
                    'Status langsung ke Dikerjakan / Custom Work (seperti tombol Mulai tukang)',
                  ),
                  value: startImmediately,
                  onChanged: (v) => setDialogState(() => startImmediately = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: selectedTechId != null && selectedTechId! > 0
                  ? () => Navigator.of(ctx).pop(true)
                  : null,
              child: const Text('Assign'),
            ),
          ],
        );
      },
    ),
  );

  if (confirmed != true || selectedTechId == null) return;

  try {
    await ApiService.assignWorkshopTechnician(
      orderId: oid,
      branchId: branch,
      technicianId: selectedTechId!,
      startImmediately: startImmediately,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            startImmediately
                ? 'Order #$oid ditugaskan dan mulai dikerjakan'
                : 'Order #$oid ditugaskan ke tukang',
          ),
        ),
      );
      await onReload();
      ref.read(workshopDashboardProvider.notifier).refresh();
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal assign: $e')),
      );
    }
  }
}

Future<void> startTechnicianWork({
  required BuildContext context,
  required dynamic order,
  required String? sessionBlockReason,
  required int? userId,
  required String branchId,
  required Future<void> Function() onReload,
}) async {
  try {
    if (sessionBlockReason != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sessionBlockReason)),
        );
      }
      return;
    }
    if (userId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sesi tidak valid. Silakan login ulang.')),
        );
      }
      return;
    }
    final oid = int.tryParse(order['order_id']?.toString() ?? '');
    if (oid == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ID order tidak valid')),
        );
      }
      return;
    }
    final orderType =
        (order['order_type'] ?? '').toString().trim().toLowerCase();
    final startStatus = orderType == 'custom' ? 'custom_work' : 'repairing';

    await ApiService.updateWorkProgress(
      oid,
      startStatus,
      userId.toString(),
      notes: 'Work started by technician',
      branchId: branchId,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Memulai pekerjaan order #$oid')),
      );
    }
    await onReload();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memulai pekerjaan: $e')),
      );
    }
  }
}
