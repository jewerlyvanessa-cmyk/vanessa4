import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

class WorkshopOrdersPage extends ConsumerStatefulWidget {
  const WorkshopOrdersPage({super.key});

  @override
  ConsumerState<WorkshopOrdersPage> createState() => _WorkshopOrdersPageState();
}

class _WorkshopOrdersPageState extends ConsumerState<WorkshopOrdersPage> {
  List<dynamic> _workshopOrders = [];
  bool _isLoading = true;
  String _error = '';
  String _selectedStatus = 'all';

  @override
  void initState() {
    super.initState();
    _loadWorkshopOrders();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Note: ref.listen should be used in build method, not here
  }

  Future<void> _loadWorkshopOrders() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;

      final qStatus = _selectedStatus == 'all'
          ? ''
          : '&status=${Uri.encodeQueryComponent(_selectedStatus)}';
      final response = await http.get(
        Uri.parse('$baseUrl/workshop-orders?branch_id=${userState.branch}$qStatus'),
        headers: NetworkConfig.defaultHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _workshopOrders = data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Gagal memuat data order workshop';
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

  List<dynamic> get _filteredOrders => _workshopOrders;

  bool _isInProgressStatus(String s) =>
      s == 'repairing' || s == 'polishing' || s == 'custom_work';

  Future<void> _updateWorkshopStatus(
    dynamic order,
    String nextStatus,
  ) async {
    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;
      final oid = order['order_id']?.toString();
      if (oid == null || oid.isEmpty) return;
      final response = await http.put(
        Uri.parse('$baseUrl/workshop-orders/$oid/status'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({
          'status': nextStatus,
          'branch_id': userState.branch,
        }),
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Status order #$oid -> $nextStatus')),
          );
        }
        await _loadWorkshopOrders();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal update status: ${response.body}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error update status: $e')));
      }
    }
  }

  Future<void> _showWorkshopStatusDialog(dynamic order) async {
    final current = (order['status'] ?? '').toString().trim().toLowerCase();
    final options = <String>[
      if (current == 'sent-to-workshop') 'in_workshop',
      if (current == 'in_workshop') ...['repairing', 'polishing', 'done_workshop'],
      if (current == 'repairing') ...['polishing', 'done_workshop'],
      if (current == 'polishing' || current == 'custom_work') 'done_workshop',
    ];
    if (options.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada transisi status yang tersedia')),
        );
      }
      return;
    }
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Update status #${order['order_id']}'),
        children: [
          for (final s in options)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(s),
              child: Text(_getStatusLabel(s)),
            ),
        ],
      ),
    );
    if (selected != null) {
      await _updateWorkshopStatus(order, selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to real-time workshop order updates
    ref.listen(realTimeOrderUpdatesProvider, (previous, next) {
      next.whenData((update) {
        if (update['type'] == 'order_update' ||
            update['type'] == 'workshop_assignment' ||
            update['type'] == 'workshop_update') {
          // Refresh workshop orders when relevant updates occur
          _loadWorkshopOrders();
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Workshop'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() => _selectedStatus = value);
              _loadWorkshopOrders();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('Semua')),
              const PopupMenuItem(value: 'pending', child: Text('Pending')),
              const PopupMenuItem(
                value: 'in_progress',
                child: Text('Dalam Proses'),
              ),
              const PopupMenuItem(value: 'completed', child: Text('Selesai')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(_getStatusLabel(_selectedStatus)),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadWorkshopOrders,
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
                    onPressed: _loadWorkshopOrders,
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Summary Cards
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          'Total Order',
                          _workshopOrders.length,
                          Icons.build,
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildSummaryCard(
                          'Dalam Proses',
                          _workshopOrders
                              .where((o) => _isInProgressStatus((o['status'] ?? '').toString()))
                              .length,
                          Icons.schedule,
                          Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _filteredOrders.isEmpty
                        ? Center(
                            child: Text(
                              'Tidak ada order workshop ${_selectedStatus == 'all' ? '' : 'dengan status ${_getStatusLabel(_selectedStatus)}'}',
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 600;
                              final cs = Theme.of(context).colorScheme;
const desktopW = 960.0;
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
                              for (var i = 0; i < _filteredOrders.length; i++) {
                                final order = _filteredOrders[i];
                                final oid =
                                    (order['order_id'] ?? '—').toString();
                                final cust =
                                    (order['customer_name'] ?? 'N/A')
                                        .toString();
                                final item =
                                    (order['nama_item'] ?? 'N/A').toString();
                                final tech = (order['technician_name'] ??
                                        'Belum diassign')
                                    .toString();
                                final st = order['status'];
                                final stLabel = _getStatusLabel(st);
                                final stColor = _getStatusColor(st);
                                final menu = DataCell(
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert),
                                      tooltip: 'Tindakan',
                                      onSelected: (action) =>
                                          _handleOrderAction(order, action),
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: 'assign_technician',
                                          child: Text('Assign teknisi'),
                                        ),
                                        PopupMenuItem(
                                          value: 'update_status',
                                          child: Text('Update status'),
                                        ),
                                        PopupMenuItem(
                                          value: 'view_details',
                                          child: Text('Lihat detail'),
                                        ),
                                      ],
                                    ),
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
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    '#$oid · $cust',
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  Text(
                                                    stLabel,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: stColor,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            menu,
                                          ]
                                        : [
                                            DataCell(Text('#$oid')),
                                            DataCell(
                                              Text(
                                                cust,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                item,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                tech,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                stLabel,
                                                style: TextStyle(
                                                  color: stColor,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            menu,
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
                                            dataRowMaxHeight: narrow ? 72 : 56,
                                            columnSpacing: narrow ? 8 : 12,
                                            horizontalMargin:
                                                narrow ? 8 : 12,
                                            showCheckboxColumn: false,
                                            dividerThickness: 0.5,
                                            columns: narrow
                                                ? [
                                                    DataColumn(
                                                      label: dataTableColumnLabel('Order'),
                                                    ),
                                                    const DataColumn(
                                                      label: SizedBox(width: 44),
                                                    ),
                                                  ]
                                                : [
                                                    DataColumn(
                                                      label: dataTableColumnLabel('Order'),
                                                    ),
                                                    DataColumn(
                                                      label: dataTableColumnLabel('Pelanggan'),
                                                    ),
                                                    DataColumn(
                                                      label: dataTableColumnLabel('Item'),
                                                    ),
                                                    DataColumn(
                                                      label: dataTableColumnLabel('Teknisi'),
                                                    ),
                                                    DataColumn(
                                                      label: dataTableColumnLabel('Status'),
                                                    ),
                                                    const DataColumn(
                                                      label: SizedBox(width: 48),
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
    );
  }

  Widget _buildSummaryCard(
    String title,
    int count,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'pending':
        return Colors.grey;
      case 'sent-to-workshop':
        return Colors.blueGrey;
      case 'in_workshop':
      case 'repairing':
      case 'polishing':
      case 'custom_work':
        return Colors.orange;
      case 'done_workshop':
      case 'ready_for_pickup':
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'all':
        return 'Semua Status';
      case 'pending':
        return 'Pending';
      case 'in_progress':
        return 'Dalam Proses';
      case 'completed':
        return 'Selesai';
      case 'sent-to-workshop':
        return 'Kirim ke Workshop';
      case 'in_workshop':
        return 'Diterima Workshop';
      case 'repairing':
        return 'Dikerjakan';
      case 'polishing':
        return 'Poles/Finishing';
      case 'custom_work':
        return 'Custom Work';
      case 'done_workshop':
        return 'Siap Kirim ke Toko';
      case 'ready_for_pickup':
        return 'Siap Diambil Customer';
      case 'cancelled':
        return 'Dibatalkan';
      default:
        return status ?? 'Unknown';
    }
  }

  void _handleOrderAction(dynamic order, String action) {
    switch (action) {
      case 'assign_technician':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Assign teknisi untuk order #${order['order_id']}'),
          ),
        );
        break;
      case 'update_status':
        _showWorkshopStatusDialog(order);
        break;
      case 'view_details':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Melihat detail order #${order['order_id']}')),
        );
        break;
    }
  }
}
