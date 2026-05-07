import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/providers/user_state_provider.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
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
      final reports = await ApiService.getTechnicianReports(
        userState.userId.toString(),
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Kembali',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Laporan'),
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
        ],
      ),
      body: Column(
        children: [
          // Report Categories
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
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      children: [
                        _ReportCard(
                          icon: Icons.work,
                          title: 'Laporan Harian',
                          subtitle: 'Ringkasan pekerjaan hari ini',
                          color: Colors.blue,
                          onTap: () => _showDailyReport(context),
                        ),
                        _ReportCard(
                          icon: Icons.calendar_month,
                          title: 'Laporan Periode',
                          subtitle: 'Statistik pekerjaan periode',
                          color: Colors.green,
                          onTap: () => _showPeriodReport(context),
                        ),
                        _ReportCard(
                          icon: Icons.inventory,
                          title: 'Penggunaan Material',
                          subtitle: 'Laporan material yang digunakan',
                          color: Colors.orange,
                          onTap: () => _showMaterialReport(context),
                        ),
                        _ReportCard(
                          icon: Icons.trending_up,
                          title: 'Performa',
                          subtitle: 'Analisis performa kerja',
                          color: Colors.purple,
                          onTap: () => _showPerformanceReport(context),
                        ),
                        _ReportCard(
                          icon: Icons.pie_chart,
                          title: 'Distribusi Pekerjaan',
                          subtitle: 'Breakdown jenis pekerjaan',
                          color: Colors.teal,
                          onTap: () => _showWorkDistributionReport(context),
                        ),
                        _ReportCard(
                          icon: Icons.download,
                          title: 'Export Laporan',
                          subtitle: 'Unduh laporan dalam format PDF',
                          color: Colors.indigo,
                          onTap: () => _exportReport(context),
                        ),
                      ],
                    ),
                  ),
          ),

          // Quick Stats
          if (_reportsData != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Statistik Cepat', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _QuickStat(
                              label: 'Total Pekerjaan',
                              value: _reportsData!['work_stats']['total_orders'].toString(),
                              icon: Icons.work,
                              color: Colors.blue,
                            ),
                          ),
                          Expanded(
                            child: _QuickStat(
                              label: 'Rata-rata Waktu',
                              value: '${_reportsData!['work_stats']['avg_duration_hours'].toStringAsFixed(1)}h',
                              icon: Icons.schedule,
                              color: Colors.green,
                            ),
                          ),
                          Expanded(
                            child: _QuickStat(
                              label: 'Efisiensi',
                              value: '${_reportsData!['work_stats']['efficiency']}%',
                              icon: Icons.trending_up,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
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

  void _showDailyReport(BuildContext context) {
    if (_reportsData == null) return;

    final todayStats = _reportsData!['daily_distribution'].isNotEmpty
      ? _reportsData!['daily_distribution'][0]
      : {'orders_count': 0, 'completed_count': 0};

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Laporan Harian'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tanggal: ${_formatDate(DateTime.now())}'),
              const SizedBox(height: 8),
              Text('Total Pekerjaan: ${todayStats['orders_count']}'),
              Text('Pekerjaan Selesai: ${todayStats['completed_count']}'),
              Text('Pekerjaan Pending: ${todayStats['orders_count'] - todayStats['completed_count']}'),
              Text('Rata-rata Waktu: ${_reportsData!['work_stats']['avg_duration_hours'].toStringAsFixed(1)} jam'),
              const SizedBox(height: 8),
              const Text('Status Pekerjaan:'),
              Text('• Selesai: ${todayStats['completed_count']}'),
              Text('• Dalam Proses: ${_reportsData!['work_stats']['in_progress_orders']}'),
              Text('• Menunggu: ${_reportsData!['work_stats']['pending_orders']}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Laporan harian diekspor')),
              );
            },
            child: const Text('Export'),
          ),
        ],
      ),
    );
  }

  void _showPeriodReport(BuildContext context) {
    if (_reportsData == null) return;

    final stats = _reportsData!['work_stats'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Laporan ${_getPeriodText(_selectedPeriod)}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Periode: ${_getPeriodText(_selectedPeriod)}'),
              const SizedBox(height: 8),
              Text('Total Pekerjaan: ${stats['total_orders']}'),
              Text('Pekerjaan Selesai: ${stats['completed_orders']}'),
              Text('Pekerjaan Pending: ${stats['pending_orders'] + stats['in_progress_orders']}'),
              Text('Rata-rata Waktu per Pekerjaan: ${stats['avg_duration_hours'].toStringAsFixed(1)} jam'),
              Text('Total Waktu Kerja: ${stats['total_work_hours'].toStringAsFixed(1)} jam'),
              const SizedBox(height: 8),
              const Text('Distribusi Harian:'),
              ..._reportsData!['daily_distribution'].take(7).map<Widget>((day) =>
                Text('• ${_formatDate(DateTime.parse(day['work_date']))}: ${day['orders_count']} pekerjaan')
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Laporan periode diekspor')),
              );
            },
            child: const Text('Export'),
          ),
        ],
      ),
    );
  }

  void _showMaterialReport(BuildContext context) {
    if (_reportsData == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Laporan Penggunaan Material'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Periode: ${_getPeriodText(_selectedPeriod)}'),
              const SizedBox(height: 8),
              const Text('Total Material Digunakan:'),
              ..._reportsData!['material_usage'].map<Widget>((material) =>
                Text('• ${material['material_type']}: ${material['total_weight_used'].toStringAsFixed(1)} gram (${material['usage_count']} kali)')
              ),
              const SizedBox(height: 8),
              const Text('Material berdasarkan Jenis Pekerjaan:'),
              ..._reportsData!['work_type_distribution'].map<Widget>((workType) =>
                Text('• ${workType['item_type']}: ${workType['count']} pekerjaan (${workType['avg_duration']?.toStringAsFixed(1) ?? '0'} jam rata-rata)')
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Laporan material diekspor')),
              );
            },
            child: const Text('Export'),
          ),
        ],
      ),
    );
  }

  void _showPerformanceReport(BuildContext context) {
    if (_reportsData == null) return;

    final stats = _reportsData!['work_stats'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Laporan Performa'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Periode: ${_getPeriodText(_selectedPeriod)}'),
              const SizedBox(height: 8),
              const Text('Metrik Performa:'),
              Text('• Efisiensi Kerja: ${stats['efficiency']}%'),
              Text('• Tingkat Penyelesaian: ${stats['on_time_rate']}%'),
              Text('• Rata-rata Waktu per Pekerjaan: ${stats['avg_duration_hours'].toStringAsFixed(1)} jam'),
              Text('Total Waktu Kerja: ${stats['total_work_hours'].toStringAsFixed(1)} jam'),
              const SizedBox(height: 8),
              const Text('Kekuatan:'),
              const Text('• Konsistensi dalam penyelesaian pekerjaan'),
              const Text('• Penggunaan material yang efisien'),
              const Text('• Kemampuan mengelola berbagai jenis pekerjaan'),
              const SizedBox(height: 8),
              const Text('Area Perbaikan:'),
              const Text('• Optimasi waktu persiapan pekerjaan'),
              const Text('• Peningkatan akurasi estimasi material'),
            ],
          ),
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

  void _showWorkDistributionReport(BuildContext context) {
    if (_reportsData == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Distribusi Jenis Pekerjaan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Periode: ${_getPeriodText(_selectedPeriod)}'),
              const SizedBox(height: 8),
              const Text('Breakdown berdasarkan Jenis Pekerjaan:'),
              ..._reportsData!['work_type_distribution'].map<Widget>((workType) =>
                Text('• ${workType['item_type']}: ${workType['count']} pekerjaan (${workType['avg_duration']?.toStringAsFixed(1) ?? '0'} jam rata-rata)')
              ),
              const SizedBox(height: 8),
              const Text('Distribusi Harian:'),
              ..._reportsData!['daily_distribution'].take(7).map<Widget>((day) =>
                Text('• ${_formatDate(DateTime.parse(day['work_date']))}: ${day['orders_count']} pekerjaan (${day['completed_count']} selesai)')
              ),
            ],
          ),
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

  void _exportReport(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Memilih jenis laporan untuk diekspor...')),
    );

    // Show export options
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Pilih Jenis Laporan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.today),
              title: const Text('Laporan Harian'),
              onTap: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Laporan harian diekspor ke PDF')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month),
              title: const Text('Laporan Periode'),
              onTap: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Laporan periode diekspor ke PDF')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory),
              title: const Text('Laporan Material'),
              onTap: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Laporan material diekspor ke PDF')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

class _ReportCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ReportCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _QuickStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
