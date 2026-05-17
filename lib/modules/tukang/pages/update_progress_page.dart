import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/utils/order_status_ui.dart';
import 'package:vanessa3/widgets/workshop_cost_breakdown_sheet.dart';

class UpdateProgressPage extends ConsumerStatefulWidget {
  const UpdateProgressPage({super.key});

  @override
  ConsumerState<UpdateProgressPage> createState() => _UpdateProgressPageState();
}

class _UpdateProgressPageState extends ConsumerState<UpdateProgressPage> {
  List<Map<String, dynamic>> _workQueue = [];
  bool _isLoading = true;
  String? _error;

  static const _allowedProgressStatuses = <String>{
    'in_workshop',
    'repairing',
    'polishing',
    'custom_work',
    'done_workshop',
    'cancelled',
  };

  /// Map backend statuses to dropdown values so [DropdownButtonFormField] never gets an unknown value.
  String _statusForProgressDropdown(String? raw) {
    final s = raw?.trim() ?? '';
    if (_allowedProgressStatuses.contains(s)) return s;
    switch (s.toLowerCase()) {
      case 'sent-to-workshop':
      case 'sent_to_workshop':
        return 'in_workshop';
      case 'ready_for_pickup':
      case 'completed':
        return 'done_workshop';
      default:
        return 'in_workshop';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadWorkQueue();
  }

  Future<void> _loadWorkQueue() async {
    setState(() {
      _isLoading = true;
      _error = null;
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
      final workQueue = await ApiService.getWorkQueue(
        userState.branch,
        assignedTechnicianId: userState.userId!.toString(),
      );

      setState(() {
        _workQueue = workQueue;
        _isLoading = false;
      });
    } on UnauthorizedApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _workQueue = [];
        _error = e.message;
        _isLoading = false;
      });
    } on ForbiddenApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _workQueue = [];
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _openCostEditor(Map<String, dynamic> work) async {
    final oid = int.tryParse(work['order_id']?.toString() ?? '');
    if (oid == null) return;
    final branch = ref.read(userStateProvider).branch;
    await showWorkshopCostBreakdownSheet(
      context,
      orderId: oid,
      branchId: branch,
      allowAllZeroCosts: true,
      onSaved: _loadWorkQueue,
    );
  }

