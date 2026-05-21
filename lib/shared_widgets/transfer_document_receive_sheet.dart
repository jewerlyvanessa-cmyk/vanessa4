import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/utils/transfer_batch_api.dart';
import 'package:vanessa3/utils/transfer_batch_group.dart';

/// Dialog terima/tolak per item dalam satu dokumen transfer.
Future<bool> showTransferDocumentReceiveSheet({
  required BuildContext context,
  required TransferCreationBatch batch,
  required bool isIncoming,
  required int approvedBy,
  required Future<void> Function() onCompleted,
}) async {
  if (batch.pendingCount == 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tidak ada item pending pada dokumen ini')),
    );
    return false;
  }

  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _TransferDocumentReceiveSheetBody(
      batch: batch,
      isIncoming: isIncoming,
      approvedBy: approvedBy,
    ),
  );

  if (changed == true) {
    await onCompleted();
  }
  return changed == true;
}

class _TransferDocumentReceiveSheetBody extends StatefulWidget {
  const _TransferDocumentReceiveSheetBody({
    required this.batch,
    required this.isIncoming,
    required this.approvedBy,
  });

  final TransferCreationBatch batch;
  final bool isIncoming;
  final int approvedBy;

  @override
  State<_TransferDocumentReceiveSheetBody> createState() =>
      _TransferDocumentReceiveSheetBodyState();
}

class _TransferDocumentReceiveSheetBodyState
    extends State<_TransferDocumentReceiveSheetBody> {
  late final Set<int> _selected = {
    for (final line in widget.batch.pendingLines)
      if (transferIdFromLine(line) != null) transferIdFromLine(line)!,
  };
  bool _submitting = false;

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Menunggu';
      case 'completed':
        return 'Diterima';
      case 'rejected':
        return 'Ditolak';
      default:
        return status;
    }
  }

  Color _statusColor(String status, ColorScheme cs) {
    switch (status) {
      case 'completed':
        return Colors.green.shade700;
      case 'rejected':
        return Colors.red.shade700;
      case 'pending':
        return Colors.orange.shade800;
      default:
        return cs.onSurfaceVariant;
    }
  }

  Future<void> _applyStatus(String status) async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Centang minimal satu item')),
      );
      return;
    }

    setState(() => _submitting = true);
    final result = await updateTransferStatuses(
      transferIds: _selected,
      status: status,
      approvedBy: widget.approvedBy,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    final verb = status == 'completed' ? 'diterima' : 'ditolak';
    if (result.allOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.okCount} item $verb',
          ),
        ),
      );
      Navigator.pop(context, true);
      return;
    }

    final failMsg = result.failed
        .map((f) => '#${f.id}: ${f.message}')
        .take(3)
        .join('\n');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${result.okCount} item $verb, ${result.failed.length} gagal.\n$failMsg',
        ),
        duration: const Duration(seconds: 5),
      ),
    );
    if (result.okCount > 0) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final batch = widget.batch;
    final created = batch.createdAt;
    final dateLabel = created == null
        ? ''
        : DateFormat('dd/MM/yyyy HH:mm', 'id_ID').format(created);
    final counterparty = widget.isIncoming
        ? 'Dari: ${batch.fromBranchName}'
        : 'Ke: ${batch.toBranchName}';
    final kurir = batch.courier;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final maxH = MediaQuery.sizeOf(context).height * 0.82;

    return SizedBox(
      height: maxH,
      child: Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Dokumen ${batch.idsLabel}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          if (dateLabel.isNotEmpty)
            Text(
              dateLabel,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          const SizedBox(height: 4),
          Text(counterparty, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (kurir != '-')
            Text('Kurir: $kurir', style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(
            'Centang item yang sudah dicek fisik, lalu terima atau tolak.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final line in batch.lines)
                  _buildLineTile(line, cs),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: _submitting
                    ? null
                    : () {
                        setState(() {
                          _selected
                            ..clear()
                            ..addAll(
                              widget.batch.pendingLines
                                  .map(transferIdFromLine)
                                  .whereType<int>(),
                            );
                        });
                      },
                child: const Text('Pilih semua pending'),
              ),
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => setState(_selected.clear),
                child: const Text('Hapus pilihan'),
              ),
            ],
          ),
          if (_submitting) const LinearProgressIndicator(),
          const SizedBox(height: 4),
          FilledButton.icon(
            onPressed: _submitting ? null : () => _applyStatus('completed'),
            icon: const Icon(Icons.check_circle_outline),
            label: Text('Terima item tercentang (${_selected.length})'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _submitting ? null : () => _applyStatus('rejected'),
            icon: Icon(Icons.cancel_outlined, color: Colors.red.shade700),
            label: Text(
              'Tolak item tercentang (${_selected.length})',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _submitting ? null : () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildLineTile(Map<String, dynamic> line, ColorScheme cs) {
    final id = transferIdFromLine(line);
    final status = transferLineStatus(line);
    final itemName = (line['item_name'] ?? line['nama_item'] ?? '-').toString();
    final qty = (line['quantity'] ?? line['qty'] ?? '-').toString();
    final isPending = status == 'pending';

    if (isPending && id != null) {
      final checked = _selected.contains(id);
      return CheckboxListTile(
        value: checked,
        onChanged: _submitting
            ? null
            : (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(id);
                  } else {
                    _selected.remove(id);
                  }
                });
              },
        title: Text(itemName),
        subtitle: Text('Qty $qty · #$id'),
        secondary: Text(
          _statusLabel(status),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _statusColor(status, cs),
          ),
        ),
        controlAffinity: ListTileControlAffinity.leading,
      );
    }

    return ListTile(
      leading: Icon(
        status == 'completed'
            ? Icons.check_circle
            : status == 'rejected'
                ? Icons.cancel
                : Icons.hourglass_top,
        color: _statusColor(status, cs),
        size: 22,
      ),
      title: Text(itemName),
      subtitle: Text('Qty $qty · #${id ?? '-'}'),
      trailing: Text(
        _statusLabel(status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _statusColor(status, cs),
        ),
      ),
    );
  }
}
