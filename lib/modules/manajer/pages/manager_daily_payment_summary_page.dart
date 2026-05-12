import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/shared_widgets/manager_report_period_selector.dart';
import 'package:vanessa3/utils/manager_report_print.dart';

/// Ringkasan pembayaran harian per cabang (`GET /payments/daily-summary`).
/// Set [orderTypeFilter] ke mis. `buyback` untuk membatasi ke jenis order tersebut.
class ManagerDailyPaymentSummaryPage extends ConsumerStatefulWidget {
  const ManagerDailyPaymentSummaryPage({
    super.key,
    required this.appBarTitle,
    required this.summarySubtitlePrefix,
    this.summaryLeadingIcon = Icons.payments,
    this.orderTypeFilter,
    this.showPaymentMethodNominals = false,
  });

  final String appBarTitle;
  final String summarySubtitlePrefix;
  final IconData summaryLeadingIcon;
  final String? orderTypeFilter;

  /// Jika true: tampilkan nominal Rp per metode (cash / transfer / QRIS). Dipakai laporan penjualan.
  final bool showPaymentMethodNominals;

  @override
  ConsumerState<ManagerDailyPaymentSummaryPage> createState() =>
      _ManagerDailyPaymentSummaryPageState();
}

class _ManagerDailyPaymentSummaryPageState
    extends ConsumerState<ManagerDailyPaymentSummaryPage> {
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
    final slug =
        widget.orderTypeFilter?.trim().toLowerCase() == 'buyback'
            ? 'laporan_buyback'
            : 'laporan_penjualan';
    await printManagerPaymentSummaryPdf(
      context,
      periodStart: _periodStart,
      periodEnd: _periodEnd,
      reportTitle: widget.appBarTitle,
      periodTitle: managerReportPeriodTitle(_periodStart, _periodEnd),
      periodSubtitle:
          managerReportPeriodShortSubtitle(_periodStart, _periodEnd),
      rows: List<Map<String, dynamic>>.from(_rows),
      fileSlugPrefix: slug,
      branchIdForLogo: ref.read(userStateProvider).branch.trim(),
      includeMethodNominals: widget.showPaymentMethodNominals,
    );
  }

  String _fmtMoney(num v) {
    return NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(v);
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
        final name = (b['name'] ?? branchId).toString();
        if (branchId.isEmpty) return <String, dynamic>{};

        final qp = <String, String>{
          'branch_id': branchId,
          ...periodQp,
        };
        final ot = widget.orderTypeFilter?.trim();
        if (ot != null && ot.isNotEmpty) {
          qp['order_type'] = ot;
        }
        final uri = Uri.parse('$baseUrl/payments/daily-summary').replace(
          queryParameters: qp,
        );
        final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
        if (resp.statusCode != 200) {
          return <String, dynamic>{
            'branch_id': branchId,
            'branch_name': name,
            'error': '${resp.statusCode}',
          };
        }
        final decoded = jsonDecode(resp.body);
        if (decoded is! Map) {
          return <String, dynamic>{
            'branch_id': branchId,
            'branch_name': name,
            'error': 'invalid_response',
          };
        }
        final summary = decoded['summary'];
        if (summary is! Map) {
          return <String, dynamic>{
            'branch_id': branchId,
            'branch_name': name,
            'error': 'missing_summary',
          };
        }

        num toNum(dynamic v) => num.tryParse(v?.toString() ?? '') ?? 0;

        return <String, dynamic>{
          'branch_id': branchId,
          'branch_name': name,
          'total_payments': toNum(summary['total_payments']),
          'total_amount': toNum(summary['total_amount']),
          'cash_payments': toNum(summary['cash_payments']),
          'transfer_payments': toNum(summary['transfer_payments']),
          'qris_payments': toNum(summary['qris_payments']),
          'cash_amount': toNum(summary['cash_amount']),
          'transfer_amount': toNum(summary['transfer_amount']),
          'qris_amount': toNum(summary['qris_amount']),
        };
      }).toList();

      final results =
          (await Future.wait(futures)).where((m) => m.isNotEmpty).toList();

      results.sort((a, b) {
        final ar = num.tryParse(a['total_amount']?.toString() ?? '') ?? 0;
        final br = num.tryParse(b['total_amount']?.toString() ?? '') ?? 0;
        return br.compareTo(ar);
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

  static num _cellNum(Map<String, dynamic> r, String k) {
    final v = r[k];
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '') ?? 0;
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

  Widget _paymentMethodTableCell(
    ColorScheme cs,
    Map<String, dynamic> r,
    bool hasErr,
    String countKey,
    String amountKey,
  ) {
    if (hasErr) return const Text('—');
    if (!widget.showPaymentMethodNominals) {
      return Text('${_cellInt(r, countKey)}');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${_cellInt(r, countKey)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          _fmtMoney(_cellNum(r, amountKey)),
          style: TextStyle(fontSize: 11, color: cs.primary),
        ),
      ],
    );
  }

  Widget _compactMethodLine(
    ColorScheme cs,
    String label,
    Map<String, dynamic> r,
    String prefix,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_cellInt(r, '${prefix}_payments')} trx',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
              Text(
                _fmtMoney(_cellNum(r, '${prefix}_amount')),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: cs.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalMoneyBand(
    ColorScheme cs, {
    required num amount,
    required bool showDash,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Total',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ),
            Text(
              showDash ? '—' : _fmtMoney(amount),
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: cs.primary,
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
    final name = (r['branch_name'] ?? '-').toString();
    final err = r['error']?.toString();
    final hasErr = err != null;
    final totalAmt = _cellNum(r, 'total_amount');

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
              name,
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
            if (!widget.showPaymentMethodNominals || hasErr) ...[
              Row(
                children: [
                  Expanded(
                    child: _metricChip(
                      cs,
                      label: 'Trx',
                      value: _cellInt(r, 'total_payments'),
                      showDash: hasErr,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _metricChip(
                      cs,
                      label: 'Cash',
                      value: _cellInt(r, 'cash_payments'),
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
                      label: 'TRF',
                      value: _cellInt(r, 'transfer_payments'),
                      showDash: hasErr,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _metricChip(
                      cs,
                      label: 'QRIS',
                      value: _cellInt(r, 'qris_payments'),
                      showDash: hasErr,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _metricChip(
                      cs,
                      label: 'Trx',
                      value: _cellInt(r, 'total_payments'),
                      showDash: false,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _compactMethodLine(cs, 'Cash', r, 'cash'),
              _compactMethodLine(cs, 'Transfer', r, 'transfer'),
              _compactMethodLine(cs, 'QRIS', r, 'qris'),
            ],
            const SizedBox(height: 10),
            _totalMoneyBand(cs, amount: totalAmt, showDash: hasErr),
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
    final totalAll = _rows.fold<num>(0, (p, r) {
      final v = num.tryParse(r['total_amount']?.toString() ?? '') ?? 0;
      return p + v;
    });
    num sumBranchField(String key) => _rows.fold<num>(0, (p, r) {
          final err = r['error']?.toString();
          if (err != null && err.isNotEmpty) return p;
          return p + _cellNum(r, key);
        });
    final totalCashAmt = sumBranchField('cash_amount');
    final totalTrfAmt = sumBranchField('transfer_amount');
    final totalQrisAmt = sumBranchField('qris_amount');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.appBarTitle),
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
                          leading: Icon(widget.summaryLeadingIcon),
                          isThreeLine: widget.showPaymentMethodNominals,
                          title: Text(dateLabel),
                          subtitle: widget.showPaymentMethodNominals
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${widget.summarySubtitlePrefix} • ${_fmtMoney(totalAll)} • $periodHint',
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Gabungan metode · Cash ${_fmtMoney(totalCashAmt)} · '
                                      'TRF ${_fmtMoney(totalTrfAmt)} · QRIS ${_fmtMoney(totalQrisAmt)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  '${widget.summarySubtitlePrefix} • ${_fmtMoney(totalAll)} • $periodHint',
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
                                    final name =
                                        (r['branch_name'] ?? '-').toString();
                                    final err = r['error']?.toString();
                                    final hasErr = err != null;
                                    final totalAmount =
                                        _cellNum(r, 'total_amount');
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
                                                  name,
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
                                                  : '${_cellInt(r, 'total_payments')}',
                                            ),
                                          ),
                                          DataCell(
                                            _paymentMethodTableCell(
                                              cs,
                                              r,
                                              hasErr,
                                              'cash_payments',
                                              'cash_amount',
                                            ),
                                          ),
                                          DataCell(
                                            _paymentMethodTableCell(
                                              cs,
                                              r,
                                              hasErr,
                                              'transfer_payments',
                                              'transfer_amount',
                                            ),
                                          ),
                                          DataCell(
                                            _paymentMethodTableCell(
                                              cs,
                                              r,
                                              hasErr,
                                              'qris_payments',
                                              'qris_amount',
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              hasErr
                                                  ? '—'
                                                  : _fmtMoney(totalAmount),
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: cs.primary,
                                              ),
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
                                                dataRowMaxHeight:
                                                    widget.showPaymentMethodNominals
                                                        ? 72
                                                        : 64,
                                                columnSpacing: 12,
                                                horizontalMargin: 10,
                                                showCheckboxColumn: false,
                                                dividerThickness: 0.5,
                                                columns: [
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Cabang',
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Trx',
                                                    ),
                                                    numeric: true,
                                                  ),
                                                  DataColumn(
                                                    label: widget
                                                            .showPaymentMethodNominals
                                                        ? dataTableColumnLabel(
                                                            'Cash\n# / Rp',
                                                            numeric: true,
                                                          )
                                                        : dataTableColumnLabel(
                                                            'Cash',
                                                            numeric: true,
                                                          ),
                                                    numeric: true,
                                                  ),
                                                  DataColumn(
                                                    label: widget
                                                            .showPaymentMethodNominals
                                                        ? dataTableColumnLabel(
                                                            'TRF\n# / Rp',
                                                            numeric: true,
                                                          )
                                                        : dataTableColumnLabel(
                                                            'TRF',
                                                            numeric: true,
                                                          ),
                                                    numeric: true,
                                                  ),
                                                  DataColumn(
                                                    label: widget
                                                            .showPaymentMethodNominals
                                                        ? dataTableColumnLabel(
                                                            'QRIS\n# / Rp',
                                                            numeric: true,
                                                          )
                                                        : dataTableColumnLabel(
                                                            'QRIS',
                                                            numeric: true,
                                                          ),
                                                    numeric: true,
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel(
                                                      'Total',
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
