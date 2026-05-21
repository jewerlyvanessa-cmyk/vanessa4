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
import 'package:vanessa3/utils/stock_request_transfer.dart';
import 'package:vanessa3/utils/transfer_batch_group.dart';

/// Stockist di warehouse: respon permintaan stok dari toko (transfer keluar pending).
class PermintaanStokTokoPage extends ConsumerStatefulWidget {
  const PermintaanStokTokoPage({super.key});

  @override
  ConsumerState<PermintaanStokTokoPage> createState() =>
      _PermintaanStokTokoPageState();
}

class _PermintaanStokTokoPageState extends ConsumerState<PermintaanStokTokoPage> {
  List<dynamic> _transfers = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadTransfers();
  }

  Future<void> _loadTransfers() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;
      final branch = userState.branch.toString();

      final uri = Uri.parse('$baseUrl/transfers').replace(
        queryParameters: <String, String>{
          'branch_id': branch,
          'type': 'outgoing',
          'status': 'pending',
          'purpose': 'stock_request',
        },
      );

      final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);

      if (resp.statusCode != 200) {
        setState(() {
          _error = 'Gagal memuat permintaan (${resp.statusCode})';
          _isLoading = false;
        });
        return;
      }

      final data = jsonDecode(resp.body);
      final raw = (data is List) ? data : <dynamic>[];
      // Fallback jika backend lama tanpa filter `purpose`.
      final filtered = raw.where((e) {
        if (e is! Map) return false;
        final n = (e['notes'] ?? '').toString();
        return transferNotesIsStockRequest(n);
      }).toList();

      setState(() {
        _transfers = filtered;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  List<TransferCreationBatch> get _batches =>
      groupTransfersByCreationBatch(_transfers);

  Future<void> _openProcessSheet(TransferCreationBatch batch) async {
    final userState = ref.read(userStateProvider);
    final approvedBy = int.tryParse(userState.userId.toString()) ?? 0;
    await showTransferDocumentReceiveSheet(
      context: context,
      batch: batch,
      isIncoming: false,
      approvedBy: approvedBy,
      onCompleted: _loadTransfers,
    );
  }

  String _userNotes(String? rawNotes) {
    final n = (rawNotes ?? '').toString();
    if (!transferNotesIsStockRequest(n)) {
      final t = n.trim();
      return t.isEmpty ? '—' : t;
    }
    final lines = n
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final out = <String>[];
    for (final line in lines) {
      if (line == stockRequestTransferNotesTag ||
          line == stockRequestByCategoryTag) {
        continue;
      }
      final lower = line.toLowerCase();
      if (lower.startsWith('kategori:') || lower.startsWith('jenis:')) {
        continue;
      }
      out.add(line);
    }
    if (out.isEmpty) return '—';
    return out.join('\n');
  }

  String _batchNotesLine(TransferCreationBatch batch) =>
      _userNotes(batch.notes);

  @override
  Widget build(BuildContext context) {
    final pendingCount = _transfers.length;
    final batches = _batches;
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Permintaan stok dari toko'),
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
                          leading: const Icon(Icons.store_mall_directory),
                          title: const Text('Menunggu tindakan warehouse'),
                          subtitle: const Text(
                            'Permintaan per kategori & jenis: menyetujui hanya mengubah status '
                            '(tanpa mutasi stok otomatis). Jika permintaan berupa SKU pasti, '
                            'sistem dapat memutasi stok bila nama barang cocok di warehouse.',
                          ),
                          trailing: Chip(label: Text('$pendingCount')),
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadTransfers,
                        child: batches.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(top: 48),
                                children: const [
                                  Center(
                                    child: Text('Belum ada permintaan stok'),
                                  ),
                                ],
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final cs = Theme.of(context).colorScheme;
                                  final minW = math.max(
                                    constraints.maxWidth,
                                    920.0,
                                  );
                                  final dataRows = <DataRow>[];
                                  for (var i = 0; i < batches.length; i++) {
                                    final batch = batches[i];
                                    final status = batch.batchStatus;
                                    final notesLine = _batchNotesLine(batch);
                                    final created = batch.createdAt;
                                    final dateLabel = created == null
                                        ? ''
                                        : dateFmt.format(created);
                                    final canAct = batch.pendingCount > 0;

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
                                        }),
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
                                                Text(
                                                  'Catatan: $notesLine',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          DataCell(
                                            Text('${batch.totalQty}'),
                                          ),
                                          DataCell(Text(batch.toBranchName)),
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
                                            canAct
                                                ? FilledButton.tonalIcon(
                                                    onPressed: () =>
                                                        _openProcessSheet(
                                                      batch,
                                                    ),
                                                    icon: const Icon(
                                                      Icons
                                                          .playlist_add_check,
                                                      size: 20,
                                                    ),
                                                    label: const Text(
                                                      'Cek & proses',
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
                                                dataRowMinHeight: 52,
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
                                                      'Ke toko',
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Status',
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Proses',
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
