import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/modules/admin_workshop/logic/workshop_orders_types.dart';
import 'package:vanessa3/modules/admin_workshop/logic/workshop_orders_utils.dart';
import 'package:vanessa3/modules/admin_workshop/widgets/workshop_orders_actions.dart';
import 'package:vanessa3/modules/admin_workshop/widgets/workshop_orders_data_table.dart';
import 'package:vanessa3/modules/admin_workshop/widgets/workshop_orders_status_dialog.dart';
import 'package:vanessa3/modules/admin_workshop/widgets/workshop_orders_summary_card.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/widgets/workshop_cost_breakdown_sheet.dart';

export 'package:vanessa3/modules/admin_workshop/logic/workshop_orders_types.dart';

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
      final branch = userState.branch.trim();
      if (branch.isEmpty) {
        setState(() {
          _error =
              'Cabang belum dipilih. Buka profil / pilih cabang lalu coba lagi.';
          _isLoading = false;
        });
        return;
      }

      final isQueueMode =
          widget.viewMode != WorkshopOrdersViewMode.inProgress;
      final query = <String, String>{'branch_id': branch};
      if (_selectedStatus != 'all') {
        query['status'] = _selectedStatus;
      }
      query['scope'] = isQueueMode ? 'all' : _scope;
      if (isQueueMode) {
        query['queue_mode'] = 'antrian';
      }
      if (isQueueMode &&
          (_selectedStatus == 'all' || _selectedStatus == 'pending')) {
        query['unassigned_only'] = '1';
      }
      final response = await ApiClient.get('/workshop-orders', query: query);

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
            detail = (decoded['error'] ??
                    decoded['details'] ??
                    decoded['message'])
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

  int get _inProgressCount => _workshopOrders
      .where(
        (o) => WorkshopOrdersUtils.isInProgressStatus(
          (o['status'] ?? '').toString(),
        ),
      )
      .length;

  void _handleOrderAction(dynamic order, String action) {
    final userState = ref.read(userStateProvider);
    switch (action) {
      case 'start_work':
        startTechnicianWork(
          context: context,
          order: order,
          sessionBlockReason: userState.workshopSessionBlockReason,
          userId: userState.userId,
          branchId: userState.branch,
          onReload: _loadWorkshopOrders,
        );
        break;
      case 'assign_technician':
        showAssignTechnicianDialog(
          context: context,
          ref: ref,
          order: order,
          branch: userState.branch.trim(),
          sessionBlockReason: userState.workshopSessionBlockReason,
          onReload: _loadWorkshopOrders,
        );
        break;
      case 'cost_breakdown':
        final oid = int.tryParse(order['order_id']?.toString() ?? '');
        if (oid == null) return;
        showWorkshopCostBreakdownSheet(
          context,
          orderId: oid,
          branchId: userState.branch,
          onSaved: _loadWorkshopOrders,
        );
        break;
      case 'update_status':
        showWorkshopStatusDialog(
          context: context,
          order: order,
          role: userState.role.trim().toLowerCase(),
          branchId: userState.branch,
          onSuccess: _loadWorkshopOrders,
        );
        break;
      case 'view_details':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Melihat detail order #${order['order_id']}')),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
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
    final role = ref.read(userStateProvider).role.trim().toLowerCase();

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
                  : WorkshopOrdersUtils.scopeSubtitle(_scope),
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
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'all', child: Text('Semua')),
                PopupMenuItem(
                  value: 'pending',
                  child: Text('Baru masuk workshop'),
                ),
                PopupMenuItem(
                  value: 'in_progress',
                  child: Text('Dalam Proses'),
                ),
                PopupMenuItem(value: 'completed', child: Text('Selesai')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(WorkshopOrdersUtils.statusLabel(_selectedStatus)),
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
                            Text(
                              _error,
                              style: const TextStyle(color: Colors.red),
                            ),
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
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: WorkshopOrdersSummaryCard(
                                    title: 'Total Order',
                                    count: _workshopOrders.length,
                                    icon: Icons.build,
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: WorkshopOrdersSummaryCard(
                                    title: 'Dalam Proses',
                                    count: _inProgressCount,
                                    icon: Icons.schedule,
                                    color: Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: _workshopOrders.isEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              WorkshopOrdersUtils
                                                  .emptyListMessage(
                                                viewMode: widget.viewMode,
                                                selectedStatus: _selectedStatus,
                                                scope: _scope,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            if (widget.viewMode !=
                                                    WorkshopOrdersViewMode
                                                        .inProgress &&
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
                                                icon: const Icon(
                                                  Icons.filter_alt_off,
                                                ),
                                                label: const Text(
                                                  'Reset filter (Antrian / Semua)',
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    )
                                  : WorkshopOrdersDataTable(
                                      orders: _workshopOrders,
                                      role: role,
                                      onAction: _handleOrderAction,
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
}
