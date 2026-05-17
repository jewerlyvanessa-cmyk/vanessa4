import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/order_status_ui.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/providers/workshop_dashboard_provider.dart';
import 'package:vanessa3/widgets/workshop_cost_breakdown_sheet.dart';

/// Mode tampilan antrian workshop.
enum WorkshopOrdersViewMode {
  /// Antrian pekerjaan (filter fleksibel).
  queue,

  /// Hanya pekerjaan yang sedang dikerjakan tukang di cabang workshop.
  inProgress,
}

class WorkshopOrdersPage extends ConsumerStatefulWidget {
  const WorkshopOrdersPage({
    super.key,
    this.viewMode = WorkshopOrdersViewMode.queue,
  });

  final WorkshopOrdersViewMode viewMode;

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
    if (widget.viewMode == WorkshopOrdersViewMode.inProgress) {
      _selectedStatus = 'in_progress';
      _scope = 'local';
    }
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
      final block = userState.workshopSessionBlockReason;
      if (block != null) {
        setState(() {
          _error = block;
          _isLoading = false;
        });
        return;
      }
      final baseUrl = NetworkConfig.baseUrl;
      final branch = userState.branch.trim();
      if (branch.isEmpty) {
        setState(() {
          _error = 'Cabang belum dipilih. Buka profil / pilih cabang lalu coba lagi.';
          _isLoading = false;
        });
        return;
      }

