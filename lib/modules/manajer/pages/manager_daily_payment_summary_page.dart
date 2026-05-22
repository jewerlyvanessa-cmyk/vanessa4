import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/branch_types.dart';
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
    this.branchTypeScope,
    this.globalScope = false,
  });

  final String appBarTitle;
  final String summarySubtitlePrefix;
  final IconData summaryLeadingIcon;
  final String? orderTypeFilter;

  /// Jika true: tampilkan nominal Rp per metode (cash / transfer / QRIS). Dipakai laporan penjualan.
  final bool showPaymentMethodNominals;

  /// Batasi cabang, mis. `toko` (selaras kartu penjualan/buyback global).
  final String? branchTypeScope;

  /// Semua cabang aktif (bukan hanya cabang di profil login); dipakai Owner/Manajer global.
  final bool globalScope;

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

  static bool _branchIsActive(Map<String, dynamic> b) {
    final s = (b['status'] ?? 'active').toString().trim().toLowerCase();
    return s.isEmpty || s == 'active';
  }

  Future<List<Map<String, dynamic>>> _fetchBranchesFromApi(String? typeScope) async {
    final qp = <String, String>{};
    final scope = typeScope?.trim().toLowerCase();
    if (scope != null && scope.isNotEmpty) {
      qp['branch_type'] = scope;
    }
    final uri = Uri.parse('${NetworkConfig.baseUrl}/branches').replace(
      queryParameters: qp.isEmpty ? null : qp,
    );
    final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
    if (resp.statusCode != 200) {
      throw Exception('Gagal memuat cabang (${resp.statusCode})');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in decoded) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      if (!_branchIsActive(m)) continue;
      if (scope != null &&
          scope.isNotEmpty &&
          !branchMatchesTypeScope(m['branch_type']?.toString(), scope)) {
        continue;
      }
      out.add(m);
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _resolveBranches() async {
    final typeScope = widget.branchTypeScope?.trim().toLowerCase();
    final hasTypeScope = typeScope != null && typeScope.isNotEmpty;

    if (widget.globalScope) {
      return _fetchBranchesFromApi(hasTypeScope ? typeScope : null);
    }

    var branches = List<Map<String, dynamic>>.from(
      ref.read(userStateProvider).branches,
    );
    if (!hasTypeScope) return branches;

    final typed = await _fetchBranchesFromApi(typeScope);
    final allowedIds = branchIdsForTypeScope(typed);
    final byId = <String, Map<String, dynamic>>{
      for (final t in typed)
        if ((t['branch_id']?.toString().trim() ?? '').isNotEmpty)
          t['branch_id']!.toString().trim(): t,
    };
    branches = branches
        .where((b) {
          final id = b['branch_id']?.toString().trim() ?? '';
          return id.isNotEmpty && allowedIds.contains(id);
        })
        .map((b) {
          final id = b['branch_id']?.toString().trim() ?? '';
          final fromApi = byId[id];
          if (fromApi == null) return b;
          return {
            ...b,
            'name': fromApi['name'] ?? b['name'],
            'branch_type': fromApi['branch_type'],
          };
        })
        .toList();
    return branches;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final branches = await _resolveBranches();
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

  static const _tableHeaderStyle = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 11,
    height: 1.15,
  );

  Widget _tableCellPad(Widget child, {bool numeric = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Align(
        alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
        child: child,
      ),
    );
  }

  Widget _fittedTableMethodCell(
    ColorScheme cs,
    Map<String, dynamic> r,
    bool hasErr,
    String countKey,
    String amountKey,
  ) {
    if (hasErr) {
      return _tableCellPad(const Text('—'), numeric: true);
    }
    if (!widget.showPaymentMethodNominals) {
      return _tableCellPad(
        Text('${_cellInt(r, countKey)}'),
        numeric: true,
      );
    }
    return _tableCellPad(
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_cellInt(r, countKey)}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            Text(
              _fmtMoney(_cellNum(r, amountKey)),
              style: TextStyle(fontSize: 10, color: cs.primary),
            ),
          ],
        ),
      ),
      numeric: true,
    );
  }

  Widget _buildFittedBranchTable(ColorScheme cs) {
    final headerCells = <Widget>[
      _tableCellPad(
        Text('Cabang', style: _tableHeaderStyle.copyWith(color: cs.onSurface)),
      ),
      _tableCellPad(
        Text('Trx', style: _tableHeaderStyle.copyWith(color: cs.onSurface)),
        numeric: true,
      ),
      _tableCellPad(
        Text(
          widget.showPaymentMethodNominals ? 'Cash\n# / Rp' : 'Cash',
          style: _tableHeaderStyle.copyWith(color: cs.onSurface),
          textAlign: TextAlign.end,
        ),
        numeric: true,
      ),
      _tableCellPad(
        Text(
          widget.showPaymentMethodNominals ? 'TRF\n# / Rp' : 'TRF',
          style: _tableHeaderStyle.copyWith(color: cs.onSurface),
          textAlign: TextAlign.end,
        ),
        numeric: true,
      ),
      _tableCellPad(
        Text(
          widget.showPaymentMethodNominals ? 'QRIS\n# / Rp' : 'QRIS',
          style: _tableHeaderStyle.copyWith(color: cs.onSurface),
          textAlign: TextAlign.end,
        ),
        numeric: true,
      ),
      _tableCellPad(
        Text('Total', style: _tableHeaderStyle.copyWith(color: cs.onSurface)),
        numeric: true,
      ),
    ];

    final dataTableRows = <TableRow>[];
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      final name = (r['branch_name'] ?? '-').toString();
      final err = r['error']?.toString();
      final hasErr = err != null;
      final totalAmount = _cellNum(r, 'total_amount');

      dataTableRows.add(
        TableRow(
          decoration: BoxDecoration(
            color: i.isOdd
                ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
                : null,
          ),
          children: [
            _tableCellPad(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (hasErr)
                    Text(
                      err,
                      style: TextStyle(color: cs.error, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            _tableCellPad(
              Text(hasErr ? '—' : '${_cellInt(r, 'total_payments')}'),
              numeric: true,
            ),
            _fittedTableMethodCell(
              cs,
              r,
              hasErr,
              'cash_payments',
              'cash_amount',
            ),
            _fittedTableMethodCell(
              cs,
              r,
              hasErr,
              'transfer_payments',
              'transfer_amount',
            ),
            _fittedTableMethodCell(
              cs,
              r,
              hasErr,
              'qris_payments',
              'qris_amount',
            ),
            _tableCellPad(
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  hasErr ? '—' : _fmtMoney(totalAmount),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
              numeric: true,
            ),
          ],
        ),
      );
    }

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.5),
        1: FlexColumnWidth(0.5),
        2: FlexColumnWidth(1.05),
        3: FlexColumnWidth(1.05),
        4: FlexColumnWidth(1.05),
        5: FlexColumnWidth(1.15),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.35),
          width: 0.5,
        ),
      ),
      children: [
        TableRow(
          decoration: BoxDecoration(color: cs.surfaceContainerHigh),
          children: headerCells,
        ),
        ...dataTableRows,
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
                                  final compactBreakpoint =
                                      widget.showPaymentMethodNominals
                                          ? 720.0
                                          : 560.0;
                                  final useCompact =
                                      constraints.maxWidth <
                                      compactBreakpoint;

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
                                      clipBehavior: Clip.none,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 4,
                                        ),
                                        child: _buildFittedBranchTable(cs),
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
