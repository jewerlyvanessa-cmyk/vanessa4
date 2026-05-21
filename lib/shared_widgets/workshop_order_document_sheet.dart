import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/utils/order_status_ui.dart';
import 'package:vanessa3/utils/surat_jalan_workshop_print.dart';
import 'package:vanessa3/utils/workshop_order_batch_api.dart';
import 'package:vanessa3/utils/workshop_order_batch_group.dart';

/// Jenis aksi batch pada dokumen order workshop (tingkat 1 — UI saja).
enum WorkshopDocumentActionKind {
  /// Workshop setuju order masuk (`sent-to-workshop`).
  approveIncoming,

  /// Admin toko konfirmasi terima fisik dari workshop.
  confirmStoreReceipt,

  /// Admin toko kirim ke workshop (`awaiting_warehouse`).
  sendToWorkshop,

  /// Workshop kirim balik ke toko (`ready_for_pickup`).
  returnToStore,
}

Future<bool> showWorkshopOrderDocumentSheet({
  required BuildContext context,
  required WorkshopOrderDocumentBatch batch,
  required WorkshopDocumentActionKind actionKind,
  required int branchId,
  required String branchIdStr,
  required Future<void> Function() onCompleted,
  String? extraSubtitle,
  WorkshopSuratJalanBranches? suratJalanBranches,
}) async {
  final pending = _pendingLinesForAction(batch, actionKind);
  if (pending.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tidak ada order yang bisa diproses')),
    );
    return false;
  }

  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _WorkshopOrderDocumentSheetBody(
      batch: batch,
      actionKind: actionKind,
      branchId: branchId,
      branchIdStr: branchIdStr,
      pendingLines: pending,
      extraSubtitle: extraSubtitle,
      suratJalanBranches: suratJalanBranches,
    ),
  );

  if (changed == true) {
    await onCompleted();
  }
  return changed == true;
}

List<Map<String, dynamic>> _pendingLinesForAction(
  WorkshopOrderDocumentBatch batch,
  WorkshopDocumentActionKind kind,
) {
  switch (kind) {
    case WorkshopDocumentActionKind.approveIncoming:
      return batch.linesWhereStatus('awaiting_warehouse');
    case WorkshopDocumentActionKind.confirmStoreReceipt:
      return batch.linesWhereStatus('ready_for_pickup');
    case WorkshopDocumentActionKind.sendToWorkshop:
      return batch.linesMatching((o) {
        final st = transferLineStatusLike(o);
        return st == 'pending' || st == 'confirmed';
      });
    case WorkshopDocumentActionKind.returnToStore:
      return batch.linesWhereStatus('done_workshop');
  }
}

class _WorkshopOrderDocumentSheetBody extends StatefulWidget {
  const _WorkshopOrderDocumentSheetBody({
    required this.batch,
    required this.actionKind,
    required this.branchId,
    required this.branchIdStr,
    required this.pendingLines,
    this.extraSubtitle,
    this.suratJalanBranches,
  });

  final WorkshopOrderDocumentBatch batch;
  final WorkshopDocumentActionKind actionKind;
  final int branchId;
  final String branchIdStr;
  final List<Map<String, dynamic>> pendingLines;
  final String? extraSubtitle;
  final WorkshopSuratJalanBranches? suratJalanBranches;

  @override
  State<_WorkshopOrderDocumentSheetBody> createState() =>
      _WorkshopOrderDocumentSheetBodyState();
}