      final isQueueMode =
          widget.viewMode != WorkshopOrdersViewMode.inProgress;
      final qStatus = _selectedStatus == 'all'
          ? ''
          : '&status=${Uri.encodeQueryComponent(_selectedStatus)}';
      // Antrian pekerjaan: queue_mode=antrian → visibilitas cabang workshop + belum assign (backend).
      final qScope = isQueueMode
          ? '&scope=all'
          : '&scope=${Uri.encodeQueryComponent(_scope)}';
      final qQueue = isQueueMode ? '&queue_mode=antrian' : '';
      final qUnassigned = isQueueMode &&
              (_selectedStatus == 'all' || _selectedStatus == 'pending')
          ? '&unassigned_only=1'
          : '';
      final response = await http.get(
        Uri.parse(
          '$baseUrl/workshop-orders?branch_id=${Uri.encodeQueryComponent(branch)}$qScope$qStatus$qQueue$qUnassigned',
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
      s == 'repairing' ||
      s == 'polishing' ||
      s == 'custom_work' ||
      s == 'in_workshop';

  /// PUT /workshop-orders mengizinkan alur tukang hanya untuk role ini (bukan admin_workshop).
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
      'superadmin',
      'manajer',
    }.contains(role);
    final canTechPut = _roleCanPutTechnicianWorkshopFlow(role);
    /// Selaras `allowedByRole` di PUT `/workshop-orders/:id/status` — tukang tidak boleh `ready_for_pickup`.
    final canMarkReadyForPickup = {
      'admin_workshop',
      'admin_toko',
      'superadmin',
      'manajer',
    }.contains(role);
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
      // Workshop / toko / manajemen: kirim balik ke toko setelah selesai workshop (bukan tukang).
      if (current == 'done_workshop' && canMarkReadyForPickup)
        'ready_for_pickup',
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
        final event = (update['event'] ?? '').toString();
        if (update['type'] == 'order_update' ||
            update['type'] == 'workshop_assignment' ||
            update['type'] == 'workshop_update' ||
            event == 'workshop_approved' ||
            event == 'workshop_assigned') {
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
            Text(
              widget.viewMode == WorkshopOrdersViewMode.inProgress
                  ? 'ON PROGRESS'
                  : 'Antrian pekerjaan',
            ),
            Text(
              widget.viewMode == WorkshopOrdersViewMode.inProgress
                  ? 'Pekerjaan yang sedang dikerjakan tukang di cabang ini'
                  : _scopeSubtitle(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: appBarFg.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w400,
                  ),
            ),
          ],
        ),
        actions: [
          if (widget.viewMode != WorkshopOrdersViewMode.inProgress)
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
          if (widget.viewMode != WorkshopOrdersViewMode.inProgress)
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
              widget.viewMode == WorkshopOrdersViewMode.inProgress
                  ? 'Menampilkan order service/custom dengan status dikerjakan tukang '
                      '(perbaikan, poles, custom work, atau sudah masuk bengkel dan ditugaskan).'
                  : 'Tip: pakai «Antrian» untuk semua pekerjaan di cabang workshop login. '
                      '«Cabang ini» = cabang asal order sama dengan cabang login, atau order yang metadata-nya mengarah ke workshop ini.',
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
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _emptyListMessage(),
                                    textAlign: TextAlign.center,
                                  ),
                                  if (widget.viewMode !=
                                          WorkshopOrdersViewMode.inProgress &&
                                      (_selectedStatus != 'all' ||
                                          _scope != 'all')) ...[
                                    const SizedBox(height: 16),
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _selectedStatus = 'all';
                                          _scope = 'all';
                                        });
                                        _loadWorkshopOrders();
                                      },
                                      icon: const Icon(Icons.filter_alt_off),
                                      label: const Text(
                                        'Reset filter (Antrian / Semua)',
                                      ),
                                    ),
                                  ],
                                ],
                              ),
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
                                final item = (order['item_name'] ??
                                        order['nama_item'] ??
                                        'N/A')
                                    .toString();
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
                                        if (role == 'tukang')
                                          const PopupMenuItem(
                                            value: 'start_work',
                                            child: Text('Mulai kerja'),
                                          ),
                                        if (const {
                                          'admin_workshop',
                                          'superadmin',
                                          'manajer',
                                        }.contains(role))
                                          const PopupMenuItem(
                                            value: 'assign_technician',
                                            child: Text('Assign tukang'),
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
                                                      label: dataTableColumnLabel('Tukang'),
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
        return 'Sama dengan antrian kerja tukang (belum selesai workshop)';
    }
  }

  String _emptyListMessage() {
    if (widget.viewMode == WorkshopOrdersViewMode.inProgress) {
      return 'Tidak ada pekerjaan yang sedang dikerjakan tukang di cabang ini.';
    }
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
        'Order menunggu persetujuan workshop: buka menu TOKO → Service dari toko, '
        'lalu setujui agar masuk antrian ini.';
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
      case 'start_work':
        _startTechnicianWork(order);
        break;
      case 'assign_technician':
        _showAssignTechnicianDialog(order);
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

  Future<void> _showAssignTechnicianDialog(dynamic order) async {
    final userState = ref.read(userStateProvider);
    final block = userState.workshopSessionBlockReason;
    if (block != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(block)),
        );
      }
      return;
    }
    final branch = userState.branch.trim();
    if (branch.isEmpty) return;

    final oid = int.tryParse(order['order_id']?.toString() ?? '');
    if (oid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ID order tidak valid')),
        );
      }
      return;
    }

    List<Map<String, dynamic>> technicians = [];
    try {
      technicians = await ApiService.getTechnicians(branch);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat tukang: $e')),
        );
      }
      return;
    }

    if (!mounted) return;
    if (technicians.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada tukang aktif di cabang ini. Tambahkan lewat menu Karyawan.'),
        ),
      );
      return;
    }

    int? selectedTechId;
    var startImmediately = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text('Assign tukang — order #$oid'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Pilih tukang yang mengerjakan order ini. '
                    'Order akan hilang dari antrian dan muncul di Update Progress tukang.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: (technicians.length * 72.0).clamp(120.0, 280.0),
                    child: ListView.builder(
                      itemCount: technicians.length,
                      itemBuilder: (context, index) {
                        final t = technicians[index];
                        final tid = int.tryParse(t['user_id']?.toString() ?? '');
                        final name = (t['username'] ?? 'Tukang').toString();
                        final activeOrders =
                            int.tryParse(t['active_orders']?.toString() ?? '0') ?? 0;
                        final selected = tid != null && selectedTechId == tid;
                        return ListTile(
                          selected: selected,
                          leading: Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: selected
                                ? Theme.of(ctx).colorScheme.primary
                                : null,
                          ),
                          title: Text(name),
                          subtitle: Text(
                            activeOrders > 0
                                ? 'Sedang $activeOrders pekerjaan aktif'
                                : 'Belum ada pekerjaan aktif',
                          ),
                          onTap: tid == null
                              ? null
                              : () => setDialogState(() => selectedTechId = tid),
                        );
                      },
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Langsung mulai kerja'),
                    subtitle: const Text(
                      'Status langsung ke Dikerjakan / Custom Work (seperti tombol Mulai tukang)',
                    ),
                    value: startImmediately,
                    onChanged: (v) =>
                        setDialogState(() => startImmediately = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: selectedTechId != null && selectedTechId! > 0
                    ? () => Navigator.of(ctx).pop(true)
                    : null,
                child: const Text('Assign'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || selectedTechId == null) return;

    try {
      await ApiService.assignWorkshopTechnician(
        orderId: oid,
        branchId: branch,
        technicianId: selectedTechId!,
        startImmediately: startImmediately,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              startImmediately
                  ? 'Order #$oid ditugaskan dan mulai dikerjakan'
                  : 'Order #$oid ditugaskan ke tukang',
            ),
          ),
        );
        await _loadWorkshopOrders();
        ref.read(workshopDashboardProvider.notifier).refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal assign: $e')),
        );
      }
    }
  }

  /// Sama alur «Mulai» di antrian kerja tukang: assign progres ke tukang login.
  Future<void> _startTechnicianWork(dynamic order) async {
    try {
      final userState = ref.read(userStateProvider);
      final block = userState.workshopSessionBlockReason;
      if (block != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(block)),
          );
        }
        return;
      }
      final uid = userState.userId;
      if (uid == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sesi tidak valid. Silakan login ulang.')),
          );
        }
        return;
      }
      final oid = int.tryParse(order['order_id']?.toString() ?? '');
      if (oid == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ID order tidak valid')),
          );
        }
        return;
      }
      final orderType = (order['order_type'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final startStatus = orderType == 'custom' ? 'custom_work' : 'repairing';

      await ApiService.updateWorkProgress(
        oid,
        startStatus,
        uid.toString(),
        notes: 'Work started by technician',
        branchId: userState.branch,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Memulai pekerjaan order #$oid')),
        );
      }
      await _loadWorkshopOrders();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memulai pekerjaan: $e')),
        );
      }
    }
  }
}
