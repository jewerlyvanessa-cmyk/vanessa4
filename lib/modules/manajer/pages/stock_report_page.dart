import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/modules/stockist/widgets/stock_inventory_grouped_table.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/shared_widgets/manager_report_period_selector.dart';
import 'package:vanessa3/utils/manager_report_print.dart';

/// Rekap stok per jenis (non-buyback) + buyback terpisah.
/// Mode **Gabungan** = seluruh cabang; mode **Per cabang** = rincian per toko.
class StockReportPage extends ConsumerStatefulWidget {
  const StockReportPage({super.key});

  @override
  ConsumerState<StockReportPage> createState() => _StockReportPageState();
}

class _JenisAggRow {
  _JenisAggRow({required this.jenis, required this.sku, required this.qty});

  final String jenis;
  final int sku;
  final int qty;

  Map<String, dynamic> toMap() => {
        'jenis': jenis,
        'sku': sku,
        'qty': qty,
      };
}

class _BranchJenisSnapshot {
  const _BranchJenisSnapshot({
    required this.branchId,
    required this.alias,
    required this.rowsStok,
    required this.rowsBuyback,
    this.error,
  });

  final String branchId;
  final String alias;
  final List<Map<String, dynamic>> rowsStok;
  final List<Map<String, dynamic>> rowsBuyback;
  final String? error;
}

class _StockReportPageState extends ConsumerState<StockReportPage> {
  static const int _kModeGabungan = 0;
  static const int _kModePerCabang = 1;

  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _rowsStokByJenis = const [];
  List<Map<String, dynamic>> _rowsBuybackByJenis = const [];
  List<String> _branchLoadErrors = const [];
  List<_BranchJenisSnapshot> _perBranch = const [];
  int _viewMode = _kModeGabungan;
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

  void _onReportPeriodChanged(DateTime start, DateTime end) {
    setState(() {
      _periodStart = managerReportDateOnly(start);
      _periodEnd = managerReportDateOnly(end);
    });
  }

  Future<void> _printPdf() async {
    final gabungan = _viewMode == _kModeGabungan;
    final branches = gabungan
        ? null
        : _perBranch
            .map(
              (b) => StockReportBranchPdfSection(
                name: b.alias,
                error: b.error,
                rowsStok: List<Map<String, dynamic>>.from(b.rowsStok),
                rowsBuyback: List<Map<String, dynamic>>.from(b.rowsBuyback),
              ),
            )
            .toList();
    await printManagerStockReportPdf(
      context,
      periodStart: _periodStart,
      periodEnd: _periodEnd,
      periodTitle: managerReportPeriodTitle(_periodStart, _periodEnd),
      periodSubtitle:
          managerReportPeriodShortSubtitle(_periodStart, _periodEnd),
      gabunganMode: gabungan,
      rowsStokByJenis: List<Map<String, dynamic>>.from(_rowsStokByJenis),
      rowsBuybackByJenis: List<Map<String, dynamic>>.from(_rowsBuybackByJenis),
      branchSections: branches,
    );
  }

  static String _normStatus(dynamic s) =>
      (s ?? '').toString().trim().toLowerCase();

  static int _parseQty(Map<String, dynamic> m) {
    final q = m['quantity'] ?? m['qty'];
    if (q is int) return q;
    if (q is num) return q.round();
    return int.tryParse(q?.toString().trim() ?? '') ?? 0;
  }

  static int _cellInt(Map<String, dynamic> r, String k) {
    final v = r[k];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static Map<String, _JenisAggRow> _emptyAgg() => {};

  void _addItem(Map<String, dynamic> m, Map<String, _JenisAggRow> agg) {
    final jenis = stockItemJenisLabel(m);
    final q = _parseQty(m);
    final cur = agg[jenis];
    if (cur == null) {
      agg[jenis] = _JenisAggRow(jenis: jenis, sku: 1, qty: q);
    } else {
      agg[jenis] = _JenisAggRow(
        jenis: jenis,
        sku: cur.sku + 1,
        qty: cur.qty + q,
      );
    }
  }

  List<Map<String, dynamic>> _sortedAggRows(Map<String, _JenisAggRow> agg) {
    final keys = agg.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [for (final k in keys) agg[k]!.toMap()];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
      _branchLoadErrors = const [];
    });

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final branches = ref.read(userStateProvider).branches;

