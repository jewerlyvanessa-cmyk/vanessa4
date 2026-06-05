import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

class TechnicianManagementPage extends ConsumerStatefulWidget {
  const TechnicianManagementPage({super.key});

  @override
  ConsumerState<TechnicianManagementPage> createState() =>
      _TechnicianManagementPageState();
}

class _TechnicianManagementPageState
    extends ConsumerState<TechnicianManagementPage> {
  List<dynamic> _technicians = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadTechnicians();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Note: ref.listen should be used in build method, not here
  }

  Future<void> _loadTechnicians() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);

      final response = await ApiClient.get(
        '/technicians',
        query: {'branch_id': userState.branch},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _technicians = data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Gagal memuat data tukang';
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

  @override
  Widget build(BuildContext context) {
    // Listen to real-time technician updates
    ref.listen(realTimeOrderUpdatesProvider, (previous, next) {
      next.whenData((update) {
        if (update['type'] == 'technician_update' ||
            update['type'] == 'technician_assignment' ||
            update['type'] == 'workshop_update') {
          // Refresh technician data when relevant updates occur
          _loadTechnicians();
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Tukang'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTechnicians,
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
                    onPressed: _loadTechnicians,
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final narrow = c.maxWidth < 600;
                      final g = narrow ? 8.0 : 16.0;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _buildSummaryCard(
                                    'Total Tukang',
                                    _technicians.length,
                                    Icons.engineering,
                                    Colors.blue,
                                  ),
                                ),
                                SizedBox(width: g),
                                Expanded(
                                  child: _buildSummaryCard(
                                    'Aktif',
                                    _technicians
                                        .where((t) => t['status'] == 'active')
                                        .length,
                                    Icons.check_circle,
                                    Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: g),
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _buildSummaryCard(
                                    'Sibuk',
                                    _technicians
                                        .where((t) => t['status'] == 'busy')
                                        .length,
                                    Icons.schedule,
                                    Colors.orange,
                                  ),
                                ),
                                SizedBox(width: g),
                                Expanded(
                                  child: _buildSummaryCard(
                                    'Tersedia',
                                    _technicians
                                        .where(
                                          (t) => t['status'] == 'available',
                                        )
                                        .length,
                                    Icons.check_circle_outline,
                                    Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Daftar tukang (${_technicians.length})',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _technicians.isEmpty
                        ? const Center(
                            child: Text('Belum ada data tukang'),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 600;
                              final cs = Theme.of(context).colorScheme;
const desktopW = 880.0;
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
                              for (var i = 0; i < _technicians.length; i++) {
                                final t = _technicians[i];
                                final name = (t['name'] ?? 'N/A').toString();
                                final spec =
                                    (t['specialization'] ?? 'Umum').toString();
                                final st = t['status'];
                                final stLabel = _getStatusLabel(st);
                                final stColor = _getStatusColor(st);
                                final menu = DataCell(
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert),
                                      tooltip: 'Tindakan',
                                      onSelected: (action) =>
                                          _handleTechnicianAction(t, action),
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: 'view_workload',
                                          child: Text('Lihat beban kerja'),
                                        ),
                                        PopupMenuItem(
                                          value: 'assign_order',
                                          child: Text('Assign order'),
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
                                                    name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                  Text(
                                                    '$spec · $stLabel',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: stColor,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            menu,
                                          ]
                                        : [
                                            DataCell(Text(name)),
                                            DataCell(Text(spec)),
                                            DataCell(
                                              Text(
                                                stLabel,
                                                style: TextStyle(
                                                  color: stColor,
                                                  fontWeight: FontWeight.w600,
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
dataRowMinHeight: narrow ? 44 : 44,
                                            dataRowMaxHeight: narrow ? 56 : 52,
                                            columnSpacing: narrow ? 8 : 14,
                                            horizontalMargin:
                                                narrow ? 8 : 12,
                                            showCheckboxColumn: false,
                                            dividerThickness: 0.5,
                                            columns: narrow
                                                ? [
                                                    DataColumn(
                                                      label: dataTableColumnLabel('Tukang'),
                                                    ),
                                                    const DataColumn(
                                                      label: SizedBox(width: 44),
                                                    ),
                                                  ]
                                                : [
                                                    DataColumn(
                                                      label: dataTableColumnLabel('Nama'),
                                                    ),
                                                    DataColumn(
                                                      label:
                                                          dataTableColumnLabel('Spesialisasi'),
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
      case 'available':
        return Colors.green;
      case 'busy':
        return Colors.orange;
      case 'offline':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'available':
        return 'Tersedia';
      case 'busy':
        return 'Sibuk';
      case 'offline':
        return 'Offline';
      default:
        return 'Unknown';
    }
  }

  void _handleTechnicianAction(dynamic technician, String action) {
    switch (action) {
      case 'view_workload':
        // Navigate to workload view
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Melihat beban kerja ${technician['name']}')),
        );
        break;
      case 'assign_order':
        // Navigate to order assignment
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Assign order ke ${technician['name']}')),
        );
        break;
    }
  }
}
