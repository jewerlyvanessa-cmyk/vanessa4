import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

class UpdateProgressPage extends ConsumerStatefulWidget {
  const UpdateProgressPage({super.key});

  @override
  ConsumerState<UpdateProgressPage> createState() => _UpdateProgressPageState();
}

class _UpdateProgressPageState extends ConsumerState<UpdateProgressPage> {
  List<Map<String, dynamic>> _workQueue = [];
  bool _isLoading = true;
  String? _error;

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
      final workQueue = await ApiService.getWorkQueue(
        userState.userId.toString(),
        userState.branch,
      );

      setState(() {
        _workQueue = workQueue;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _updateProgress(int orderId, String status, String notes) async {
    try {
      final userState = ref.read(userStateProvider);
      await ApiService.updateWorkProgress(
        orderId,
        status,
        userState.userId.toString(),
        notes: notes,
      );

      // Reload work queue after update
      await _loadWorkQueue();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Progress berhasil diperbarui')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  void _showUpdateDialog(Map<String, dynamic> work) {
    final statusController = TextEditingController(text: work['status']);
    final notesController = TextEditingController(text: work['notes'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Progress - Order #${work['order_id']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: statusController.text,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(
                  value: 'in_workshop',
                  child: Text('Diterima Workshop'),
                ),
                DropdownMenuItem(
                  value: 'repairing',
                  child: Text('Dikerjakan'),
                ),
                DropdownMenuItem(
                  value: 'polishing',
                  child: Text('Poles/Finishing'),
                ),
                DropdownMenuItem(
                  value: 'custom_work',
                  child: Text('Custom Work'),
                ),
                DropdownMenuItem(
                  value: 'done_workshop',
                  child: Text('Selesai Tukang (Siap Kirim)'),
                ),
                DropdownMenuItem(value: 'cancelled', child: Text('Dibatalkan')),
              ],
              onChanged: (value) {
                statusController.text = value ?? '';
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Catatan',
                hintText: 'Tambahkan catatan progress...',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _updateProgress(
                work['order_id'],
                statusController.text,
                notesController.text,
              );
            },
            child: const Text('Update'),
          ),
        ],
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
                                  IconButton(
                                    tooltip: 'Update progress',
                                    icon: const Icon(Icons.edit),
                                    onPressed: () =>
                                        _showUpdateDialog(work),
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
                                                      label: SizedBox(width: 44),
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
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'in_workshop':
        return 'Diterima Workshop';
      case 'repairing':
        return 'Dikerjakan';
      case 'polishing':
        return 'Poles/Finishing';
      case 'custom_work':
        return 'Custom Work';
      case 'done_workshop':
        return 'Selesai Tukang';
      case 'ready_for_pickup':
      case 'completed':
        return 'Selesai';
      case 'cancelled':
        return 'Dibatalkan';
      default:
        return 'Unknown';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'in_workshop':
        return Colors.blueGrey;
      case 'repairing':
      case 'polishing':
      case 'custom_work':
        return Colors.blue;
      case 'done_workshop':
        return Colors.teal;
      case 'ready_for_pickup':
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
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