class _WorkshopOrderDocumentSheetBodyState
    extends State<_WorkshopOrderDocumentSheetBody> {
  late final Set<int> _selected = {
    for (final line in widget.pendingLines)
      if (orderIdFromLine(line) != null) orderIdFromLine(line)!,
  };
  bool _submitting = false;

  bool get _canPrintSuratJalan =>
      widget.actionKind == WorkshopDocumentActionKind.sendToWorkshop &&
      widget.suratJalanBranches != null;

  List<Map<String, dynamic>> _selectedLines() {
    return widget.batch.lines
        .where((o) {
          final id = orderIdFromLine(o);
          return id != null && _selected.contains(id);
        })
        .toList();
  }

  Future<void> _printSuratJalanSelected() async {
    final branches = widget.suratJalanBranches;
    if (branches == null || _selected.isEmpty) return;
    await printSuratJalanWorkshopOrders(
      context,
      orders: _selectedLines(),
      branches: branches,
    );
  }

  ({String primary, String? secondary}) _actionLabels() {
    switch (widget.actionKind) {
      case WorkshopDocumentActionKind.approveIncoming:
        return (primary: 'Setujui order tercentang', secondary: null);
      case WorkshopDocumentActionKind.confirmStoreReceipt:
        return (primary: 'Terima order tercentang', secondary: null);
      case WorkshopDocumentActionKind.sendToWorkshop:
        return (primary: 'Kirim ke workshop tercentang', secondary: null);
      case WorkshopDocumentActionKind.returnToStore:
        return (
          primary: 'Kirim ke toko tercentang',
          secondary: 'Siap diambil di toko',
        );
    }
  }

  Future<void> _apply() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Centang minimal satu order')),
      );
      return;
    }

    setState(() => _submitting = true);
    WorkshopOrderBatchResult result;
    switch (widget.actionKind) {
      case WorkshopDocumentActionKind.confirmStoreReceipt:
        result = await confirmWorkshopStoreReceiptBatch(
          orderIds: _selected,
          branchId: widget.branchIdStr,
        );
        break;
      case WorkshopDocumentActionKind.approveIncoming:
        result = await putWorkshopOrderStatuses(
          orderIds: _selected,
          status: 'sent-to-workshop',
          branchId: widget.branchId,
        );
        break;
      case WorkshopDocumentActionKind.sendToWorkshop:
        result = await putWorkshopOrderStatuses(
          orderIds: _selected,
          status: 'awaiting_warehouse',
          branchId: widget.branchId,
        );
        break;
      case WorkshopDocumentActionKind.returnToStore:
        result = await putWorkshopOrderStatuses(
          orderIds: _selected,
          status: 'ready_for_pickup',
          branchId: widget.branchId,
        );
        break;
    }

    if (!mounted) return;
    setState(() => _submitting = false);

    if (result.allOk) {
      if (!mounted) return;
      if (_canPrintSuratJalan && widget.suratJalanBranches != null) {
        await printSuratJalanWorkshopOrders(
          context,
          orders: _selectedLines(),
          branches: widget.suratJalanBranches!,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.okCount} order berhasil diproses')),
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
          '${result.okCount} berhasil, ${result.failed.length} gagal.\n$failMsg',
        ),
        duration: const Duration(seconds: 5),
      ),
    );
    if (result.okCount > 0) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labels = _actionLabels();
    final created = widget.batch.documentTime;
    final dateLabel = created == null
        ? ''
        : DateFormat('dd/MM/yyyy HH:mm', 'id_ID').format(created);
    final maxH = MediaQuery.sizeOf(context).height * 0.82;
    final pendingIds = widget.pendingLines.map(orderIdFromLine).whereType<int>().toSet();

    return SizedBox(
      height: maxH,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.batch.flowLabel,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              'Dokumen ${widget.batch.idsLabel}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (dateLabel.isNotEmpty)
              Text(
                dateLabel,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            if (widget.extraSubtitle != null &&
                widget.extraSubtitle!.trim().isNotEmpty)
              Text(
                widget.extraSubtitle!,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            const SizedBox(height: 8),
            Text(
              'Centang order yang sudah dicek, lalu proses sekaligus.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  for (final line in widget.batch.lines)
                    _lineTile(line, pendingIds, cs),
                ],
              ),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () {
                          setState(() {
                            _selected
                              ..clear()
                              ..addAll(pendingIds);
                          });
                        },
                  child: const Text('Pilih semua'),
                ),
                TextButton(
                  onPressed: _submitting ? null : () => setState(_selected.clear),
                  child: const Text('Hapus pilihan'),
                ),
              ],
            ),
            if (_submitting) const LinearProgressIndicator(),
            if (_canPrintSuratJalan) ...[
              OutlinedButton.icon(
                onPressed: _submitting || _selected.isEmpty
                    ? null
                    : _printSuratJalanSelected,
                icon: const Icon(Icons.print_outlined),
                label: Text('Cetak surat jalan (${_selected.length})'),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: _submitting ? null : _apply,
              icon: const Icon(Icons.playlist_add_check),
              label: Text('${labels.primary} (${_selected.length})'),
            ),
            if (labels.secondary != null) ...[
              const SizedBox(height: 4),
              Text(
                labels.secondary!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
            TextButton(
              onPressed: _submitting ? null : () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineTile(
    Map<String, dynamic> line,
    Set<int> pendingIds,
    ColorScheme cs,
  ) {
    final id = orderIdFromLine(line);
    final status = transferLineStatusLike(line);
    final item = (line['item_name'] ?? line['nama_item'] ?? '—').toString();
    final cust = (line['customer_name'] ?? '—').toString();
    final isPending = id != null && pendingIds.contains(id);

    if (isPending) {
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
        title: Text(item),
        subtitle: Text('$cust · ${OrderStatusUi.label(status)}'),
        secondary: Text('#$id', style: const TextStyle(fontSize: 11)),
        controlAffinity: ListTileControlAffinity.leading,
      );
    }

    return ListTile(
      leading: Icon(
        Icons.check_circle_outline,
        color: cs.primary.withValues(alpha: 0.5),
        size: 22,
      ),
      title: Text(item),
      subtitle: Text('$cust · ${OrderStatusUi.label(status)}'),
      trailing: Text('#${id ?? '-'}', style: const TextStyle(fontSize: 11)),
    );
  }
}

/// Tabel ringkas dokumen order workshop (mirip daftar transfer).
Widget workshopOrderDocumentDataTable({
  required BuildContext context,
  required List<WorkshopOrderDocumentBatch> batches,
  required void Function(WorkshopOrderDocumentBatch batch) onOpenDocument,
  required bool Function(WorkshopOrderDocumentBatch batch) showAction,
  required String actionLabel,
  double minWidth = 880,
}) {
  final cs = Theme.of(context).colorScheme;
  final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');
  final rows = <DataRow>[];

  for (var i = 0; i < batches.length; i++) {
    final batch = batches[i];
    final created = batch.documentTime;
    final dateLabel = created == null ? '' : dateFmt.format(created);

    rows.add(
      DataRow(
        color: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.hovered)) {
            return cs.primary.withValues(alpha: 0.06);
          }
          return i.isOdd
              ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
              : null;
        }),
        cells: [
          DataCell(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  batch.idsLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (dateLabel.isNotEmpty)
                  Text(
                    dateLabel,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                Text(
                  '${batch.lineCount} order',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          DataCell(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in batch.orderRows)
                  Text(
                    row.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
          DataCell(
            showAction(batch)
                ? FilledButton.tonalIcon(
                    onPressed: () => onOpenDocument(batch),
                    icon: const Icon(Icons.playlist_add_check, size: 20),
                    label: Text(actionLabel),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  return Material(
    elevation: 0,
    color: cs.surfaceContainerLow.withValues(alpha: 0.65),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: SingleChildScrollView(
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(cs.surfaceContainerHigh),
              dataRowMinHeight: 48,
              dataRowMaxHeight: 120,
              columnSpacing: 10,
              horizontalMargin: 8,
              showCheckboxColumn: false,
              columns: const [
                DataColumn(label: Text('Dokumen')),
                DataColumn(label: Text('Order')),
                DataColumn(label: Text('Aksi')),
              ],
              rows: rows,
            ),
          ),
        ),
      ),
    ),
  );
}
