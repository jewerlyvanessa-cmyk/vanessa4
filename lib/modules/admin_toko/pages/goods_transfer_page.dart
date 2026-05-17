import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/modules/admin_toko/pages/goods_transfer_create_page.dart';
import 'package:vanessa3/shared_widgets/responsive_form_row.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

class GoodsTransferPage extends ConsumerStatefulWidget {
  const GoodsTransferPage({super.key});

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
    final primary = await http.get(
      Uri.parse('$baseUrl/branches'),
      headers: NetworkConfig.defaultHeaders,
    );
    if (primary.statusCode == 200) return primary;
    final fallback = await http.get(
      Uri.parse('$baseUrl/api/branches'),
      headers: NetworkConfig.defaultHeaders,
    );
    if (fallback.statusCode == 200) return fallback;
    return primary;
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;

      // Load transfer requests
      final transfersResponse = await http.get(
        Uri.parse('$baseUrl/transfers?branch_id=${userState.branch}'),
        headers: NetworkConfig.defaultHeaders,
      );

      final branchesResponse = await _fetchBranchesList(baseUrl);

      if (transfersResponse.statusCode == 200 && branchesResponse.statusCode == 200) {
        final transfersData = jsonDecode(transfersResponse.body);
        final branchesData = jsonDecode(branchesResponse.body);
        final filteredTransfers = (transfersData is List)
            ? transfersData.where((e) {
                if (e is! Map) return false;
                final status = (e['status'] ?? '').toString().toLowerCase();
                return status != 'completed';
              }).toList()
            : <dynamic>[];

        setState(() {
          _transferRequests = filteredTransfers;
          _branches = branchesData;
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

  /// Kode & nama: field API jika ada, atau parse "KODE - Nama" dari `item_name`.
  (String code, String name) _transferCodeAndName(Map<dynamic, dynamic> t) {
    for (final k in const ['item_code', 'kode_produk', 'product_code']) {
      final c = t[k]?.toString().trim();
      if (c != null && c.isNotEmpty) {
        final n =
            (t['item_name'] ?? t['nama_item'] ?? '-').toString().trim();
        return (c, n.isEmpty ? '-' : n);
      }
    }
    final raw = (t['item_name'] ?? t['nama_item'] ?? '-').toString().trim();
    final sep = raw.indexOf(' - ');
    if (sep > 0) {
      final a = raw.substring(0, sep).trim();
      final b = raw.substring(sep + 3).trim();
      return (a.isEmpty ? '-' : a, b.isEmpty ? '-' : b);
    }
    return ('-', raw.isEmpty ? '-' : raw);
  }

  int _transferQty(Map<dynamic, dynamic> t) {
    final q = t['quantity'] ?? t['qty'];
    if (q is int) return q;
    return int.tryParse(q?.toString() ?? '') ?? 0;
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

  void _showTransferHistoryDetail(
    Map<String, dynamic> transfer,
    String currentBranchIdStr,
  ) {
    final isIncoming = transfer['to_branch_id']?.toString() == currentBranchIdStr;
    final (code, name) = _transferCodeAndName(transfer);
    final qty = _transferQty(transfer);
    final status = transfer['status'];
    final fromBranch =
        transfer['from_branch_name']?.toString() ??
        transfer['from_branch_id']?.toString() ??
        '-';
    final toBranch =
        transfer['to_branch_name']?.toString() ??
        transfer['to_branch_id']?.toString() ??
        '-';
    final createdAt = _formatTransferDateTime(transfer['created_at']);
    final updatedAt = _formatTransferDateTime(transfer['updated_at']);
    final notes = (transfer['notes'] ?? '').toString().trim();

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
                    'Detail / Riwayat Transfer',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _detailRow('ID Transfer', '#${transfer['transfer_id'] ?? '-'}'),
                  _detailRow('Arah', isIncoming ? 'Masuk' : 'Keluar'),
                  _detailRow('Kode Barang', code),
                  _detailRow('Nama Barang', name),
                  _detailRow('Qty', '$qty'),
                  _detailRow('Dari', fromBranch),
                  _detailRow('Ke', toBranch),
                  _detailRow('Status', _transferStatusLabel(status)),
                  if (notes.isNotEmpty) _detailRow('Catatan', notes),
                  const SizedBox(height: 10),
                  Text(
                    'Riwayat',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: cs.surfaceContainerLow,
                      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dibuat: $createdAt'),
                        const SizedBox(height: 4),
                        Text('Update terakhir: $updatedAt'),
                        const SizedBox(height: 4),
                        Text(
                          'Status saat ini: ${_transferStatusLabel(status)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _transferStatusColor(status),
                          ),
                        ),
                      ],
                    ),
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
    final rows = <DataRow>[];

    for (var i = 0; i < _transferRequests.length; i++) {
      final t = _transferRequests[i] as Map<dynamic, dynamic>;
      final transfer = Map<String, dynamic>.from(t);
      final isIncoming =
          transfer['to_branch_id']?.toString() == currentBranchIdStr;
      final transferIdRaw = transfer['transfer_id'];
      final transferId = transferIdRaw is int
          ? transferIdRaw
          : int.tryParse(transferIdRaw?.toString() ?? '');
      final (code, name) = _transferCodeAndName(transfer);
      final qty = _transferQty(transfer);
      final status = transfer['status'];
      final branchLine = isIncoming
          ? 'Dari: ${transfer['from_branch_name'] ?? transfer['from_branch_id'] ?? '-'}'
          : 'Ke: ${transfer['to_branch_name'] ?? transfer['to_branch_id'] ?? '-'}';

      Widget actionsCell() {
        if (isIncoming && status == 'pending' && transferId != null) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                tooltip: 'Terima',
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: extraCompact ? 30 : 36,
                  minHeight: extraCompact ? 30 : 36,
                ),
                onPressed: () => _approveTransfer(transferId),
              ),
              IconButton(
                icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                tooltip: 'Tolak',
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: extraCompact ? 30 : 36,
                  minHeight: extraCompact ? 30 : 36,
                ),
                onPressed: () => _rejectTransfer(transferId),
              ),
            ],
          );
        }
        if (status == 'pending' && !isIncoming) {
          return Text(
            'Menunggu',
            style: TextStyle(
              fontSize: extraCompact ? 11 : 12,
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
              _showTransferHistoryDetail(transfer, currentBranchIdStr),
          color: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return cs.primary.withValues(alpha: 0.06);
            }
            return i.isOdd
                ? cs.surfaceContainerHighest.withValues(alpha: 0.35)
                : null;
          }),
          cells: [
            if (!narrow) ...[
              DataCell(
                Text(
                  '#${transfer['transfer_id'] ?? '-'}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: extraCompact ? 12 : 13,
                  ),
                ),
              ),
              DataCell(
                Text(
                  isIncoming ? 'Masuk' : 'Keluar',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: extraCompact ? 11 : 12,
                    color: isIncoming ? Colors.blue.shade800 : Colors.orange.shade800,
                  ),
                ),
              ),
            ],
            DataCell(
              Tooltip(
                message: code,
                child: Text(
                  code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: extraCompact ? 12 : 13),
                ),
              ),
            ),
            DataCell(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: narrow ? 2 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: extraCompact ? 12 : 13),
                  ),
                  if (narrow) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${isIncoming ? 'Masuk' : 'Keluar'} · ${_transferStatusLabel(status)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: extraCompact ? 9 : 10,
                        fontWeight: FontWeight.w600,
                        color: _transferStatusColor(status),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            DataCell(
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$qty',
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
                  _transferStatusLabel(status),
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
      if (!narrow) ...[
        const DataColumn(
          label: Text('#', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        const DataColumn(
          label: Text('Arah', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
      const DataColumn(
        label: Text('Kode', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      const DataColumn(
        label: Text('Nama barang', style: TextStyle(fontWeight: FontWeight.w800)),
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
      DataColumn(label: SizedBox(width: extraCompact ? 74 : (narrow ? 88 : 100))),
    ];

    return DataTable(
      headingRowColor: WidgetStateProperty.all(cs.surfaceContainerHigh),
      dataRowMinHeight: extraCompact ? 34 : (narrow ? 40 : 44),
      dataRowMaxHeight: extraCompact ? 52 : (narrow ? 60 : 64),
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
        title: const Text('Kirim / Terima Barang'),
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
        ),
      ),
    );
    if (created == true && mounted) {
      await _loadData();
    }
  }

  Future<void> _approveTransfer(int transferId) async {
    try {
      final baseUrl = NetworkConfig.baseUrl;
      final userState = ref.read(userStateProvider);

      final response = await http.put(
        Uri.parse('$baseUrl/transfers/$transferId'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({
          'status': 'completed',
          'approved_by': userState.userId,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transfer berhasil diterima')),
          );
        }
        _loadData();
      } else {
        String msg = 'Gagal menerima transfer';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map && (decoded['detail'] != null || decoded['error'] != null)) {
            msg = '${decoded['error'] ?? msg}${decoded['detail'] != null ? '\n${decoded['detail']}' : ''}';
          } else {
            msg = '$msg (${response.statusCode})';
          }
        } catch (_) {
          msg = '$msg (${response.statusCode}): ${response.body}';
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $error')),
        );
      }
    }
  }

  Future<void> _rejectTransfer(int transferId) async {
    try {
      final baseUrl = NetworkConfig.baseUrl;
      final userState = ref.read(userStateProvider);

      final response = await http.put(
        Uri.parse('$baseUrl/transfers/$transferId'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({
          'status': 'rejected',
          'approved_by': userState.userId,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transfer berhasil ditolak')),
          );
        }
        _loadData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal menolak transfer')),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $error')),
        );
      }
    }
  }
}