      final aggStok = _emptyAgg();
      final aggBb = _emptyAgg();
      final branchErrors = <String>[];
      final perBranchList = <_BranchJenisSnapshot>[];

      for (final b in branches) {
        final branchId = b['branch_id']?.toString() ?? '';
        final alias = (b['alias']?.toString().trim().isNotEmpty == true)
            ? b['alias'].toString().trim()
            : (b['name'] ?? branchId).toString();
        if (branchId.isEmpty) continue;

        final locStok = _emptyAgg();
        final locBb = _emptyAgg();

        final uri = Uri.parse('$baseUrl/items').replace(
          queryParameters: {
            'branch_id': branchId,
            'limit': '5000',
          },
        );
        final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
        if (resp.statusCode != 200) {
          branchErrors.add('$alias: HTTP ${resp.statusCode}');
          perBranchList.add(
            _BranchJenisSnapshot(
              branchId: branchId,
              alias: alias,
              rowsStok: const [],
              rowsBuyback: const [],
              error: 'HTTP ${resp.statusCode}',
            ),
          );
          continue;
        }

        final decoded = jsonDecode(resp.body);
        if (decoded is! List) {
          branchErrors.add('$alias: respons tidak valid');
          perBranchList.add(
            _BranchJenisSnapshot(
              branchId: branchId,
              alias: alias,
              rowsStok: const [],
              rowsBuyback: const [],
              error: 'Respons tidak valid',
            ),
          );
          continue;
        }

        for (final it in decoded) {
          if (it is! Map) continue;
          final m = Map<String, dynamic>.from(it);
          if (_normStatus(m['status']) == 'buyback') {
            _addItem(m, aggBb);
            _addItem(m, locBb);
          } else {
            _addItem(m, aggStok);
            _addItem(m, locStok);
          }
        }

        perBranchList.add(
          _BranchJenisSnapshot(
            branchId: branchId,
            alias: alias,
            rowsStok: _sortedAggRows(locStok),
            rowsBuyback: _sortedAggRows(locBb),
          ),
        );
      }

      final sortedBranches = [...perBranchList]..sort((a, b) {
          if (a.error != null && b.error == null) return 1;
          if (a.error == null && b.error != null) return -1;
          final ta = _sumSku(a.rowsStok) + _sumSku(a.rowsBuyback);
          final tb = _sumSku(b.rowsStok) + _sumSku(b.rowsBuyback);
          return tb.compareTo(ta);
        });

