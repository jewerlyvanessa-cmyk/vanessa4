import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/transfer_document_receive_sheet.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/transfer_batch_group.dart';

class DariTokoPage extends ConsumerStatefulWidget {
  const DariTokoPage({super.key});

  @override
  ConsumerState<DariTokoPage> createState() => _DariTokoPageState();
}

class _DariTokoPageState extends ConsumerState<DariTokoPage> {
  List<dynamic> _transfers = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadTransfers();
  }

  List<TransferCreationBatch> get _batches =>
      groupTransfersByCreationBatch(_transfers);

  Future<void> _loadTransfers() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;

      final resp = await http.get(
        Uri.parse(
          '$baseUrl/transfers?branch_id=${userState.branch}&type=incoming',
        ),
        headers: NetworkConfig.defaultHeaders,
      );

      if (resp.statusCode != 200) {
        setState(() {
          _error = 'Gagal memuat transfer masuk (${resp.statusCode})';
          _isLoading = false;
        });
        return;
      }

      final data = jsonDecode(resp.body);
      setState(() {
        _transfers = (data is List) ? data : <dynamic>[];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _openReceiveSheet(TransferCreationBatch batch) async {
    final userState = ref.read(userStateProvider);
    final approvedBy = int.tryParse(userState.userId.toString()) ?? 0;
    await showTransferDocumentReceiveSheet(
      context: context,
      batch: batch,
      isIncoming: true,
      approvedBy: approvedBy,
      onCompleted: _loadTransfers,
    );
  }

  String? _batchApprovalExtra(TransferCreationBatch batch) {
    final status = batch.batchStatus;
    if (status != 'completed' && status != 'rejected' && status != 'mixed') {
      return null;
    }
    final first = batch.lines.first;
    final who = (first['approved_by_name'] ?? '-').toString();
    if (batch.batchStatus == 'mixed') {
      return 'Status per item berbeda';
    }
    return status == 'completed' ? 'Diterima: $who' : 'Ditolak: $who';
  }

  @override
  Widget build(BuildContext context) {
    final incomingPending =
        _transfers.where((t) => t['status'] == 'pending').length;
    final batches = _batches;
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dari Toko (Masuk)'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadTransfers,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _loadTransfers,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Card(
                        child: ListTile(
                          leading: const Icon(Icons.arrow_downward),
                          title: const Text('Menunggu diterima'),
                          trailing: Chip(label: Text('$incomingPending')),
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadTransfers,
                        child: batches.isEmpty
                            ? ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(top: 48),
                                children: const [
                                  Center(
                                    child: Text('Belum ada transfer masuk'),
                                  ),
                                ],
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final cs = Theme.of(context).colorScheme;
                                  final minW = math.max(
                                    constraints.maxWidth,
                                    900.0,
                                  );
                                  final dataRows = <DataRow>[];
                                  for (var i = 0; i < batches.length; i++) {
                                    final batch = batches[i];
                                    final status = batch.batchStatus;
                                    final extra = _batchApprovalExtra(batch);
                                    final created = batch.createdAt;
                                    final dateLabel = created == null
                                        ? ''
                                        : dateFmt.format(created);
                                    final canReceive = batch.pendingCount > 0;

                                    dataRows.add(
                                      DataRow(
                                        color:
                                            WidgetStateProperty.resolveWith(
                                          (s) {
                                            if (s.contains(
                                              WidgetState.hovered,
                                            )) {
                                              return cs.primary
                                                  .withValues(alpha: 0.06);
                                            }
                                            return i.isOdd
                                                ? cs.surfaceContainerHighest
                                                    .withValues(alpha: 0.45)
                                                : null;
                                          },
                                        ),
                                        cells: [
                                          DataCell(
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  batch.idsLabel,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (dateLabel.isNotEmpty)
                                                  Text(
                                                    dateLabel,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: cs
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                Text(
                                                  '${batch.lineCount} item · pending ${batch.pendingCount}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          DataCell(
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                for (final row
                                                    in batch.itemRows)
                                                  Text(
                                                    '${row.itemName} × ${row.qty}',
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                if (extra != null)
                                                  Text(
                                                    extra,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: cs
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          DataCell(
                                            Text('${batch.totalQty}'),
                                          ),
                                          DataCell(
                                            Text(batch.fromBranchName),
                                          ),
                                          DataCell(
                                            Chip(
                                              label: Text(
                                                status == 'mixed'
                                                    ? 'beragam'
                                                    : status,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                          DataCell(
                                            canReceive
                                                ? FilledButton.tonalIcon(
                                                    onPressed: () =>
                                                        _openReceiveSheet(
                                                      batch,
                                                    ),
                                                    icon: const Icon(
                                                      Icons
                                                          .playlist_add_check,
                                                      size: 20,
                                                    ),
                                                    label: const Text(
                                                      'Cek & terima',
                                                    ),
                                                  )
                                                : const SizedBox.shrink(),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      0,
                                      12,
                                      12,
                                    ),
                                    child: Material(
                                      elevation: 0,
                                      color: cs.surfaceContainerLow
                                          .withValues(alpha: 0.65),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(
                                          color: cs.outlineVariant
                                              .withValues(alpha: 0.45),
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Scrollbar(
                                        child: SingleChildScrollView(
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          scrollDirection: Axis.horizontal,
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              minWidth: minW,
                                            ),
                                            child: SingleChildScrollView(
                                              physics:
                                                  const AlwaysScrollableScrollPhysics(),
                                              child: DataTable(
                                                headingRowColor:
                                                    WidgetStateProperty.all(
                                                  cs.surfaceContainerHigh,
                                                ),
                                                dataRowMinHeight: 48,
                                                dataRowMaxHeight: 120,
                                                columnSpacing: 10,
                                                horizontalMargin: 8,
                                                showCheckboxColumn: false,
                                                dividerThickness: 0.5,
                                                columns: [
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Dokumen',
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Barang',
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Qty total',
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Dari',
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Status',
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Terima',
                                                    ),
                                                  ),
                                                ],
                                                rows: dataRows,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
