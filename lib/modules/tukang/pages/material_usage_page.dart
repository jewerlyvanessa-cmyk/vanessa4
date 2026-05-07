import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

class MaterialUsagePage extends ConsumerStatefulWidget {
  const MaterialUsagePage({super.key});

  @override
  ConsumerState<MaterialUsagePage> createState() => _MaterialUsagePageState();
}

class _MaterialUsagePageState extends ConsumerState<MaterialUsagePage> {
  List<Map<String, dynamic>> _workQueue = [];
  List<Map<String, dynamic>> _materialStock = [];
  bool _isLoading = true;
  String? _error;

  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();

  Map<String, dynamic>? _selectedWork;
  Map<String, dynamic>? _selectedMaterial;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userState = ref.read(userStateProvider);

      final results = await Future.wait([
        ApiService.getWorkQueue(userState.userId.toString(), userState.branch),
        ApiService.getMaterialStock(userState.branch),
      ]);

      setState(() {
        _workQueue = results[0];
        _materialStock = results[1];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _recordMaterialUsage() async {
    if (_selectedWork == null || _selectedMaterial == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih pekerjaan dan material terlebih dahulu'),
        ),
      );
      return;
    }

    final quantity = double.tryParse(_quantityController.text);
    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan jumlah yang valid')),
      );
      return;
    }

    try {
      final userState = ref.read(userStateProvider);
      await ApiService.updateMaterialStock(
        _selectedMaterial!['item_id'],
        -quantity, // Negative for usage
        userState.userId.toString(),
        notes:
            'Digunakan untuk Order #${_selectedWork!['order_id']} - ${_notesController.text}',
      );

      // Reset form
      setState(() {
        _selectedWork = null;
        _selectedMaterial = null;
      });
      _quantityController.clear();
      _notesController.clear();

      // Reload data
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Penggunaan material berhasil dicatat')),
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

  void _showMaterialUsageDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Catat Penggunaan Material'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Work Selection
                DropdownButtonFormField<Map<String, dynamic>>(
                  initialValue: _selectedWork,
                  decoration: const InputDecoration(
                    labelText: 'Pilih Pekerjaan',
                  ),
                  items: _workQueue.map((work) {
                    return DropdownMenuItem(
                      value: work,
                      child: Text(
                        'Order #${work['order_id']} - ${work['item_name']}',
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedWork = value;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Material Selection
                DropdownButtonFormField<Map<String, dynamic>>(
                  initialValue: _selectedMaterial,
                  decoration: const InputDecoration(
                    labelText: 'Pilih Material',
                  ),
                  items: _materialStock.map((material) {
                    return DropdownMenuItem(
                      value: material,
                      child: Text(
                        '${material['item_name']} (${material['quantity']} ${material['unit'] ?? 'pcs'} tersedia)',
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedMaterial = value;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Quantity Input
                TextField(
                  controller: _quantityController,
                  decoration: InputDecoration(
                    labelText: 'Jumlah Digunakan',
                    suffixText: _selectedMaterial?['unit'] ?? 'pcs',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),

                // Notes
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (Opsional)',
                    hintText: 'Tambahkan catatan penggunaan...',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _recordMaterialUsage();
              },
              child: const Text('Catat'),
            ),
          ],
        ),
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
        title: const Text('Penggunaan Material'),
      ),
      body: Column(
        children: [
          // Quick Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ElevatedButton.icon(
              onPressed: _showMaterialUsageDialog,
              icon: const Icon(Icons.add),
              label: const Text('Catat Penggunaan Material'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),

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
                          onPressed: _loadData,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  )
                : DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        const TabBar(
                          tabs: [
                            Tab(text: 'Pekerjaan Aktif'),
                            Tab(text: 'Stok Material'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              // Active Work Tab
                              _workQueue.isEmpty
                                  ? const Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.assignment,
                                            size: 48,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(height: 16),
                                          Text('Tidak ada pekerjaan aktif'),
                                        ],
                                      ),
                                    )
                                  : RefreshIndicator(
                                      onRefresh: _loadData,
                                      child: ListView(
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
                                        padding: const EdgeInsets.all(12),
                                        children: [
                                          SizedBox(
                                            height: math.max(
                                              360.0,
                                              MediaQuery.sizeOf(context)
                                                      .height *
                                                  0.45,
                                            ),
                                            child: LayoutBuilder(
                                              builder: (context, c) {
                                                final narrow = c.maxWidth < 520;
                                                final cs = Theme.of(context)
                                                    .colorScheme;
final w = c.maxWidth;
                                                final box = narrow
                                                    ? BoxConstraints.tightFor(
                                                        width: w,
                                                      )
                                                    : (w >= 880
                                                        ? BoxConstraints
                                                            .tightFor(
                                                            width: 880,
                                                          )
                                                        : const BoxConstraints(
                                                            minWidth: 880,
                                                          ));

                                                final rows = <DataRow>[];
                                                for (var i = 0;
                                                    i < _workQueue.length;
                                                    i++) {
                                                  final work = _workQueue[i];
                                                  final st = work['status']
                                                          ?.toString() ??
                                                      '';
                                                  final stC =
                                                      _getStatusColor(st);
                                                  final oid = (work['order_id'] ??
                                                          '—')
                                                      .toString();
                                                  final item = (work['item_name'] ??
                                                          'N/A')
                                                      .toString();
                                                  final itype = (work['item_type'] ??
                                                          '')
                                                      .toString();
                                                  final cust = (work['customer_name'] ??
                                                          'N/A')
                                                      .toString();
                                                  final stT =
                                                      _getStatusText(st);
                                                  rows.add(
                                                    DataRow(
                                                      color: WidgetStateProperty
                                                          .resolveWith((s) {
                                                        if (s.contains(
                                                          WidgetState.hovered,
                                                        )) {
                                                          return cs.primary
                                                              .withValues(
                                                            alpha: 0.06,
                                                          );
                                                        }
                                                        return i.isOdd
                                                            ? cs.surfaceContainerHighest
                                                                .withValues(
                                                                alpha: 0.45,
                                                              )
                                                            : null;
                                                      }),
                                                      cells: narrow
                                                          ? [
                                                              DataCell(
                                                                Row(
                                                                  children: [
                                                                    CircleAvatar(
                                                                      radius:
                                                                          16,
                                                                      backgroundColor:
                                                                          stC,
                                                                      child: Icon(
                                                                        _getStatusIcon(
                                                                          st,
                                                                        ),
                                                                        color: Colors
                                                                            .white,
                                                                        size:
                                                                            16,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      width: 8,
                                                                    ),
                                                                    Expanded(
                                                                      child:
                                                                          Column(
                                                                        crossAxisAlignment:
                                                                            CrossAxisAlignment.start,
                                                                        mainAxisAlignment:
                                                                            MainAxisAlignment.center,
                                                                        children: [
                                                                          Text(
                                                                            '#$oid · $item',
                                                                            maxLines:
                                                                                2,
                                                                            overflow:
                                                                                TextOverflow.ellipsis,
                                                                            style:
                                                                                const TextStyle(
                                                                              fontWeight: FontWeight.w600,
                                                                              fontSize: 12,
                                                                            ),
                                                                          ),
                                                                          Text(
                                                                            '$cust · $stT',
                                                                            maxLines:
                                                                                1,
                                                                            overflow:
                                                                                TextOverflow.ellipsis,
                                                                            style:
                                                                                TextStyle(
                                                                              fontSize: 11,
                                                                              color: stC,
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ]
                                                          : [
                                                              DataCell(
                                                                Text('#$oid'),
                                                              ),
                                                              DataCell(
                                                                Text(
                                                                  '$item ($itype)',
                                                                  maxLines: 2,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                              ),
                                                              DataCell(
                                                                Text(
                                                                  cust,
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                              ),
                                                              DataCell(
                                                                Text(
                                                                  stT,
                                                                  style:
                                                                      TextStyle(
                                                                    color: stC,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    fontSize:
                                                                        12,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                    ),
                                                  );
                                                }

                                                return Material(
                                                  elevation: 0,
                                                  color: cs.surfaceContainerLow
                                                      .withValues(alpha: 0.65),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      12,
                                                    ),
                                                    side: BorderSide(
                                                      color: cs.outlineVariant
                                                          .withValues(
                                                        alpha: 0.45,
                                                      ),
                                                    ),
                                                  ),
                                                  clipBehavior: Clip.antiAlias,
                                                  child: Scrollbar(
                                                    child:
                                                        SingleChildScrollView(
                                                      scrollDirection:
                                                          Axis.vertical,
                                                      child:
                                                          SingleChildScrollView(
                                                        scrollDirection:
                                                            Axis.horizontal,
                                                        child: Align(
                                                          alignment:
                                                              Alignment
                                                                  .topLeft,
                                                          child:
                                                              ConstrainedBox(
                                                            constraints: box,
                                                            child: DataTable(
                                                              headingRowColor:
                                                                  WidgetStateProperty
                                                                      .all(
                                                                cs.surfaceContainerHigh,
                                                              ),
                                                              dataRowMinHeight:
                                                                  narrow
                                                                      ? 52
                                                                      : 44,
                                                              dataRowMaxHeight:
                                                                  narrow
                                                                      ? 64
                                                                      : 52,
                                                              columnSpacing:
                                                                  narrow
                                                                      ? 6
                                                                      : 12,
                                                              horizontalMargin:
                                                                  narrow
                                                                      ? 6
                                                                      : 10,
                                                              showCheckboxColumn:
                                                                  false,
                                                              dividerThickness:
                                                                  0.5,
                                                              columns: narrow
                                                                  ? [
                                                                      DataColumn(
                                                                        label: dataTableColumnLabel(
                                                                          'Pekerjaan',
                                                                        ),
                                                                      ),
                                                                    ]
                                                                  : [
                                                                      DataColumn(
                                                                        label: dataTableColumnLabel(
                                                                          'Order',
                                                                        ),
                                                                      ),
                                                                      DataColumn(
                                                                        label: dataTableColumnLabel(
                                                                          'Item',
                                                                        ),
                                                                      ),
                                                                      DataColumn(
                                                                        label: dataTableColumnLabel(
                                                                          'Pelanggan',
                                                                        ),
                                                                      ),
                                                                      DataColumn(
                                                                        label: dataTableColumnLabel(
                                                                          'Status',
                                                                        ),
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

                              // Material Stock Tab
                              _materialStock.isEmpty
                                  ? const Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.inventory,
                                            size: 48,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(height: 16),
                                          Text('Tidak ada stok material'),
                                        ],
                                      ),
                                    )
                                  : RefreshIndicator(
                                      onRefresh: _loadData,
                                      child: ListView(
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
                                        padding: const EdgeInsets.all(12),
                                        children: [
                                          SizedBox(
                                            height: math.max(
                                              360.0,
                                              MediaQuery.sizeOf(context)
                                                      .height *
                                                  0.45,
                                            ),
                                            child: LayoutBuilder(
                                              builder: (context, c) {
                                                final cs = Theme.of(context)
                                                    .colorScheme;
final rows = <DataRow>[];
                                                for (var i = 0;
                                                    i < _materialStock.length;
                                                    i++) {
                                                  final m = _materialStock[i];
                                                  final q = (m['quantity'] is num)
                                                      ? (m['quantity'] as num)
                                                      : num.tryParse(m['quantity']
                                                              ?.toString() ??
                                                          '') ??
                                                          0;
                                                  final hi = q > 10;
                                                  rows.add(
                                                    DataRow(
                                                      color: WidgetStateProperty
                                                          .resolveWith((s) {
                                                        if (s.contains(
                                                          WidgetState.hovered,
                                                        )) {
                                                          return cs.primary
                                                              .withValues(
                                                            alpha: 0.06,
                                                          );
                                                        }
                                                        return i.isOdd
                                                            ? cs.surfaceContainerHighest
                                                                .withValues(
                                                                alpha: 0.45,
                                                              )
                                                            : null;
                                                      }),
                                                      cells: [
                                                        DataCell(
                                                          Text(
                                                            m['item_name']
                                                                    ?.toString() ??
                                                                '—',
                                                            style: const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ),
                                                        DataCell(
                                                          Text(
                                                            m['item_type']
                                                                    ?.toString() ??
                                                                '—',
                                                          ),
                                                        ),
                                                        DataCell(
                                                          Text(
                                                            '$q ${m['unit'] ?? 'pcs'}',
                                                          ),
                                                        ),
                                                        DataCell(
                                                          Text(
                                                            m['material_type']
                                                                    ?.toString() ??
                                                                '—',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: cs
                                                                  .onSurfaceVariant,
                                                            ),
                                                          ),
                                                        ),
                                                        DataCell(
                                                          Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              horizontal: 8,
                                                              vertical: 4,
                                                            ),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: hi
                                                                  ? Colors.green
                                                                  : Colors
                                                                      .orange,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                10,
                                                              ),
                                                            ),
                                                            child: Text(
                                                              hi
                                                                  ? 'Tersedia'
                                                                  : 'Terbatas',
                                                              style:
                                                                  const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                }
                                                return Material(
                                                  elevation: 0,
                                                  color: cs.surfaceContainerLow
                                                      .withValues(alpha: 0.65),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      12,
                                                    ),
                                                    side: BorderSide(
                                                      color: cs.outlineVariant
                                                          .withValues(
                                                        alpha: 0.45,
                                                      ),
                                                    ),
                                                  ),
                                                  clipBehavior: Clip.antiAlias,
                                                  child: Scrollbar(
                                                    child:
                                                        SingleChildScrollView(
                                                      scrollDirection:
                                                          Axis.horizontal,
                                                      child: ConstrainedBox(
                                                        constraints:
                                                            BoxConstraints(
                                                          minWidth: c.maxWidth,
                                                        ),
                                                        child: DataTable(
                                                          headingRowColor:
                                                              WidgetStateProperty
                                                                  .all(
                                                            cs.surfaceContainerHigh,
                                                          ),
dataRowMinHeight: 44,
                                                          dataRowMaxHeight: 52,
                                                          columnSpacing: 12,
                                                          horizontalMargin: 10,
                                                          showCheckboxColumn:
                                                              false,
                                                          dividerThickness: 0.5,
                                                          columns: [
                                                            DataColumn(
                                                              label: dataTableColumnLabel(
                                                                'Item',
                                                              ),
                                                            ),
                                                            DataColumn(
                                                              label: dataTableColumnLabel(
                                                                'Tipe',
                                                              ),
                                                            ),
                                                            DataColumn(
                                                              label: dataTableColumnLabel(
                                                                'Stok',
                                                              ),
                                                            ),
                                                            DataColumn(
                                                              label: dataTableColumnLabel(
                                                                'Material',
                                                              ),
                                                            ),
                                                            DataColumn(
                                                              label: dataTableColumnLabel(
                                                                'Level',
                                                              ),
                                                            ),
                                                          ],
                                                          rows: rows,
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
                            ],
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
