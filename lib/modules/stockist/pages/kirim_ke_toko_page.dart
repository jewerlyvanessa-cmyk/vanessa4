import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/modules/stockist/pages/kirim_ke_toko_create_page.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/surat_jalan_print.dart';
import 'package:vanessa3/utils/transfer_batch_group.dart';

class KirimKeTokoPage extends ConsumerStatefulWidget {
  const KirimKeTokoPage({super.key});

  @override
  ConsumerState<KirimKeTokoPage> createState() => _KirimKeTokoPageState();
}

class _KirimKeTokoPageState extends ConsumerState<KirimKeTokoPage> {
  List<dynamic> _transfers = [];
  List<dynamic> _branches = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  List<TransferCreationBatch> get _batches =>
      groupTransfersByCreationBatch(_transfers);

  List<dynamic> _decodeJsonList(http.Response resp) {
    final decoded = jsonDecode(resp.body);
    if (decoded is! List) return <dynamic>[];
    return decoded;
  }

  Future<http.Response> _fetchBranchesList() async {
    return ApiClient.get('/branches');
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);

      final transfersResp = await ApiClient.get(
        '/transfers',
        query: {
          'branch_id': userState.branch,
          'type': 'outgoing',
        },
      );
      final branchesResp = await _fetchBranchesList();

      if (transfersResp.statusCode != 200) {
        setState(() {
          _error =
              'Gagal memuat transfer (${transfersResp.statusCode}). Cabang: ${branchesResp.statusCode}.';
          _isLoading = false;
        });
        return;
      }
      if (branchesResp.statusCode != 200) {
        setState(() {
          _error =
              'Gagal memuat daftar cabang (${branchesResp.statusCode}). Transfer: ${transfersResp.statusCode}.';
          _isLoading = false;
        });
        return;
      }

      final transfersData = jsonDecode(transfersResp.body);
      final branchesList = _decodeJsonList(branchesResp);
      setState(() {
        _transfers = (transfersData is List) ? transfersData : <dynamic>[];
        _branches = branchesList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  String? _fromBranchNameForBatch(TransferCreationBatch batch) {
    final userState = ref.read(userStateProvider);
    final id = batch.fromBranchId.isNotEmpty
        ? batch.fromBranchId
        : userState.branch.toString();
    for (final b in userState.branches) {
      if (b['branch_id']?.toString() == id) {
        final n = b['name']?.toString().trim();
        if (n != null && n.isNotEmpty) return n;
      }
    }
    for (final b in _branches) {
      if (b is! Map) continue;
      if (b['branch_id']?.toString() == id) {
        final n = b['name']?.toString().trim();
        if (n != null && n.isNotEmpty) return n;
      }
    }
    return id.isEmpty ? null : 'Cabang $id';
  }

  Future<void> _reprintSuratJalan(TransferCreationBatch batch) async {
    final userState = ref.read(userStateProvider);
    final fromId = batch.fromBranchId.isNotEmpty
        ? batch.fromBranchId
        : userState.branch.toString().trim();
    final courier = batch.courier == '-' ? '' : batch.courier;

    await printSuratJalanTransfers(
      context,
      transfers: batch.lines,
      fromBranchName: _fromBranchNameForBatch(batch) ?? 'Cabang $fromId',
      toBranchName: batch.toBranchName,
      fromBranchIdForLogo: fromId,
      courier: courier,
      notes: batch.notes,
    );
  }

  Future<void> _openCreateTransfer() async {
    if (_branches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daftar cabang belum dimuat')),
      );
      return;
    }
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => KirimKeTokoCreatePage(branches: _branches),
      ),
    );
    if (created == true && mounted) {
      await _loadData();
    }
  }

  String? _batchApprovalExtra(TransferCreationBatch batch) {
    final status = batch.batchStatus;
    if (status != 'completed' && status != 'rejected') return null;
    final first = batch.lines.first;
    final who = (first['approved_by_name'] ?? '-').toString();
    return status == 'completed' ? 'Diterima: $who' : 'Ditolak: $who';
  }

  @override
  Widget build(BuildContext context) {
    final outgoingPending =
        _transfers.where((t) => t['status'] == 'pending').length;
    final batches = _batches;
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kirim ke Toko (Keluar)'),
        actions: [
          IconButton(
            tooltip: 'Kirim baru',
            onPressed: _openCreateTransfer,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadData,
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
                          onPressed: _loadData,
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
                          leading: const Icon(Icons.arrow_upward),
                          title: const Text('Menunggu diproses'),
                          trailing: Chip(label: Text('$outgoingPending')),
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadData,
                        child: batches.isEmpty
                            ? ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(top: 48),
                                children: const [
                                  Center(
                                    child: Text('Belum ada transfer keluar'),
                                  ),
                                ],
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final cs = Theme.of(context).colorScheme;
                                  final minW = math.max(
                                    constraints.maxWidth,
                                    980.0,
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
                                                  '${batch.lineCount} item',
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
                                          DataCell(Text(batch.toBranchName)),
                                          DataCell(Text(batch.courier)),
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
                                            IconButton(
                                              tooltip: 'Cetak ulang surat jalan',
                                              icon: const Icon(
                                                Icons.print_outlined,
                                                size: 22,
                                              ),
                                              onPressed: () =>
                                                  _reprintSuratJalan(batch),
                                            ),
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
                                                      'Transfer',
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
                                                    label:
                                                        dataTableColumnLabel(
                                                      'Ke',
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Kurir',
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Status',
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Cetak',
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
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateTransfer,
        tooltip: 'Kirim barang',
        child: const Icon(Icons.add),
      ),
    );
  }
}
