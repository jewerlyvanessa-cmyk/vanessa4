import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/modules/admin_toko/pages/goods_transfer_create_page.dart';
import 'package:vanessa3/shared_widgets/responsive_form_row.dart';
import 'package:vanessa3/shared_widgets/transfer_document_receive_sheet.dart';
import 'package:vanessa3/utils/branch_types.dart';
import 'package:vanessa3/utils/inter_store_transfer_filter.dart';
import 'package:vanessa3/utils/responsive_layout.dart';
import 'package:vanessa3/utils/transfer_batch_group.dart';

/// [branchTypeScope] — `toko` | `warehouse` | `workshop` untuk transfer antar cabang sejenis.
class GoodsTransferPage extends ConsumerStatefulWidget {
  const GoodsTransferPage({
    super.key,
    this.branchTypeScope = 'toko',
  });

  final String branchTypeScope;

  @override
  ConsumerState<GoodsTransferPage> createState() => _GoodsTransferPageState();
}

class _GoodsTransferPageState extends ConsumerState<GoodsTransferPage> {
  List<dynamic> _transferRequests = [];
  List<dynamic> _branches = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<http.Response> _fetchBranchesList(String baseUrl) async {
    final q = Uri(queryParameters: {'branch_type': widget.branchTypeScope});
    final primary = await http.get(
      Uri.parse('$baseUrl/branches').replace(queryParameters: q.queryParameters),
      headers: NetworkConfig.defaultHeaders,
    );
    if (primary.statusCode == 200) return primary;
    final fallback = await http.get(
      Uri.parse('$baseUrl/api/branches').replace(queryParameters: q.queryParameters),
      headers: NetworkConfig.defaultHeaders,
    );
    if (fallback.statusCode == 200) return fallback;
    return primary;
  }

