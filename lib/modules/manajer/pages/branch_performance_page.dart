import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/shared_widgets/manager_report_period_selector.dart';
import 'package:vanessa3/utils/manager_report_print.dart';

class BranchPerformancePage extends ConsumerStatefulWidget {
  const BranchPerformancePage({super.key});

  @override
  ConsumerState<BranchPerformancePage> createState() =>
      _BranchPerformancePageState();
}

class _BranchPerformancePageState extends ConsumerState<BranchPerformancePage> {
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _rows = const [];
  bool _rangeMode = false;
  late DateTime _periodStart;
  late DateTime _periodEnd;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now().toLocal();
    _periodStart = managerReportDateOnly(n);
    _periodEnd = managerReportDateOnly(n);
    _load();
  }

  void _onPeriodChanged(DateTime start, DateTime end) {
    setState(() {
      _periodStart = managerReportDateOnly(start);
      _periodEnd = managerReportDateOnly(end);
    });
    _load();
  }

  Future<void> _printPdf() async {
    await printManagerBranchPerformancePdf(
      context,
      periodStart: _periodStart,
      periodEnd: _periodEnd,
      periodTitle: managerReportPeriodTitle(_periodStart, _periodEnd),
      periodSubtitle:
          managerReportPeriodShortSubtitle(_periodStart, _periodEnd),
      rows: List<Map<String, dynamic>>.from(_rows),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final branches = ref.read(userStateProvider).branches;
      final periodQp =
          managerReportPeriodQueryParams(_periodStart, _periodEnd);

      final futures = branches.map((b) async {
        final branchId = b['branch_id']?.toString() ?? '';
        final alias = (b['alias']?.toString().trim().isNotEmpty == true)
            ? b['alias'].toString().trim()
            : (b['name'] ?? branchId).toString();
        if (branchId.isEmpty) return <String, dynamic>{};

        final uri = Uri.parse('$baseUrl/api/dashboard/order-today').replace(
          queryParameters: {
            'branch_id': branchId,
            ...periodQp,
          },
        );
        final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
        if (resp.statusCode != 200) {
          return <String, dynamic>{
            'branch_id': branchId,
            'branch_alias': alias,
            'error': '${resp.statusCode}',
          };
        }

        final decoded = jsonDecode(resp.body);
        if (decoded is! Map) {
          return <String, dynamic>{
            'branch_id': branchId,
            'branch_alias': alias,
            'error': 'invalid_response',
          };
        }

        final byType = decoded['orders_by_type'];
        int nType(String k) {
          if (byType is! Map) return 0;
          final v = byType[k];
          if (v is num) return v.toInt();
          return int.tryParse(v?.toString() ?? '') ?? 0;
        }

        return <String, dynamic>{
          'branch_id': branchId,
          'branch_alias': alias,
          'jual': nType('jual'),
          'buyback': nType('buyback'),
          'service': nType('service'),
          'custom': nType('custom'),
        };
      }).toList();

      final results = (await Future.wait(futures))
          .where((m) => m.isNotEmpty)
          .toList();

      int intVal(dynamic v) {
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v?.toString() ?? '') ?? 0;
      }

      int typeSum(Map<String, dynamic> m) {
        if (m['error'] != null) return -1;
        return intVal(m['jual']) +
            intVal(m['buyback']) +
            intVal(m['service']) +
            intVal(m['custom']);
      }

      results.sort((a, b) {
        final sa = typeSum(a);
        final sb = typeSum(b);
        if (sa < 0 && sb >= 0) return 1;
        if (sa >= 0 && sb < 0) return -1;
        return sb.compareTo(sa);
      });

      if (!mounted) return;
      setState(() {
        _rows = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  static int _cellInt(Map<String, dynamic> r, String k) {
    final v = r[k];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  Widget _metricChip(
    ColorScheme cs, {
    required String label,
    required int value,
    required bool showDash,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              showDash ? '—' : '$value',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactBranchCard(
    ColorScheme cs,
    Map<String, dynamic> r,
  ) {
    final alias = (r['branch_alias'] ?? '-').toString();
    final err = r['error']?.toString();
    final hasErr = err != null;

    return Material(
      elevation: 0,
      color: cs.surfaceContainerLow.withValues(alpha: 0.65),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              alias,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: AppTypography.section,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (hasErr) ...[
              const SizedBox(height: 4),
              Text(
                err,
                style: TextStyle(
                  color: cs.error,
                  fontSize: 11,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _metricChip(
                    cs,
                    label: 'Jual',
                    value: _cellInt(r, 'jual'),
                    showDash: hasErr,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metricChip(
                    cs,
                    label: 'Buyback',
                    value: _cellInt(r, 'buyback'),
                    showDash: hasErr,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _metricChip(
                    cs,
                    label: 'Service',
                    value: _cellInt(r, 'service'),
                    showDash: hasErr,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metricChip(
                    cs,
                    label: 'Custom',
                    value: _cellInt(r, 'custom'),
                    showDash: hasErr,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        managerReportPeriodTitle(_periodStart, _periodEnd);
    final periodHint =
        managerReportPeriodShortSubtitle(_periodStart, _periodEnd);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Performa Cabang'),
        actions: [
          if (!_loading && _error.isEmpty)
            IconButton(
              tooltip: 'Cetak PDF',
              onPressed: _printPdf,
              icon: const Icon(Icons.print_outlined),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: ManagerReportPeriodSelector(
                        rangeMode: _rangeMode,
                        rangeStart: _periodStart,
                        rangeEnd: _periodEnd,
                        onRangeModeChanged: (v) {
                          setState(() => _rangeMode = v);
                          if (v) _load();
                        },
                        onPeriodChanged: _onPeriodChanged,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Card(
                        child: ListTile(
                          leading: const Icon(Icons.analytics_outlined),
                          title: Text(dateLabel),
                          subtitle: Text(
                            'Order per cabang • $periodHint',
                          ),
                          trailing: Chip(label: Text('${_rows.length}')),
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: _rows.isEmpty
                            ? ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(top: 48),
                                children: const [
                                  Center(child: Text('Tidak ada data')),
                                ],
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final cs = Theme.of(context).colorScheme;
                                  const compactBreakpoint = 560.0;
                                  final useCompact =
                                      constraints.maxWidth < compactBreakpoint;

                                  if (useCompact) {
                                    return ListView.separated(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        0,
                                        12,
                                        12,
                                      ),
                                      itemCount: _rows.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: 10),
                                      itemBuilder: (context, i) {
                                        return _buildCompactBranchCard(
                                          cs,
                                          _rows[i],
                                        );
                                      },
                                    );
                                  }

                                  final minW = constraints.maxWidth;
                                  final dataRows = <DataRow>[];
                                  for (var i = 0; i < _rows.length; i++) {
                                    final r = _rows[i];
                                    final alias =
                                        (r['branch_alias'] ?? '-').toString();
                                    final err = r['error']?.toString();
                                    final hasErr = err != null;
                                    dataRows.add(
                                      DataRow(
                                        color:
                                            WidgetStateProperty.resolveWith(
                                                (s) {
                                          if (s.contains(
                                            WidgetState.hovered,
                                          )) {
                                            return cs.primary
                                                .withValues(alpha: 0.06);
                                          }
                                          return i.isOdd
                                              ? cs.surfaceContainerHighest
                                                  .withValues(alpha: 0.45)
                                              : null;
                                        }),
                                        cells: [
                                          DataCell(
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  alias,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (hasErr)
                                                  Text(
                                                    err,
                                                    style: TextStyle(
                                                      color: cs.error,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              hasErr
                                                  ? '—'
                                                  : '${_cellInt(r, 'jual')}',
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              hasErr
                                                  ? '—'
                                                  : '${_cellInt(r, 'buyback')}',
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              hasErr
                                                  ? '—'
                                                  : '${_cellInt(r, 'service')}',
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              hasErr
                                                  ? '—'
                                                  : '${_cellInt(r, 'custom')}',
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      0,
                                      12,
                                      12,
                                    ),
                                    child: Material(
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
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          scrollDirection: Axis.horizontal,
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              minWidth: minW,
                                            ),
                                            child: SingleChildScrollView(
                                              physics:
                                                  const AlwaysScrollableScrollPhysics(),
                                              child: DataTable(
                                                headingRowColor:
                                                    WidgetStateProperty.all(
                                                  cs.surfaceContainerHigh,
                                                ),
                                                dataRowMinHeight: 44,
                                                dataRowMaxHeight: 64,
                                                columnSpacing: 12,
                                                horizontalMargin: 10,
                                                showCheckboxColumn: false,
                                                dividerThickness: 0.5,
                                                columns: [
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Alias',
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Jual',
                                                    ),
                                                    numeric: true,
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Buyback',
                                                    ),
                                                    numeric: true,
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Service',
                                                    ),
                                                    numeric: true,
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Custom',
                                                    ),
                                                    numeric: true,
                                                  ),
                                                ],
                                                rows: dataRows,
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
}

