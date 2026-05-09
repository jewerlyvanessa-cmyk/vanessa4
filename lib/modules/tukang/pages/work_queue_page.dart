import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/utils/order_status_ui.dart';
import 'package:vanessa3/widgets/workshop_cost_breakdown_sheet.dart';

class WorkQueuePage extends ConsumerStatefulWidget {
  const WorkQueuePage({super.key});

  @override
  ConsumerState<WorkQueuePage> createState() => _WorkQueuePageState();
}

class _WorkQueuePageState extends ConsumerState<WorkQueuePage> {
  List<Map<String, dynamic>> _workQueue = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadWorkQueue();
  }

  Future<void> _loadWorkQueue() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final workQueue = await ApiService.getWorkQueue(
        userState.userId.toString(),
        userState.branch,
      );

      setState(() {
        _workQueue = workQueue;
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _errorMessage = 'Gagal memuat antrian kerja: $error';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Kembali',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Antrian Kerja'),
      ),
      body: Column(
        children: [
          // Work Queue List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_errorMessage, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadWorkQueue,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  )
                : _workQueue.isEmpty
                    ? const Center(
                        child: Text('Tidak ada order dalam antrian kerja'),
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final narrow = constraints.maxWidth < 560;
                            final cs = Theme.of(context).colorScheme;
const desktopW = 900.0;
                            final w = constraints.maxWidth;
                            final BoxConstraints box;
                            if (narrow) {
                              box = BoxConstraints.tightFor(width: w);
                            } else if (w >= desktopW) {
                              box = BoxConstraints.tightFor(width: desktopW);
                            } else {
                              box = const BoxConstraints(minWidth: desktopW);
                            }

                            final rows = <DataRow>[];
                            for (var i = 0; i < _workQueue.length; i++) {
                              final order = _workQueue[i];
                              final oid =
                                  (order['order_id'] ?? '—').toString();
                              final item =
                                  (order['item_name'] ?? 'N/A').toString();
                              final cust =
                                  (order['customer_name'] ?? 'N/A')
                                      .toString();
                              final type = _getOrderTypeText(
                                order['order_type']?.toString() ?? '',
                              );
                              final pri =
                                  _getPriorityText(order['priority']?.toString() ?? '');
                              final est =
                                  (order['estimated_time'] ?? '—').toString();
                              final idxColor =
                                  _getStatusColor(order['status']?.toString() ?? '');

                              final startCell = DataCell(
                                FilledButton.tonal(
                                  onPressed: () => _startWork(order),
                                  child: const Text('Mulai'),
                                ),
                              );

                              final detailCell = DataCell(
                                IconButton(
                                  tooltip: 'Detail',
                                  icon: const Icon(Icons.info_outline),
                                  onPressed: () =>
                                      _showWorkDetails(context, order),
                                ),
                              );

                              rows.add(
                                DataRow(
                                  color: WidgetStateProperty.resolveWith(
                                    (states) {
                                      if (states.contains(
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
                                  cells: narrow
                                      ? [
                                          DataCell(
                                            Row(
                                              children: [
                                                CircleAvatar(
                                                  radius: 14,
                                                  backgroundColor: idxColor,
                                                  child: Text(
                                                    '${i + 1}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Text(
                                                        '#$oid · $type',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      Text(
                                                        '$item · $cust',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: cs
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          startCell,
                                          detailCell,
                                        ]
                                      : [
                                          DataCell(
                                            CircleAvatar(
                                              backgroundColor: idxColor,
                                              child: Text(
                                                '${i + 1}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                          DataCell(Text('#$oid')),
                                          DataCell(Text(type)),
                                          DataCell(
                                            Text(
                                              item,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              cust,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          DataCell(Text(pri)),
                                          DataCell(
                                            Text(
                                              est,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          startCell,
                                          detailCell,
                                        ],
                                ),
                              );
                            }

                            return Material(
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
                                  scrollDirection: Axis.vertical,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Align(
                                      alignment: Alignment.topLeft,
                                      child: ConstrainedBox(
                                        constraints: box,
                                        child: DataTable(
                                          headingRowColor:
                                              WidgetStateProperty.all(
                                            cs.surfaceContainerHigh,
                                          ),
dataRowMinHeight: narrow ? 52 : 48,
                                          dataRowMaxHeight: narrow ? 64 : 52,
                                          columnSpacing: narrow ? 6 : 10,
                                          horizontalMargin: narrow ? 6 : 10,
                                          showCheckboxColumn: false,
                                          dividerThickness: 0.5,
                                          columns: narrow
                                              ? [
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Antrian'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Aksi'),
                                                  ),
                                                  const DataColumn(
                                                    label: SizedBox(width: 40),
                                                  ),
                                                ]
                                              : [
                                                  DataColumn(label: dataTableColumnLabel('#')),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Order'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Jenis'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Item'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Pelanggan'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Prioritas'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Estimasi'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Mulai'),
                                                  ),
                                                  const DataColumn(
                                                    label: SizedBox(width: 44),
                                                  ),
                                                ],
                                          rows: rows,
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
        onPressed: _loadWorkQueue,
        tooltip: 'Refresh Antrian',
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Color _getStatusColor(String status) {
    return OrderStatusUi.color(status);
  }

  String _getOrderTypeText(String orderType) {
    switch (orderType) {
      case 'service':
        return 'Service';
      case 'custom':
        return 'Custom Order';
      case 'buyback':
        return 'Buyback';
      default:
        return orderType;
    }
  }

  String _getPriorityText(String priority) {
    switch (priority) {
      case 'high':
        return 'Tinggi';
      case 'medium':
        return 'Sedang';
      case 'low':
        return 'Rendah';
      default:
        return 'Normal';
    }
  }

  void _startWork(Map<String, dynamic> order) async {
    try {
      await ApiService.updateWorkProgress(
        int.parse(order['order_id'].toString()),
        'repairing',
        ref.read(userStateProvider).userId.toString(),
        notes: 'Work started by technician',
        branchId: ref.read(userStateProvider).branch,
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Memulai pekerjaan Order #${order['order_id']}'),
            ),
          );
        }
      });

      // Refresh the work queue
      _loadWorkQueue();
    } catch (error) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memulai pekerjaan: $error')),
          );
        }
      });
    }
  }

  void _showWorkDetails(BuildContext context, Map<String, dynamic> order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Detail Order #${order['order_id']}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Jenis Order: ${_getOrderTypeText(order['order_type'])}'),
              const SizedBox(height: 8),
              Text('Status: ${order['status']}'),
              const SizedBox(height: 8),
              Text('Item: ${order['item_name'] ?? 'N/A'}'),
              const SizedBox(height: 8),
              Text('Material: ${order['material'] ?? 'N/A'}'),
              const SizedBox(height: 8),
              Text('Berat: ${order['weight'] ?? 'N/A'} gram'),
              const SizedBox(height: 8),
              Text('Customer: ${order['customer_name'] ?? 'N/A'}'),
              const SizedBox(height: 8),
              Text('Prioritas: ${_getPriorityText(order['priority'])}'),
              const SizedBox(height: 8),
              Text('Estimasi Waktu: ${order['estimated_time']}'),
              const SizedBox(height: 8),
              Text(
                'Catatan Teknisi: ${order['technician_notes'] ?? 'Tidak ada'}',
              ),
              const SizedBox(height: 8),
              Text(
                'Dibuat: ${order['created_at'] != null ? DateTime.parse(order['created_at']).toLocal().toString() : 'N/A'}',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
          TextButton(
            onPressed: () async {
              final oid = int.tryParse(order['order_id']?.toString() ?? '');
              if (oid == null) return;
              final branch = ref.read(userStateProvider).branch;
              Navigator.of(context).pop();
              await showWorkshopCostBreakdownSheet(
                context,
                orderId: oid,
                branchId: branch,
                onSaved: _loadWorkQueue,
              );
            },
            child: const Text('Biaya aktual'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _startWork(order);
            },
            child: const Text('Mulai Kerja'),
          ),
        ],
      ),
    );
  }
}
