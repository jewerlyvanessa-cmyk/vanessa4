import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

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
          SnackBar(content: Text('Transfer #$transferId: $status')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal update transfer (${resp.statusCode}): ${resp.body}',
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

  @override
  Widget build(BuildContext context) {
    final incomingPending =
        _transfers.where((t) => t['status'] == 'pending').length;

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
                        child: _transfers.isEmpty
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
                                    840.0,
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
                                    final fromName =
                                        (transfer['from_branch_name'] ?? '-')
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
                                    final canAct =
                                        id != null && status == 'pending';
                                    String? extra;
                                    if (status == 'completed' ||
                                        status == 'rejected') {
                                      extra = status == 'completed'
                                          ? 'Diterima: ${(transfer['approved_by_name'] ?? '-').toString()}'
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
                                          DataCell(Text(fromName)),
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
                                                        tooltip: 'Terima',
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
dataRowMinHeight: 48,
                                                dataRowMaxHeight: 72,
                                                columnSpacing: 10,
                                                horizontalMargin: 8,
                                                showCheckboxColumn: false,
                                                dividerThickness: 0.5,
                                                columns: [
                                                  DataColumn(
                                                    label: dataTableColumnLabel('ID'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Item'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Qty'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Dari'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Status'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Aksi'),
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

