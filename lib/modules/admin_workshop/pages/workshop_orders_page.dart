import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/order_status_ui.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/widgets/workshop_cost_breakdown_sheet.dart';

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
  /// `all` = antrian kerja tukang (default); `cross_branch` / `local` = sempitkan by cabang asal.
  String _scope = 'all';

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
      final branch = userState.branch.trim();
      if (branch.isEmpty) {
        setState(() {
          _error = 'Cabang belum dipilih. Buka profil / pilih cabang lalu coba lagi.';
          _isLoading = false;
        });
        return;
      }

      final qStatus = _selectedStatus == 'all'
          ? ''
          : '&status=${Uri.encodeQueryComponent(_selectedStatus)}';
      final qScope = '&scope=${Uri.encodeQueryComponent(_scope)}';
      final response = await http.get(
        Uri.parse(
          '$baseUrl/workshop-orders?branch_id=${Uri.encodeQueryComponent(branch)}$qScope$qStatus',
        ),
        headers: NetworkConfig.defaultHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is! List) {
          setState(() {
            _error = 'Format respons server tidak valid (bukan daftar order).';
            _isLoading = false;
          });
          return;
        }
        setState(() {
          _workshopOrders = data;
          _isLoading = false;
        });
      } else {
        String detail = '';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            detail = (decoded['error'] ?? decoded['details'] ?? decoded['message'])
                    ?.toString() ??
                '';
          } else {
            detail = response.body;
          }
        } catch (_) {
          detail = response.body;
        }
        if (detail.length > 200) {
          detail = '${detail.substring(0, 200)}…';
        }
        setState(() {
          _error =
              'Gagal memuat order workshop (HTTP ${response.statusCode})'
              '${detail.isNotEmpty ? ': $detail' : ''}';
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

  /// PUT /workshop-orders mengizinkan alur teknisi hanya untuk role ini (bukan admin_workshop).
  bool _roleCanPutTechnicianWorkshopFlow(String role) =>
      {'superadmin', 'manajer', 'tukang'}.contains(role);

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
    final role = ref.read(userStateProvider).role.trim().toLowerCase();
    final canReceiveFromWarehouse = {
      'admin_workshop',
      'stockist',
      'superadmin',
      'manajer',
    }.contains(role);
    final canTechPut = _roleCanPutTechnicianWorkshopFlow(role);
    final options = <String>[
      if (current == 'awaiting_warehouse' && canReceiveFromWarehouse)
        'sent-to-workshop',
      if (current == 'sent-to-workshop' && canTechPut) 'in_workshop',
      if (current == 'in_workshop' && canTechPut)
        ...['repairing', 'polishing', 'done_workshop'],
      if (current == 'repairing' && canTechPut)
        ...['polishing', 'done_workshop'],
      if ((current == 'polishing' || current == 'custom_work') && canTechPut)
        'done_workshop',
      // Admin workshop: hanya terima dari gudang & kirim balik ke toko setelah selesai bengkel.
      if (current == 'done_workshop') 'ready_for_pickup',
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

    final appBarFg = Theme.of(context).appBarTheme.foregroundColor ??
        Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Antrian pekerjaan'),
            Text(
              _scopeSubtitle(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: appBarFg.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w400,
                  ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() => _selectedStatus = value);
              _loadWorkshopOrders();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('Semua')),
              const PopupMenuItem(
                value: 'pending',
                child: Text('Baru masuk workshop'),
              ),
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment<String>(
                  value: 'all',
                  label: Text('Antrian'),
                  icon: Icon(Icons.playlist_play_outlined, size: 18),
                ),
                ButtonSegment<String>(
                  value: 'cross_branch',
                  label: Text('Cabang lain'),
                  icon: Icon(Icons.swap_horiz, size: 18),
                ),
                ButtonSegment<String>(
                  value: 'local',
                  label: Text('Cabang ini'),
                  icon: Icon(Icons.home_work_outlined, size: 18),
                ),
              ],
              selected: {_scope},
              onSelectionChanged: (Set<String> next) {
                if (next.isEmpty) return;
                setState(() => _scope = next.first);
                _loadWorkshopOrders();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              'Tip: pakai «Antrian» untuk semua pekerjaan di cabang bengkel login. '
              '«Cabang ini» = cabang asal order sama dengan cabang login, atau order yang metadata-nya mengarah ke bengkel ini.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: _isLoading
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
                              _emptyListMessage(),
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

                              final role = ref
                                  .read(userStateProvider)
                                  .role
                                  .trim()
                                  .toLowerCase();
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
                                      itemBuilder: (context) => [
                                        if (role != 'admin_workshop')
                                          const PopupMenuItem(
                                            value: 'assign_technician',
                                            child: Text('Assign teknisi'),
                                          ),
                                        const PopupMenuItem(
                                          value: 'cost_breakdown',
                                          child: Text('Biaya aktual (tagihan)'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'update_status',
                                          child: Text('Update status'),
                                        ),
                                        const PopupMenuItem(
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
          ),
        ],
      ),
    );
  }

  String _scopeSubtitle() {
    switch (_scope) {
      case 'local':
        return 'Hanya order dibuat di cabang ini (sama antrian, disaring)';
      case 'cross_branch':
        return 'Hanya kiriman dari cabang lain (sama antrian, disaring)';
      default:
        return 'Sama dengan antrian kerja tukang (belum selesai bengkel)';
    }
  }

  String _emptyListMessage() {
    final filt = _selectedStatus == 'all'
        ? ''
        : ' (filter: ${_getStatusLabel(_selectedStatus)})';
    if (_scope == 'local') {
      return 'Tidak ada order antrian cabang ini$filt';
    }
    if (_scope == 'cross_branch') {
      return 'Tidak ada kiriman cabang lain di antrian$filt';
    }
    return 'Tidak ada order di antrian kerja$filt.\n'
        'Order baru dari toko: cek status Menunggu bengkel — setujui ke workshop '
        '(menu Service dari toko atau Update status pada baris berstatus tersebut).';
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
    // Keep workshop-specific statuses mapped, fallback to shared mapping.
    switch (status?.toLowerCase()) {
      case 'repairing':
      case 'polishing':
      case 'custom_work':
        return Colors.orange;
      default:
        return OrderStatusUi.color(status);
    }
  }

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'all':
        return 'Semua Status';
      case 'pending':
        return 'Baru masuk';
      case 'in_progress':
        return 'Dalam Proses';
      case 'repairing':
        return 'Dikerjakan';
      case 'polishing':
        return 'Poles/Finishing';
      case 'custom_work':
        return 'Custom Work';
      case 'ready_for_pickup':
        // Khusus Admin Workshop: lebih jelas sebagai "kirim balik ke toko".
        return 'Kirim ke Toko (Siap Diambil)';
      default:
        return OrderStatusUi.label(status);
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
      case 'cost_breakdown':
        final oid = int.tryParse(order['order_id']?.toString() ?? '');
        if (oid == null) return;
        final branch = ref.read(userStateProvider).branch;
        showWorkshopCostBreakdownSheet(
          context,
          orderId: oid,
          branchId: branch,
          onSaved: _loadWorkshopOrders,
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
