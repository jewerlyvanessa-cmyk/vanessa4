import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/shared_widgets/module_dashboard_app_bar.dart';
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';

class WorkshopReportsPage extends ConsumerStatefulWidget {
  const WorkshopReportsPage({super.key});

  @override
  ConsumerState<WorkshopReportsPage> createState() =>
      _WorkshopReportsPageState();
}

class _WorkshopReportsPageState extends ConsumerState<WorkshopReportsPage> {
  String _selectedPeriod = 'month';
  Map<String, dynamic>? _reportsData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userState = ref.read(userStateProvider);
      final reports = await ApiService.getWorkshopReports(
        userState.branch,
        period: _selectedPeriod,
      );

      setState(() {
        _reportsData = reports;
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
    _loadReports();
  }

  @override
  Widget build(BuildContext context) {
    final userState = ref.watch(userStateProvider);
    final webSocketState = ref.watch(webSocketProvider);

    return Scaffold(
      appBar: AppBar(
        title: const ModuleAppBarTitle(title: 'Laporan Workshop'),
        actions: [
          // Period selector
          PopupMenuButton<String>(
            onSelected: _changePeriod,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'week', child: Text('Minggu Ini')),
              const PopupMenuItem(value: 'month', child: Text('Bulan Ini')),
              const PopupMenuItem(value: 'quarter', child: Text('3 Bulan')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(_getPeriodText(_selectedPeriod)),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          // Real-time connection indicator
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Icon(
                  webSocketState != null ? Icons.wifi : Icons.wifi_off,
                  color: webSocketState != null ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 4),
                const Text('Live', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          SwitchBranchRoleWidget(),
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Kembali',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Column(
        children: [
          // User Info Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admin Workshop: ${userState.username}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Branch: ${userState.branch}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),

          // Report Summary Cards
          if (_reportsData != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          title: 'Total Orders',
                          value: _reportsData!['total_orders'].toString(),
                          icon: Icons.assignment,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SummaryCard(
                          title: 'Completed',
                          value: _reportsData!['completed_orders'].toString(),
                          icon: Icons.check_circle,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          title: 'In Progress',
                          value: _reportsData!['in_progress_orders'].toString(),
                          icon: Icons.engineering,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SummaryCard(
                          title: 'Pending',
                          value: _reportsData!['pending_orders'].toString(),
                          icon: Icons.schedule,
                          color: Colors.red,
                        ),
                      ),
                    ],
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
                          onPressed: _loadReports,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  )
                : _reportsData == null
                ? const Center(child: Text('Tidak ada data laporan'))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSection('Ringkasan Produksi', [
                          _buildStatItem(
                            'Total Order',
                            _reportsData!['total_orders'].toString(),
                          ),
                          _buildStatItem(
                            'Order Selesai',
                            _reportsData!['completed_orders'].toString(),
                          ),
                          _buildStatItem(
                            'Order Dalam Proses',
                            _reportsData!['in_progress_orders'].toString(),
                          ),
                          _buildStatItem(
                            'Order Pending',
                            _reportsData!['pending_orders'].toString(),
                          ),
                          _buildStatItem(
                            'Rata-rata Waktu Produksi',
                            '${_reportsData!['avg_production_time']?.toStringAsFixed(1) ?? '0'} jam',
                          ),
                        ]),
                        const SizedBox(height: 16),
                        _buildSection('Penggunaan Material', [
                          _buildStatItem(
                            'Total Material Digunakan',
                            '${_reportsData!['total_material_used']?.toStringAsFixed(1) ?? '0'} gram',
                          ),
                          _buildStatItem(
                            'Jenis Material',
                            _reportsData!['material_types']?.toString() ?? '0',
                          ),
                          _buildStatItem(
                            'Efisiensi Material',
                            '${_reportsData!['material_efficiency']?.toStringAsFixed(1) ?? '0'}%',
                          ),
                        ]),
                        const SizedBox(height: 16),
                        _buildSection('Performa Tukang', [
                          _buildStatItem(
                            'Total Tukang Aktif',
                            _reportsData!['active_technicians']?.toString() ??
                                '0',
                          ),
                          _buildStatItem(
                            'Rata-rata Produktivitas',
                            '${_reportsData!['avg_productivity']?.toStringAsFixed(1) ?? '0'} order/hari',
                          ),
                          _buildStatItem(
                            'Tingkat Kepuasan',
                            '${_reportsData!['satisfaction_rate']?.toStringAsFixed(1) ?? '0'}%',
                          ),
                        ]),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Export reports
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Laporan workshop diekspor')),
          );
        },
        tooltip: 'Export Laporan',
        child: const Icon(Icons.download),
      ),
    );
  }

  String _getPeriodText(String period) {
    switch (period) {
      case 'week':
        return 'Minggu';
      case 'month':
        return 'Bulan';
      case 'quarter':
        return '3 Bulan';
      default:
        return 'Bulan';
    }
  }

  Widget _buildSection(String title, List<Widget> items) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...items,
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
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
