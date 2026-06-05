import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/providers/network_provider.dart';
import 'package:vanessa3/providers/offline_queue_provider.dart';
import 'package:vanessa3/services/offline_sync_service.dart';
import 'package:vanessa3/shared_widgets/offline_queue_sheet.dart';

/// Banner status koneksi + antrian offline menunggu sync.
class OfflineStatusBanner extends ConsumerWidget {
  const OfflineStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(networkStatusProvider);
    final queue = ref.watch(offlineQueueCountProvider);

    final backendDown = !network.isBackendReachable;
    final hasQueue = queue.pending > 0;
    final hasStuck = queue.stuck > 0;

    if (!backendDown && !hasQueue) {
      return const SizedBox.shrink();
    }

    final color = hasStuck
        ? Colors.deepOrange.shade900
        : hasQueue && backendDown
            ? Colors.orange.shade800
            : hasQueue
                ? Colors.blue.shade800
                : Colors.red.shade800;

    String message;
    if (hasStuck) {
      message =
          '${queue.stuck} transaksi gagal sync — ketuk untuk detail & hapus.';
    } else if (backendDown && hasQueue) {
      message =
          'Offline — ${queue.pending} transaksi menunggu. Akan dikirim otomatis saat server hidup.';
    } else if (backendDown) {
      message =
          'Tidak terhubung ke server. Data baca dari cache; pembayaran tunai/order bisa diantrikan.';
    } else {
      message = '${queue.pending} transaksi dalam antrian — sinkronisasi…';
    }

    return Material(
      color: color,
      child: InkWell(
        onTap: hasQueue ? () => showOfflineQueueSheet(context) : null,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  hasStuck
                      ? Icons.warning_amber_rounded
                      : backendDown
                          ? Icons.cloud_off
                          : Icons.cloud_upload,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                if (hasQueue && network.isBackendReachable)
                  TextButton(
                    onPressed: () async {
                      await OfflineSyncService.syncPending();
                      await ref.read(offlineQueueCountProvider.notifier).refresh();
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Sync'),
                  ),
                if (hasQueue)
                  IconButton(
                    tooltip: 'Detail antrian',
                    color: Colors.white,
                    iconSize: 20,
                    onPressed: () => showOfflineQueueSheet(context),
                    icon: const Icon(Icons.list_alt),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
