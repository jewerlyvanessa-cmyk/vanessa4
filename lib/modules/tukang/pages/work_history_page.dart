import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/main.dart';

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
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    itemCount: _workHistory.length,
                    itemBuilder: (context, index) {
                      final work = _workHistory[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _getStatusColor(work['status']),
                            child: Icon(
                              _getStatusIcon(work['status']),
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          title: Text('Order #${work['order_id']}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${work['item_name']} (${work['item_type']})',
                              ),
                              Text('Pelanggan: ${work['customer_name']}'),
                              Text(
                                'Tanggal: ${_formatDate(work['completed_at'] ?? work['created_at'])}',
                              ),
                              if (work['duration_hours'] != null)
                                Text(
                                  'Waktu: ${work['duration_hours'].toStringAsFixed(1)} jam',
                                ),
                            ],
                          ),
                          trailing: Text(
                            _getStatusText(work['status']),
                            style: TextStyle(
                              color: _getStatusColor(work['status']),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          onTap: () => _showWorkDetail(context, work),
                        ),
                      );
                    },
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

    final completedWorks = _workHistory
        .where((work) => work['status'] == 'completed')
        .length;
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
    switch (status) {
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
      case 'completed':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help;
    }
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