  List<Map<String, dynamic>> _parseBranchesList(dynamic branchesData) {
    if (branchesData is! List) return [];
    return filterBranchesForTypeScope(branchesData, widget.branchTypeScope);
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;

      final scope = widget.branchTypeScope;
      final transfersResponse = await http.get(
        Uri.parse(
          '$baseUrl/transfers?branch_id=${userState.branch}'
          '&branch_type_scope=${Uri.encodeQueryComponent(scope)}',
        ),
        headers: NetworkConfig.defaultHeaders,
      );

      final branchesResponse = await _fetchBranchesList(baseUrl);

      if (transfersResponse.statusCode == 200 && branchesResponse.statusCode == 200) {
        final transfersData = jsonDecode(transfersResponse.body);
        final branchesData = jsonDecode(branchesResponse.body);
        final scopedBranches = _parseBranchesList(branchesData);
        final scopedIds = branchIdsForTypeScope(scopedBranches);

        var filteredTransfers = (transfersData is List)
            ? filterTransfersForBranchTypeScope(
                transfersData,
                scope,
                scopedIds,
              )
            : <Map<String, dynamic>>[];

        filteredTransfers = filteredTransfers
            .where(
              (e) =>
                  (e['status'] ?? '').toString().toLowerCase() != 'completed',
            )
            .toList();

        setState(() {
          _transferRequests = filteredTransfers;
          _branches = scopedBranches;
          _isLoading = false;
        });
      } else {
        final transfersHint = transfersResponse.statusCode == 200
            ? 'OK'
            : '${transfersResponse.statusCode} ${transfersResponse.body}';
        final branchesHint = branchesResponse.statusCode == 200
            ? 'OK'
            : '${branchesResponse.statusCode} ${branchesResponse.body}';
        setState(() {
          _error = 'Gagal memuat data.\ntransfers: $transfersHint\nbranches: $branchesHint';
          _isLoading = false;
        });
      }
    } catch (error) {
      setState(() {
        _error = 'Error: $error';
        _isLoading = false;
      });
    }
  }

  String _transferStatusLabel(dynamic s) {
    switch ((s ?? '').toString().toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'completed':
        return 'Selesai';
      case 'rejected':
        return 'Ditolak';
      default:
        return (s ?? '-').toString();
    }
  }

  Color _transferStatusColor(dynamic s) {
    switch ((s ?? '').toString().toLowerCase()) {
      case 'completed':
        return Colors.green.shade700;
      case 'pending':
        return Colors.orange.shade800;
      case 'rejected':
        return Colors.red.shade700;
      default:
        return Colors.grey;
    }
  }

  String _formatTransferDateTime(dynamic raw) {
    if (raw == null) return '-';
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return raw.toString();
    final d = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _openReceiveSheet(
    TransferCreationBatch batch,
    String currentBranchIdStr,
  ) async {
    final userState = ref.read(userStateProvider);
    final approvedBy = int.tryParse(userState.userId.toString()) ?? 0;
    await showTransferDocumentReceiveSheet(
      context: context,
      batch: batch,
      isIncoming: batch.isIncomingForBranch(currentBranchIdStr),
      approvedBy: approvedBy,
      onCompleted: _loadData,
    );
  }

  void _showTransferHistoryDetail(
    TransferCreationBatch batch,
    String currentBranchIdStr,
  ) {
    final isIncoming = batch.isIncomingForBranch(currentBranchIdStr);
    final status = batch.batchStatus;
    final createdAt = batch.createdAt == null
        ? '-'
        : _formatTransferDateTime(batch.createdAt!.toIso8601String());
    final notes = batch.notes;
    final kurir = batch.courier;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Detail dokumen transfer',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _detailRow('Dokumen', batch.idsLabel),
                  _detailRow('Arah', isIncoming ? 'Masuk' : 'Keluar'),
                  _detailRow('Dari', batch.fromBranchName),
                  _detailRow('Ke', batch.toBranchName),
                  if (kurir != '-') _detailRow('Kurir', kurir),
                  _detailRow('Status', _transferStatusLabel(status)),
                  if (notes.isNotEmpty) _detailRow('Catatan', notes),
                  const SizedBox(height: 8),
                  Text(
                    'Barang (${batch.lineCount} item)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  for (final line in batch.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '• ${(line['item_name'] ?? '-')} × ${line['quantity'] ?? '-'} '
                        '(#${line['transfer_id'] ?? '-'}) · ${_transferStatusLabel(line['status'])}',
                      ),
                    ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: cs.surfaceContainerLow,
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text('Dibuat: $createdAt'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }

  Widget _buildTransferDataTable(
    BuildContext context,
    bool narrow,
    String currentBranchIdStr,
  ) {
    final cs = Theme.of(context).colorScheme;
    final extraCompact = narrow && MediaQuery.sizeOf(context).width < 420;
    final batches = groupTransfersByCreationBatch(_transferRequests);
    final dateFmt = DateFormat('dd/MM/yy HH:mm', 'id_ID');
    final rows = <DataRow>[];

    for (var i = 0; i < batches.length; i++) {
      final batch = batches[i];
      final isIncoming = batch.isIncomingForBranch(currentBranchIdStr);
      final status = batch.batchStatus;
      final branchLine = isIncoming
          ? 'Dari: ${batch.fromBranchName}'
          : 'Ke: ${batch.toBranchName}';
      final created = batch.createdAt;
      final dateLabel =
          created == null ? '' : dateFmt.format(created);

      Widget actionsCell() {
        if (isIncoming && batch.pendingCount > 0) {
          return FilledButton.tonalIcon(
            onPressed: () => _openReceiveSheet(batch, currentBranchIdStr),
            icon: const Icon(Icons.playlist_add_check, size: 18),
            label: Text(
              extraCompact ? 'Cek' : 'Cek & terima',
              style: TextStyle(fontSize: extraCompact ? 11 : 12),
            ),
          );
        }
        if (batch.pendingCount > 0 && !isIncoming) {
          return Text(
            'Menunggu penerima',
            style: TextStyle(
              fontSize: extraCompact ? 10 : 11,
              fontWeight: FontWeight.w600,
              color: Colors.orange.shade800,
            ),
          );
        }
        return const SizedBox.shrink();
      }

      rows.add(
        DataRow(
          onSelectChanged: (_) =>
              _showTransferHistoryDetail(batch, currentBranchIdStr),
          color: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return cs.primary.withValues(alpha: 0.06);
            }
            return i.isOdd
                ? cs.surfaceContainerHighest.withValues(alpha: 0.35)
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
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: extraCompact ? 11 : 13,
                    ),
                  ),
                  if (!narrow && dateLabel.isNotEmpty)
                    Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            DataCell(
              Text(
                isIncoming ? 'Masuk' : 'Keluar',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: extraCompact ? 11 : 12,
                  color: isIncoming
                      ? Colors.blue.shade800
                      : Colors.orange.shade800,
                ),
              ),
            ),
            DataCell(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final row in batch.itemRows)
                    Text(
                      '${row.itemName} × ${row.qty}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: extraCompact ? 11 : 12),
                    ),
                ],
              ),
            ),
            DataCell(
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${batch.totalQty}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: extraCompact ? 12 : 13,
                  ),
                ),
              ),
            ),
            if (!narrow) ...[
              DataCell(
                Text(
                  branchLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
              DataCell(
                Text(
                  status == 'mixed' ? 'Beragam' : _transferStatusLabel(status),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: _transferStatusColor(status),
                  ),
                ),
              ),
            ],
            DataCell(actionsCell()),
          ],
        ),
      );
    }

    final columns = <DataColumn>[
      const DataColumn(
        label: Text('Dokumen', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      const DataColumn(
        label: Text('Arah', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      const DataColumn(
        label: Text('Barang', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      const DataColumn(
        numeric: true,
        label: Text('Qty', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      if (!narrow) ...[
        const DataColumn(
          label: Text('Cabang', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        const DataColumn(
          label: Text('Status', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
      DataColumn(
        label: SizedBox(width: extraCompact ? 88 : (narrow ? 100 : 120)),
      ),
    ];

    return DataTable(
      headingRowColor: WidgetStateProperty.all(cs.surfaceContainerHigh),
      dataRowMinHeight: extraCompact ? 40 : (narrow ? 48 : 52),
      dataRowMaxHeight: 120,
      columnSpacing: extraCompact ? 6 : (narrow ? 8 : 14),
      horizontalMargin: extraCompact ? 6 : (narrow ? 8 : 12),
      showCheckboxColumn: false,
      dividerThickness: 0.5,
      columns: columns,
      rows: rows,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentBranchId = ref.read(userStateProvider).branch;
    final currentBranchIdStr = currentBranchId.toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(goodsTransferPageTitle(widget.branchTypeScope)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _openCreateTransfer,
            tooltip: 'Kirim Barang',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('Coba Lagi'),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: ResponsiveLayout.pagePadding(context)
                          .copyWith(bottom: 0),
                      child: ResponsiveMetricRow(
                        children: [
                          _buildSummaryCard(
                            'Permintaan Masuk',
                            _transferRequests
                                .where((t) =>
                                    t['to_branch_id']?.toString() ==
                                        currentBranchIdStr &&
                                    t['status'] == 'pending')
                                .length,
                            Icons.arrow_downward,
                            Colors.blue,
                          ),
                          _buildSummaryCard(
                            'Permintaan Keluar',
                            _transferRequests
                                .where((t) =>
                                    t['from_branch_id']?.toString() ==
                                        currentBranchIdStr &&
                                    t['status'] == 'pending')
                                .length,
                            Icons.arrow_upward,
                            Colors.orange,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                      child: Text(
                        'Daftar Transfer',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    Expanded(
                      child: _transferRequests.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Text('Belum ada permintaan transfer'),
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final narrow = constraints.maxWidth < 600;
                                final minW = narrow
                                    ? constraints.maxWidth
                                    : 920.0;
                                return Scrollbar(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.vertical,
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minWidth: minW > constraints.maxWidth
                                              ? minW
                                              : constraints.maxWidth,
                                        ),
                                        child: _buildTransferDataTable(
                                          context,
                                          narrow,
                                          currentBranchIdStr,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateTransfer,
        tooltip: 'Kirim Barang Baru',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSummaryCard(String title, int count, IconData icon, Color color) {
    final screenW = MediaQuery.sizeOf(context).width;
    final narrow = screenW < 600;
    final extraCompact = screenW < 420;
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: extraCompact ? 8 : (narrow ? 9 : 10),
          horizontal: extraCompact ? 8 : 10,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: extraCompact ? 30 : 34,
              height: extraCompact ? 30 : 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(
                icon,
                color: color,
                size: extraCompact ? 18 : 20,
              ),
            ),
            SizedBox(width: extraCompact ? 8 : 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: extraCompact ? 11 : 12,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: extraCompact ? 6 : 10),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: extraCompact ? 18 : (narrow ? 20 : 22),
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCreateTransfer() async {
    if (_branches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daftar cabang belum dimuat')),
      );
      return;
    }
    final fromBranchId = ref.read(userStateProvider).branch;
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => GoodsTransferCreatePage(
          branches: _branches,
          fromBranchId: fromBranchId,
          branchTypeScope: widget.branchTypeScope,
        ),
      ),
    );
    if (created == true && mounted) {
      await _loadData();
    }
  }

}

