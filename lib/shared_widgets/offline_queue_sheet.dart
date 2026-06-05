import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/data/offline_queue.dart';
import 'package:vanessa3/services/offline_sync_service.dart';

/// Detail antrian offline + hapus item yang gagal sync permanen.
Future<void> showOfflineQueueSheet(BuildContext context) async {
  final items = await OfflineSyncService.listPending();
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return _OfflineQueueSheet(initialItems: items);
    },
  );
}

class _OfflineQueueSheet extends StatefulWidget {
  const _OfflineQueueSheet({required this.initialItems});

  final List<OfflineQueueItem> initialItems;

  @override
  State<_OfflineQueueSheet> createState() => _OfflineQueueSheetState();
}

class _OfflineQueueSheetState extends State<_OfflineQueueSheet> {
  late List<OfflineQueueItem> _items;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _items = List<OfflineQueueItem>.from(widget.initialItems);
  }

  Future<void> _reload() async {
    final next = await OfflineSyncService.listPending();
    if (!mounted) return;
    setState(() => _items = next);
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      await OfflineSyncService.syncPending();
      await _reload();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _remove(String id) async {
    await OfflineSyncService.removeItem(id);
    await _reload();
  }

  String _label(OfflineQueueItem item) {
    if (item.path == '/payments') return 'Pembayaran';
    if (item.path == '/orders') return 'Order';
    return item.path;
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');
    final stuck = _items
        .where((i) => i.attempts >= OfflineSyncService.maxAttempts)
        .length;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Antrian offline (${_items.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (stuck > 0) ...[
              const SizedBox(height: 8),
              Text(
                '$stuck item gagal sync setelah ${OfflineSyncService.maxAttempts} percobaan. '
                'Periksa data atau hapus dari antrian.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Antrian kosong.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final item = _items[i];
                    final isStuck =
                        item.attempts >= OfflineSyncService.maxAttempts;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _label(item),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isStuck
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      ),
                      subtitle: Text(
                        '${df.format(item.createdAt.toLocal())} · '
                        'percobaan ${item.attempts}/${OfflineSyncService.maxAttempts}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: IconButton(
                        tooltip: 'Hapus dari antrian',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _remove(item.id),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Tutup'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _items.isEmpty || _syncing ? null : _syncNow,
                  icon: _syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync, size: 18),
                  label: Text(_syncing ? 'Sync…' : 'Sync sekarang'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