      if (!mounted) return;
      setState(() {
        _rowsStokByJenis = _sortedAggRows(aggStok);
        _rowsBuybackByJenis = _sortedAggRows(aggBb);
        _branchLoadErrors = branchErrors;
        _perBranch = sortedBranches;
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

  int _sumSku(List<Map<String, dynamic>> rows) =>
      rows.fold(0, (a, r) => a + _cellInt(r, 'sku'));

  int _sumQty(List<Map<String, dynamic>> rows) =>
      rows.fold(0, (a, r) => a + _cellInt(r, 'qty'));

  Widget _metricChip(
    ColorScheme cs, {
    required String label,
    required int value,
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
              '$value',
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

  Widget _buildCompactJenisCard(ColorScheme cs, Map<String, dynamic> r) {
    final jenis = (r['jenis'] ?? '-').toString();
    final sku = _cellInt(r, 'sku');
    final qty = _cellInt(r, 'qty');

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
              jenis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: AppTypography.section,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _metricChip(cs, label: 'SKU', value: sku),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metricChip(cs, label: 'Qty', value: qty),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _jenisTableMaterial({
    required ColorScheme cs,
    required double minW,
    required List<DataRow> dataRows,
  }) {
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
      child: Scrollbar(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minW),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  cs.surfaceContainerHigh,
                ),
                dataRowMinHeight: 44,
                dataRowMaxHeight: 64,
                columnSpacing: 12,
                horizontalMargin: 10,
                showCheckboxColumn: false,
                dividerThickness: 0.5,
                columns: [
                  DataColumn(label: dataTableColumnLabel('Jenis')),
                  DataColumn(
                    label: dataTableColumnLabel('SKU'),
                    numeric: true,
                  ),
                  DataColumn(
                    label: dataTableColumnLabel('Qty'),
                    numeric: true,
                  ),
                ],
                rows: dataRows,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<DataRow> _buildDataRows(ColorScheme cs, List<Map<String, dynamic>> rows) {
    final dataRows = <DataRow>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      dataRows.add(
        DataRow(
          color: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.hovered)) {
              return cs.primary.withValues(alpha: 0.06);
            }
            return i.isOdd
                ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
                : null;
          }),
          cells: [
            DataCell(
              Text(
                (r['jenis'] ?? '-').toString(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            DataCell(Text('${_cellInt(r, 'sku')}')),
            DataCell(Text('${_cellInt(r, 'qty')}')),
          ],
        ),
      );
    }
    return dataRows;
  }

  Widget _jenisSection({
    required BuildContext context,
    required ColorScheme cs,
    required List<Map<String, dynamic>> rows,
    required String emptyText,
  }) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            emptyText,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const compactBreakpoint = 560.0;
        final useCompact = constraints.maxWidth < compactBreakpoint;
        final minW = constraints.maxWidth;

        if (useCompact) {
          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) =>
                _buildCompactJenisCard(cs, rows[i]),
          );
        }

        return _jenisTableMaterial(
          cs: cs,
          minW: minW,
          dataRows: _buildDataRows(cs, rows),
        );
      },
    );
  }

  Widget _sectionHeading({
    required BuildContext context,
    required ColorScheme cs,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _branchSummaryTable(ColorScheme cs) {
    if (_perBranch.isEmpty) {
      return const SizedBox.shrink();
    }
    final rows = <DataRow>[];
    for (var i = 0; i < _perBranch.length; i++) {
      final b = _perBranch[i];
      final err = b.error;
      final skuS = _sumSku(b.rowsStok);
      final qtyS = _sumQty(b.rowsStok);
      final skuB = _sumSku(b.rowsBuyback);
      final qtyB = _sumQty(b.rowsBuyback);
      rows.add(
        DataRow(
          color: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.hovered)) {
              return cs.primary.withValues(alpha: 0.06);
            }
            return i.isOdd
                ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
                : null;
          }),
          cells: [
            DataCell(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    b.alias,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (err != null)
                    Text(
                      err,
                      style: TextStyle(color: cs.error, fontSize: 11),
                    ),
                ],
              ),
            ),
            DataCell(Text(err != null ? '—' : '$skuS')),
            DataCell(Text(err != null ? '—' : '$qtyS')),
            DataCell(Text(err != null ? '—' : '$skuB')),
            DataCell(Text(err != null ? '—' : '$qtyB')),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final minW = c.maxWidth;
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
          child: Scrollbar(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: minW),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    cs.surfaceContainerHigh,
                  ),
                  dataRowMinHeight: 44,
                  dataRowMaxHeight: 72,
                  columnSpacing: 10,
                  horizontalMargin: 8,
                  showCheckboxColumn: false,
                  dividerThickness: 0.5,
                  columns: [
                    DataColumn(label: dataTableColumnLabel('Cabang')),
                    DataColumn(
                      label: dataTableColumnLabel('SKU stok'),
                      numeric: true,
                    ),
                    DataColumn(
                      label: dataTableColumnLabel('Qty stok'),
                      numeric: true,
                    ),
                    DataColumn(
                      label: dataTableColumnLabel('SKU BB'),
                      numeric: true,
                    ),
                    DataColumn(
                      label: dataTableColumnLabel('Qty BB'),
                      numeric: true,
                    ),
                  ],
                  rows: rows,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _perCabangBody(BuildContext context, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeading(
          context: context,
          cs: cs,
          title: 'Ringkasan per cabang',
          subtitle:
              'Total SKU dan qty stok (non-buyback) serta buyback per toko.',
          icon: Icons.table_rows,
        ),
        _branchSummaryTable(cs),
        const SizedBox(height: 24),
        _sectionHeading(
          context: context,
          cs: cs,
          title: 'Rincian per cabang',
          subtitle: 'Buka setiap cabang untuk rekap per jenis (stok & buyback).',
          icon: Icons.store_mall_directory_outlined,
        ),
        ..._perBranch.map((b) {
          final skuS = _sumSku(b.rowsStok);
          final qtyS = _sumQty(b.rowsStok);
          final skuBb = _sumSku(b.rowsBuyback);
          final qtyBb = _sumQty(b.rowsBuyback);
          final err = b.error;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              elevation: 0,
              color: cs.surfaceContainerLow.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                key: PageStorageKey('branch_${b.branchId}'),
                initiallyExpanded: _perBranch.length <= 3,
                leading: Icon(
                  err != null ? Icons.error_outline : Icons.storefront_outlined,
                  color: err != null ? cs.error : cs.primary,
                ),
                title: Text(
                  b.alias,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: err != null
                    ? Text(err, style: TextStyle(color: cs.error, fontSize: 12))
                    : Text(
                        'Stok SKU $skuS • Qty $qtyS  ·  '
                        'Buyback SKU $skuBb • Qty $qtyBb',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                children: err != null
                    ? [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Data cabang ini tidak bisa dimuat.',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ),
                      ]
                    : [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Text(
                            'Stok per jenis',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _jenisSection(
                            context: context,
                            cs: cs,
                            rows: b.rowsStok,
                            emptyText: 'Tidak ada stok (non-buyback).',
                          ),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Text(
                            'Buyback per jenis',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                          child: _jenisSection(
                            context: context,
                            cs: cs,
                            rows: b.rowsBuyback,
                            emptyText: 'Tidak ada buyback.',
                          ),
                        ),
                      ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _gabunganBody(BuildContext context, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeading(
          context: context,
          cs: cs,
          title: 'Rekap stok per jenis',
          subtitle:
              'Semua item kecuali status buyback, digabung dari seluruh cabang.',
          icon: Icons.pie_chart_outline,
        ),
        _jenisSection(
          context: context,
          cs: cs,
          rows: _rowsStokByJenis,
          emptyText: 'Tidak ada stok (non-buyback).',
        ),
        const SizedBox(height: 28),
        Divider(
          height: 1,
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 20),
        _sectionHeading(
          context: context,
          cs: cs,
          title: 'Buyback',
          subtitle:
              'Hanya item dengan status buyback, per jenis, terpisah dari rekap stok.',
          icon: Icons.currency_exchange,
        ),
        _jenisSection(
          context: context,
          cs: cs,
          rows: _rowsBuybackByJenis,
          emptyText: 'Tidak ada item buyback.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        managerReportPeriodTitle(_periodStart, _periodEnd);
    final periodHint =
        managerReportPeriodShortSubtitle(_periodStart, _periodEnd);
    final cs = Theme.of(context).colorScheme;

    final skuStok = _sumSku(_rowsStokByJenis);
    final qtyStok = _sumQty(_rowsStokByJenis);
    final skuBb = _sumSku(_rowsBuybackByJenis);
    final qtyBb = _sumQty(_rowsBuybackByJenis);
    final nCabang = ref.watch(userStateProvider).branches.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Stok'),
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
                        onRangeModeChanged: (v) =>
                            setState(() => _rangeMode = v),
                        onPeriodChanged: _onReportPeriodChanged,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Card(
                        child: ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text(dateLabel),
                          subtitle: Text(
                            '$periodHint • $nCabang cabang • '
                            'Stok: SKU $skuStok / Qty $qtyStok'
                            ' • Buyback: SKU $skuBb / Qty $qtyBb',
                          ),
                          trailing: Chip(
                            label: Text(
                              '${_rowsStokByJenis.length + _rowsBuybackByJenis.length}',
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Material(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 20,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Angka stok adalah snapshot inventori saat ini. '
                                  'Periode di atas menyamakan tampilan dengan laporan lain; '
                                  'data item tidak diubah menurut tanggal.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: SegmentedButton<int>(
                        segments: const [
                          ButtonSegment<int>(
                            value: _kModeGabungan,
                            label: Text('Gabungan'),
                            icon: Icon(Icons.merge_type, size: 18),
                          ),
                          ButtonSegment<int>(
                            value: _kModePerCabang,
                            label: Text('Per cabang'),
                            icon: Icon(Icons.store_mall_directory_outlined, size: 18),
                          ),
                        ],
                        selected: {_viewMode},
                        onSelectionChanged: (s) {
                          setState(() => _viewMode = s.first);
                        },
                      ),
                    ),
                    if (_branchLoadErrors.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Material(
                          color: cs.errorContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'Beberapa cabang gagal dimuat:\n'
                              '${_branchLoadErrors.join('\n')}',
                              style: TextStyle(
                                color: cs.onErrorContainer,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight - 1,
                                ),
                                child: _viewMode == _kModeGabungan
                                    ? _gabunganBody(context, cs)
                                    : _perCabangBody(context, cs),
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
