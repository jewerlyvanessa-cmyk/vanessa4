import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/stock_request_transfer.dart';

/// Stockist di gudang: respon permintaan stok dari toko (transfer keluar pending).
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

  Future<void> _updateTransferStatus(int transferId, String status) async {
    final userState = ref.read(userStateProvider);
    final baseUrl = NetworkConfig.baseUrl;

    try {
      final resp = await http.put(
        Uri.parse('$baseUrl/transfers/$transferId'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({
          'status': status,
          'approved_by': userState.userId,
        }),
      );

      if (!mounted) return;

      if (resp.statusCode == 200) {
        await _loadTransfers();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Permintaan #$transferId: $status')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal memproses (${resp.statusCode}): ${resp.body}',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    final pendingCount = _transfers.length;

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
                          title: const Text('Menunggu tindakan gudang'),
                          subtitle: const Text(
                            'Permintaan per kategori & jenis: menyetujui hanya mengubah status '
                            '(tanpa mutasi stok otomatis). Jika permintaan berupa SKU pasti, '
                            'sistem dapat memutasi stok bila nama barang cocok di gudang.',
                          ),
                          trailing: Chip(label: Text('$pendingCount')),
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadTransfers,
                        child: _transfers.isEmpty
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
                                  for (var i = 0; i < _transfers.length; i++) {
                                    final transfer =
                                        _transfers[i] as Map<String, dynamic>;
                                    final id = int.tryParse(
                                      transfer['transfer_id'].toString(),
                                    );
                                    final status =
                                        (transfer['status'] ?? '-').toString();
                                    final toName =
                                        (transfer['to_branch_name'] ?? '-')
                                            .toString();
                                    final itemName =
                                        (transfer['item_name'] ??
                                                transfer['nama_item'] ??
                                                '-')
                                            .toString();
                                    final qty =
                                        (transfer['quantity'] ??
                                                transfer['qty'] ??
                                                '-')
                                            .toString();
                                    final notesLine = _userNotes(
                                      transfer['notes']?.toString(),
                                    );
                                    final canAct =
                                        id != null && status == 'pending';
                                    String? extra;
                                    if (status == 'completed' ||
                                        status == 'rejected') {
                                      extra = status == 'completed'
                                          ? 'Oleh: ${(transfer['approved_by_name'] ?? '-').toString()}'
                                          : 'Ditolak: ${(transfer['approved_by_name'] ?? '-').toString()}';
                                    }
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
                                            Text(
                                              '#${id ?? '-'}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(itemName),
                                                Text(
                                                  'Catatan: $notesLine',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: cs.onSurfaceVariant,
                                                  ),
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
                                          DataCell(Text(qty)),
                                          DataCell(Text(toName)),
                                          DataCell(
                                            Chip(
                                              label: Text(
                                                status,
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
                                                ? Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      IconButton(
                                                        tooltip:
                                                            'Setujui & proses stok',
                                                        icon: const Icon(
                                                          Icons.check,
                                                          color: Colors.green,
                                                        ),
                                                        onPressed: () =>
                                                            _updateTransferStatus(
                                                          id,
                                                          'completed',
                                                        ),
                                                      ),
                                                      IconButton(
                                                        tooltip: 'Tolak',
                                                        icon: const Icon(
                                                          Icons.close,
                                                          color: Colors.red,
                                                        ),
                                                        onPressed: () =>
                                                            _updateTransferStatus(
                                                          id,
                                                          'rejected',
                                                        ),
                                                      ),
                                                    ],
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
                                                dataRowMaxHeight: 88,
                                                columnSpacing: 10,
                                                horizontalMargin: 8,
                                                showCheckboxColumn: false,
                                                dividerThickness: 0.5,
                                                columns: [
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'ID',
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Item',
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Qty',
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
                                                      'Aksi',
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
