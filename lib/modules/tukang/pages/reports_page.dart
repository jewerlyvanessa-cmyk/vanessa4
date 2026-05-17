import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/responsive_form_row.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  String _selectedPeriod = 'today';
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
      final block = userState.workshopSessionBlockReason;
      if (block != null) {
        setState(() {
          _error = block;
          _isLoading = false;
        });
        return;
      }
      final userId = userState.userId;
      if (userId == null) {
        setState(() {
          _error = 'Sesi tidak valid. Silakan login ulang.';
          _isLoading = false;
        });
        return;
      }
      final reports = await ApiService.getTechnicianReports(
        userId.toString(),
        userState.branch,
        period: _selectedPeriod,
      );

      if (!mounted) return;
      setState(() {
        _reportsData = reports;
        _isLoading = false;
      });
    } on UnauthorizedApiException {
      if (!mounted) return;
      setState(() {
        _error = null;
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

  void _changePeriod(String period) {
    if (_selectedPeriod == period) return;
    setState(() => _selectedPeriod = period);
    _loadReports();
  }

  String _getPeriodText(String period) {
    switch (period) {
      case 'today':
        return 'Hari Ini';
      case 'week':
        return 'Minggu Ini';
      case 'month':
        return 'Bulan Ini';
      case 'quarter':
        return '3 Bulan Terakhir';
      default:
        return 'Hari Ini';
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Map<String, dynamic> get _workStats {
    final raw = _reportsData?['work_stats'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  List<Map<String, dynamic>> _listField(String key) {
    final raw = _reportsData?[key];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  num _num(dynamic v) {
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '') ?? 0;
  }

  Widget _summaryCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _statLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _todayRow(List<Map<String, dynamic>> daily) {
    final now = DateTime.now();
    for (final day in daily) {
      final raw = day['work_date']?.toString();
      if (raw == null || raw.isEmpty) continue;
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) continue;
      if (parsed.year == now.year &&
          parsed.month == now.month &&
          parsed.day == now.day) {
        return day;
      }
    }
    return <String, dynamic>{};
  }

  Widget _reportBody(BuildContext context) {
    final userState = ref.watch(userStateProvider);
    final cs = Theme.of(context).colorScheme;
    final stats = _workStats;
    final daily = _listField('daily_distribution');
    final materials = _listField('material_usage');
    final workTypes = _listField('work_type_distribution');

    final todayStats = _selectedPeriod == 'today'
        ? stats
        : _todayRow(daily);
    final todayOrders = _selectedPeriod == 'today'
        ? _num(stats['total_orders'])
        : _num(todayStats['orders_count']);
    final todayCompleted = _selectedPeriod == 'today'
        ? _num(stats['completed_orders'])
        : _num(todayStats['completed_count']);

    return RefreshIndicator(
      onRefresh: _loadReports,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: ResponsiveLayout.pagePadding(context).copyWith(bottom: 24),
        children: [
          Text(
            'Laporan untuk: ${userState.username.isNotEmpty ? userState.username : 'Anda'}'
            '${userState.userId != null ? ' (ID ${userState.userId})' : ''}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Hanya pekerjaan yang ditugaskan ke akun login ini.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PeriodChip(
                label: 'Hari Ini',
                isSelected: _selectedPeriod == 'today',
                onTap: () => _changePeriod('today'),
              ),
              _PeriodChip(
                label: 'Minggu',
                isSelected: _selectedPeriod == 'week',
                onTap: () => _changePeriod('week'),
              ),
              _PeriodChip(
                label: 'Bulan',
                isSelected: _selectedPeriod == 'month',
                onTap: () => _changePeriod('month'),
              ),
              _PeriodChip(
                label: '3 Bulan',
                isSelected: _selectedPeriod == 'quarter',
                onTap: () => _changePeriod('quarter'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ResponsiveMetricRow(
            children: [
              _StatCard(
                title: 'Total',
                value: _num(stats['total_orders']).toString(),
                icon: Icons.work_outline,
                color: cs.primary,
              ),
              _StatCard(
                title: 'Rata-rata',
                value:
                    '${_num(stats['avg_duration_hours']).toStringAsFixed(1)}j',
                icon: Icons.schedule_outlined,
                color: cs.tertiary,
              ),
              _StatCard(
                title: 'Efisiensi',
                value: '${_num(stats['efficiency'])}%',
                icon: Icons.trending_up_outlined,
                color: cs.secondary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_selectedPeriod != 'today') ...[
            _summaryCard(
              context,
              title: 'Hari ini',
              icon: Icons.today_outlined,
              children: [
                _statLine('Tanggal', _formatDate(DateTime.now())),
                _statLine('Pekerjaan', todayOrders.toString()),
                _statLine('Selesai', todayCompleted.toString()),
              ],
            ),
            const SizedBox(height: 12),
          ],
          _summaryCard(
            context,
            title: _getPeriodText(_selectedPeriod),
            icon: Icons.calendar_month_outlined,
            children: [
              if (_selectedPeriod == 'today')
                _statLine('Tanggal', _formatDate(DateTime.now())),
              _statLine('Total pekerjaan', _num(stats['total_orders']).toString()),
              _statLine(
                'Selesai',
                _num(stats['completed_orders']).toString(),
              ),
              _statLine(
                'Dalam proses',
                _num(stats['in_progress_orders']).toString(),
              ),
              _statLine(
                'Menunggu',
                _num(stats['pending_orders']).toString(),
              ),
              _statLine(
                'Rata-rata / pekerjaan',
                '${_num(stats['avg_duration_hours']).toStringAsFixed(1)} jam',
              ),
              _statLine(
                'Total jam kerja',
                '${_num(stats['total_work_hours']).toStringAsFixed(1)} jam',
              ),
              _statLine('Efisiensi', '${_num(stats['efficiency'])}%'),
              _statLine(
                'Tepat waktu',
                '${_num(stats['on_time_rate'])}%',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _summaryCard(
            context,
            title: 'Distribusi harian',
            icon: Icons.bar_chart_outlined,
            children: daily.isEmpty
                ? [
                    Text(
                      'Belum ada data harian pada periode ini.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ]
                : daily.take(14).map((day) {
                    final dateRaw = day['work_date']?.toString();
                    final parsed = DateTime.tryParse(dateRaw ?? '');
                    final label = parsed != null
                        ? _formatDate(parsed)
                        : (dateRaw ?? '—');
                    return _statLine(
                      label,
                      '${_num(day['orders_count'])} kerja · ${_num(day['completed_count'])} selesai',
                    );
                  }).toList(),
          ),
          const SizedBox(height: 12),
          _summaryCard(
            context,
            title: 'Penggunaan material',
            icon: Icons.inventory_2_outlined,
            children: materials.isEmpty
                ? [
                    Text(
                      'Belum ada catatan material pada periode ini.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ]
                : materials.map((m) {
                    return _statLine(
                      m['material_type']?.toString() ?? '—',
                      '${_num(m['total_weight_used']).toStringAsFixed(1)} g · ${_num(m['usage_count'])}×',
                    );
                  }).toList(),
          ),
          const SizedBox(height: 12),
          _summaryCard(
            context,
            title: 'Jenis pekerjaan',
            icon: Icons.pie_chart_outline_outlined,
            children: workTypes.isEmpty
                ? [
                    Text(
                      'Belum ada breakdown jenis pekerjaan.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ]
                : workTypes.map((w) {
                    final avg = _num(w['avg_duration']);
                    return _statLine(
                      w['item_type']?.toString() ?? '—',
                      '${_num(w['count'])} · ${avg.toStringAsFixed(1)} jam rata-rata',
                    );
                  }).toList(),
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
        title: const Text('Laporan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
            onPressed: _isLoading ? null : _loadReports,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadReports,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : _reportsData == null
                  ? const Center(child: Text('Data laporan tidak tersedia'))
                  : _reportBody(context),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: isSelected ? cs.primary : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? cs.onPrimary : cs.onSurface,
              fontSize: AppTypography.bodySmall,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
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