  Future<bool> _updateProgress(int orderId, String status, String notes) async {
    try {
      final userState = ref.read(userStateProvider);
      final block = userState.workshopSessionBlockReason;
      if (block != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(block)),
          );
        }
        return false;
      }
      await ApiService.updateWorkProgress(
        orderId,
        status,
        userState.userId!.toString(),
        notes: notes,
        branchId: userState.branch,
      );

      await _loadWorkQueue();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Progress berhasil diperbarui')),
        );
      }
      return true;
    } on UnauthorizedApiException {
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
      return false;
    }
  }

  static double _parseCostField(String raw) {
    final t = raw.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(t) ?? 0;
  }

  Future<void> _showUpdateDialog(Map<String, dynamic> work) async {
    final oid = int.tryParse(work['order_id']?.toString() ?? '');
    if (oid == null) return;
    final branch = ref.read(userStateProvider).branch;

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => _UpdateProgressDialog(
        orderId: oid,
        branchId: branch,
        initialStatus: _statusForProgressDropdown(work['status']?.toString()),
        initialNotes: (work['notes'] ?? '').toString(),
        onSave: (status, notes, material, ongkos, lain) async {
          await ApiService.submitOrderCostBreakdown(
            orderId: oid,
            branchId: branch,
            materialCost: material,
            laborCost: ongkos,
            otherCost: lain,
            notes: notes,
          );
          return _updateProgress(oid, status, notes);
        },
      ),
    );
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
        title: const Text('Update Progress'),
      ),
      body: Column(
        children: [
          // Content Area
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Error: $_error'),
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.assignment, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Tidak ada pekerjaan yang perlu diperbarui'),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadWorkQueue,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      children: [
                        SizedBox(
                          height: math.max(
                            420.0,
                            MediaQuery.sizeOf(context).height * 0.55,
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 560;
                              final cs = Theme.of(context).colorScheme;
                              const desktopW = 920.0;
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
                                final work = _workQueue[i];
                                final st = work['status']?.toString() ?? '';
                                final stColor = _getStatusColor(st);
                                final oid =
                                    (work['order_id'] ?? '—').toString();
                                final item =
                                    (work['item_name'] ?? 'N/A').toString();
                                final itype =
                                    (work['item_type'] ?? '').toString();
                                final cust =
                                    (work['customer_name'] ?? 'N/A')
                                        .toString();
                                final stText = _getStatusText(st);
                                final notes = (work['notes'] ?? '')
                                    .toString()
                                    .trim();

                                final editCell = DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Biaya aktual',
                                        icon: const Icon(
                                          Icons.receipt_long_outlined,
                                        ),
                                        onPressed: () => _openCostEditor(work),
                                      ),
                                      IconButton(
                                        tooltip: 'Update progress',
                                        icon: const Icon(Icons.edit),
                                        onPressed: () =>
                                            _showUpdateDialog(work),
                                      ),
                                    ],
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
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  CircleAvatar(
                                                    radius: 18,
                                                    backgroundColor: stColor,
                                                    child: Icon(
                                                      _getStatusIcon(st),
                                                      color: Colors.white,
                                                      size: 18,
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
                                                          '#$oid · $item',
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                        Text(
                                                          '$cust · $stText',
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color: stColor,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            editCell,
                                          ]
                                        : [
                                            DataCell(Text('#$oid')),
                                            DataCell(
                                              Text(
                                                '$item ($itype)',
                                                maxLines: 2,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
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
                                                stText,
                                                style: TextStyle(
                                                  color: stColor,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                notes.isEmpty ? '—' : notes,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: cs.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                            editCell,
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
                                            dataRowMinHeight: narrow ? 56 : 48,
                                            dataRowMaxHeight:
                                                narrow ? 72 : 56,
                                            columnSpacing: narrow ? 6 : 10,
                                            horizontalMargin:
                                                narrow ? 6 : 10,
                                            showCheckboxColumn: false,
                                            dividerThickness: 0.5,
                                            columns: narrow
                                                ? [
                                                    DataColumn(
                                                      label: dataTableColumnLabel('Pekerjaan'),
                                                    ),
                                                    const DataColumn(
                                                      label: SizedBox(width: 100),
                                                    ),
                                                  ]
                                                : [
                                                    DataColumn(
                                                      label: dataTableColumnLabel('Order'),
                                                    ),
                                                    DataColumn(
                                                      label: dataTableColumnLabel('Item'),
                                                    ),
                                                    DataColumn(
                                                      label:
                                                          dataTableColumnLabel('Pelanggan'),
                                                    ),
                                                    DataColumn(
                                                      label: dataTableColumnLabel('Status'),
                                                    ),
                                                    DataColumn(
                                                      label: dataTableColumnLabel('Catatan'),
                                                    ),
                                                    const DataColumn(
                                                      label: SizedBox(width: 104),
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
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(String status) {
    return OrderStatusUi.label(status);
  }

  Color _getStatusColor(String status) {
    return OrderStatusUi.color(status);
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'in_workshop':
        return Icons.inventory_2_outlined;
      case 'repairing':
      case 'polishing':
      case 'custom_work':
        return Icons.engineering;
      case 'done_workshop':
        return Icons.local_shipping_outlined;
      case 'ready_for_pickup':
      case 'completed':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }
}

/// Dialog update progress + biaya — state terpisah agar dropdown/status & dispose controller benar.
class _UpdateProgressDialog extends StatefulWidget {
  const _UpdateProgressDialog({
    required this.orderId,
    required this.branchId,
    required this.initialStatus,
    required this.initialNotes,
    required this.onSave,
  });

  final int orderId;
  final String branchId;
  final String initialStatus;
  final String initialNotes;
  final Future<bool> Function(
    String status,
    String notes,
    double material,
    double ongkos,
    double lain,
  ) onSave;

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  static const _statusItems = <DropdownMenuItem<String>>[
    DropdownMenuItem(value: 'in_workshop', child: Text('Diterima Workshop')),
    DropdownMenuItem(value: 'repairing', child: Text('Dikerjakan')),
    DropdownMenuItem(value: 'polishing', child: Text('Poles/Finishing')),
    DropdownMenuItem(value: 'custom_work', child: Text('Custom Work')),
    DropdownMenuItem(
      value: 'done_workshop',
      child: Text('Selesai di Tukang (siap kirim ke toko)'),
    ),
    DropdownMenuItem(value: 'cancelled', child: Text('Dibatalkan')),
  ];

  late String _selectedStatus;
  late final TextEditingController _notesController;
  late final TextEditingController _materialCtrl;
  late final TextEditingController _ongkosCtrl;
  late final TextEditingController _lainCtrl;

  bool _loadingCosts = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.initialStatus;
    _notesController = TextEditingController(text: widget.initialNotes);
    _materialCtrl = TextEditingController();
    _ongkosCtrl = TextEditingController();
    _lainCtrl = TextEditingController();
    _loadCosts();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _materialCtrl.dispose();
    _ongkosCtrl.dispose();
    _lainCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCosts() async {
    try {
      final data = await ApiService.getOrderCostBreakdown(
        widget.orderId,
        widget.branchId,
      );
      final latest = data['latest'];
      if (latest is Map && mounted) {
        _materialCtrl.text = _costFieldText(latest['material_cost']);
        _ongkosCtrl.text = _costFieldText(latest['labor_cost']);
        _lainCtrl.text = _costFieldText(latest['other_cost']);
      }
    } catch (_) {
      // biarkan kosong (boleh 0)
    }
    if (mounted) setState(() => _loadingCosts = false);
  }

  static String _costFieldText(dynamic v) {
    final n = num.tryParse(v?.toString() ?? '') ?? 0;
    if (n == 0) return '';
    return n.toString();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final ok = await widget.onSave(
        _selectedStatus,
        _notesController.text,
        _UpdateProgressPageState._parseCostField(_materialCtrl.text),
        _UpdateProgressPageState._parseCostField(_ongkosCtrl.text),
        _UpdateProgressPageState._parseCostField(_lainCtrl.text),
      );
      if (ok && mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Update Progress · Order #${widget.orderId}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedStatus,
                  items: _statusItems,
                  onChanged: _saving
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() => _selectedStatus = v);
                        },
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_loadingCosts)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              )
            else ...[
              Text(
                'Biaya aktual (masing-masing boleh Rp 0)',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _materialCtrl,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Material',
                  prefixText: 'Rp ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ongkosCtrl,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Ongkos',
                  prefixText: 'Rp ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _lainCtrl,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Lain-lain',
                  prefixText: 'Rp ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Catatan',
                hintText: 'Catatan progress...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving || _loadingCosts ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Simpan'),
        ),
      ],
    );
  }
}
