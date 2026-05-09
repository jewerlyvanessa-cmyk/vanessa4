import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/utils/order_status_ui.dart';

class WorkHistoryPage extends ConsumerStatefulWidget {
  const WorkHistoryPage({super.key});

  @override
  ConsumerState<WorkHistoryPage> createState() => _WorkHistoryPageState();
}

class _WorkHistoryPageState extends ConsumerState<WorkHistoryPage> {
  String _selectedPeriod = 'all';
  List<Map<String, dynamic>> _workHistory = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadWorkHistory();
  }

  Future<void> _loadWorkHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userState = ref.read(userStateProvider);
      final history = await ApiService.getWorkHistory(
        userState.userId.toString(),
        userState.branch,
        period: _selectedPeriod,
      );

      setState(() {
        _workHistory = history;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _changePeriod(String period) {
    setState(() {
      _selectedPeriod = period;
    });
    _loadWorkHistory();
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
        title: const Text('Riwayat Pekerjaan'),
      ),
      body: Column(
        children: [
          // Filter Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                _FilterChip(
                  label: 'Semua',
                  isSelected: _selectedPeriod == 'all',
                  onTap: () => _changePeriod('all'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Hari Ini',
                  isSelected: _selectedPeriod == 'today',
                  onTap: () => _changePeriod('today'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Minggu Ini',
                  isSelected: _selectedPeriod == 'week',
                  onTap: () => _changePeriod('week'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Bulan Ini',
                  isSelected: _selectedPeriod == 'month',
                  onTap: () => _changePeriod('month'),
                ),
              ],
            ),
          ),

          // Statistics Cards
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'Total Pekerjaan',
                    value: _workHistory.length.toString(),
                    icon: Icons.work,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    title: 'Rata-rata Waktu',
                    value: _calculateAverageTime(),
                    icon: Icons.schedule,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    title: 'Tingkat Kepuasan',
                    value: _calculateSatisfactionRate(),
                    icon: Icons.star,
                    color: Colors.orange,
                  ),
                ),
              ],
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
                          onPressed: _loadWorkHistory,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  )
                : _workHistory.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Belum ada riwayat pekerjaan'),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
                        for (var i = 0; i < _workHistory.length; i++) {
                          final work = _workHistory[i];
                          final st = work['status']?.toString() ?? '';
                          final stColor = _getStatusColor(st);
                          final oid = (work['order_id'] ?? '—').toString();
                          final item =
                              (work['item_name'] ?? 'N/A').toString();
                          final itype =
                              (work['item_type'] ?? '').toString();
                          final cust =
                              (work['customer_name'] ?? 'N/A').toString();
                          final dateStr = _formatDate(
                            work['completed_at'] ?? work['created_at'],
                          );
                          final dur = work['duration_hours'];
                          final durStr = dur == null
                              ? '—'
                              : '${(dur as num).toStringAsFixed(1)} j';

                          final detailBtn = DataCell(
                            IconButton(
                              tooltip: 'Detail',
                              icon: const Icon(Icons.info_outline),
                              onPressed: () =>
                                  _showWorkDetail(context, work),
                            ),
                          );

                          rows.add(
                            DataRow(
                              color: WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.hovered)) {
                                  return cs.primary.withValues(alpha: 0.06);
                                }
                                return i.isOdd
                                    ? cs.surfaceContainerHighest
                                        .withValues(alpha: 0.45)
                                    : null;
                              }),
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
                                              '#$oid · $item',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ),
                                            Text(
                                              '$dateStr · ${_getStatusText(st)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: stColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      detailBtn,
                                    ]
                                  : [
                                      DataCell(Text('#$oid')),
                                      DataCell(
                                        Text(
                                          '$item ($itype)',
                                          maxLines: 2,
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
                                      DataCell(
                                        Text(
                                          dateStr,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(durStr)),
                                      DataCell(
                                        Text(
                                          _getStatusText(st),
                                          style: TextStyle(
                                            color: stColor,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      detailBtn,
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
                                      dataRowMaxHeight: narrow ? 64 : 56,
                                      columnSpacing: narrow ? 6 : 10,
                                      horizontalMargin: narrow ? 6 : 10,
                                      showCheckboxColumn: false,
                                      dividerThickness: 0.5,
                                      columns: narrow
                                          ? [
                                              DataColumn(
                                                label: dataTableColumnLabel('Riwayat'),
                                              ),
                                              const DataColumn(
                                                label: SizedBox(width: 44),
                                              ),
                                            ]
                                          : [
                                              DataColumn(label: dataTableColumnLabel('Order')),
                                              DataColumn(label: dataTableColumnLabel('Item')),
                                              DataColumn(
                                                label: dataTableColumnLabel('Pelanggan'),
                                              ),
                                              DataColumn(
                                                label: dataTableColumnLabel('Tanggal'),
                                              ),
                                              DataColumn(
                                                label: dataTableColumnLabel('Durasi'),
                                              ),
                                              DataColumn(
                                                label: dataTableColumnLabel('Status'),
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
        onPressed: () {
          // Export work history
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Riwayat pekerjaan diekspor')),
          );
        },
        tooltip: 'Export Riwayat',
        child: const Icon(Icons.download),
      ),
    );
  }

  String _calculateAverageTime() {
    if (_workHistory.isEmpty) return '0 jam';

    final completedWorks = _workHistory.where(
      (work) => work['duration_hours'] != null,
    );
    if (completedWorks.isEmpty) return '0 jam';

    final totalHours = completedWorks.fold<double>(
      0,
      (sum, work) => sum + work['duration_hours'],
    );
    final average = totalHours / completedWorks.length;
    return '${average.toStringAsFixed(1)} jam';
  }

  String _calculateSatisfactionRate() {
    if (_workHistory.isEmpty) return '0%';

    final completedWorks = _workHistory.where((work) {
      final st = (work['status'] ?? '').toString().trim().toLowerCase();
      return st == 'done_workshop' || st == 'ready_for_pickup' || st == 'completed';
    }).length;
    final rate = (completedWorks / _workHistory.length) * 100;
    return '${rate.toStringAsFixed(0)}%';
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day} ${_getMonthName(date.month)} ${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Ags',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return months[month - 1];
  }

  String _getStatusText(String status) {
    return OrderStatusUi.label(status);
  }

  Color _getStatusColor(String status) {
    return OrderStatusUi.color(status);
  }

  void _showWorkDetail(BuildContext context, Map<String, dynamic> work) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Detail Order #${work['order_id']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Jenis Pekerjaan: ${work['item_name']} (${work['item_type']})',
            ),
            const SizedBox(height: 8),
            Text('Pelanggan: ${work['customer_name']}'),
            const SizedBox(height: 8),
            Text(
              'Tanggal: ${_formatDate(work['completed_at'] ?? work['created_at'])}',
            ),
            const SizedBox(height: 8),
            if (work['duration_hours'] != null)
              Text('Durasi: ${work['duration_hours'].toStringAsFixed(1)} jam'),
            const SizedBox(height: 8),
            Text('Status: ${_getStatusText(work['status'])}'),
            const SizedBox(height: 8),
            Text('Material: ${work['material_type']}'),
            const SizedBox(height: 8),
            Text('Berat: ${work['weight']} gram'),
            if (work['notes'] != null && work['notes'].isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Catatan: ${work['notes']}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  const _FilterChip({required this.label, this.isSelected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor : Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
