import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/core/network/api_exceptions.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/manager_report_period_selector.dart';
import 'package:vanessa3/utils/business_calendar.dart';
import 'package:vanessa3/utils/kasir_report_print.dart';

/// Laporan keuangan kasir: pembayaran order + catatan keuangan toko (non-order).
class KasirReportsPage extends ConsumerStatefulWidget {
  const KasirReportsPage({super.key});

  @override
  ConsumerState<KasirReportsPage> createState() => _KasirReportsPageState();
}

String _paymentMethodLabel(String method) {
  switch (method.trim().toLowerCase()) {
    case 'cash':
      return 'Tunai';
    case 'transfer':
      return 'Transfer Bank';
    case 'qris':
      return 'QRIS';
    case 'ewallet':
    case 'e-wallet':
      return 'E-Wallet';
    default:
      return method.isEmpty ? '—' : method;
  }
}

class _KasirReportsPageState extends ConsumerState<KasirReportsPage> {
  bool _rangeMode = false;
  late DateTime _periodStart;
  late DateTime _periodEnd;

  bool _loading = true;
  String _error = '';

  Map<String, dynamic> _paymentSummary = {};
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _operational = [];

  @override
  void initState() {
    super.initState();
    _periodStart = BusinessCalendar.todayWibDateOnly();
    _periodEnd = _periodStart;
    _load();
  }

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  String _fmtMoney(num v) => NumberFormat.currency(
        locale: 'id_ID',
        symbol: 'Rp ',
        decimalDigits: 0,
      ).format(v);

  bool _entryIsIncome(Map<String, dynamic> e) =>
      e['entry_kind']?.toString() == 'income';

  String _branchLabel() {
    final s = ref.read(userStateProvider);
    for (final b in s.branches) {
      if (b['branch_id']?.toString() == s.branch.toString()) {
        return (b['alias'] ?? b['branch_name'] ?? b['name'] ?? s.branch)
            .toString();
      }
    }
    return s.branch.toString();
  }

  void _onPeriodChanged(DateTime start, DateTime end) {
    setState(() {
      _periodStart = managerReportDateOnly(start);
      _periodEnd = managerReportDateOnly(end);
    });
    _load();
  }

  Future<void> _load() async {
    final userState = ref.read(userStateProvider);
    final branch = userState.branch.trim();
    final userId = userState.userId;
    if (userId == null) {
      setState(() {
        _loading = false;
        _error = 'User belum login. Silakan login ulang.';
        _payments = [];
        _operational = [];
        _paymentSummary = {};
      });
      return;
    }
    if (branch.isEmpty) {
      setState(() {
        _loading = false;
        _error =
            'Cabang aktif tidak tersedia. Ganti cabang lewat profil lalu coba lagi.';
        _payments = [];
        _operational = [];
        _paymentSummary = {};
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final periodQ = managerReportPeriodQueryParams(_periodStart, _periodEnd);
      final scopeQ = <String, String>{
        'branch_id': branch,
        'user_id': userId.toString(),
      };
      final payQuery = <String, String>{...scopeQ, ...periodQ};
      final payRes = await ApiClient.get(
        '/payments/daily-summary',
        query: payQuery,
      );
      final opsRes = await ApiClient.get(
        '/store-operational',
        query: {...scopeQ, ...periodQ},
      );

      if (payRes.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = _apiMessage(payRes.body, payRes.statusCode, 'Gagal memuat pembayaran order');
        });
        return;
      }
      if (opsRes.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = _apiMessage(opsRes.body, opsRes.statusCode, 'Gagal memuat keuangan toko');
        });
        return;
      }

      final payDecoded = jsonDecode(payRes.body);
      final opsDecoded = jsonDecode(opsRes.body);

      final payments = <Map<String, dynamic>>[];
      if (payDecoded is Map) {
        final tx = payDecoded['transactions'];
        if (tx is List) {
          for (final e in tx) {
            if (e is Map) payments.add(Map<String, dynamic>.from(e));
          }
        }
      }

      final ops = <Map<String, dynamic>>[];
      if (opsDecoded is List) {
        for (final e in opsDecoded) {
          if (e is Map) ops.add(Map<String, dynamic>.from(e));
        }
      }

      final summary = payDecoded is Map
          ? Map<String, dynamic>.from(
              (payDecoded['summary'] as Map?)?.cast<String, dynamic>() ?? {},
            )
          : <String, dynamic>{};

      setState(() {
        _payments = payments;
        _operational = ops;
        _paymentSummary = summary;
        _loading = false;
      });
    } on UnauthorizedException catch (_) {
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  String _apiMessage(String body, int status, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final det = decoded['details']?.toString().trim();
        final err = decoded['error']?.toString().trim();
        if (det != null && det.isNotEmpty) return '$fallback: $det';
        if (err != null && err.isNotEmpty) return '$fallback: $err';
      }
    } catch (_) {}
    return '$fallback (HTTP $status)';
  }

  ({double income, double expense, double net}) _operationalTotals() {
    double income = 0;
    double expense = 0;
    for (final e in _operational) {
      final n = _toNum(e['amount']).toDouble();
      if (_entryIsIncome(e)) {
        income += n;
      } else {
        expense += n;
      }
    }
    return (income: income, expense: expense, net: income - expense);
  }

  String _paymentOrderLabel(Map<String, dynamic> p) {
    final n = (p['order_number'] ?? '').toString().trim();
    if (n.isNotEmpty) return n;
    final id = (p['order_id'] ?? '').toString().trim();
    if (id.isNotEmpty) return '#$id';
    return '—';
  }

  Future<void> _printReport() async {
    final us = ref.read(userStateProvider);
    final ops = _operationalTotals();
    await printKasirCombinedFinanceReport(
      context,
      periodTitle: managerReportPeriodTitle(_periodStart, _periodEnd),
      periodSlug: managerReportIsoDate(_periodStart),
      branchLabel: '${_branchLabel()} (${us.branch})',
      branchIdForLogo: us.branch.trim(),
      cashierLabel:
          '${us.username.isEmpty ? 'Kasir' : us.username}${us.userId != null ? ' · ID ${us.userId}' : ''}',
      paymentTransactionCount:
          int.tryParse(_paymentSummary['total_payments']?.toString() ?? '') ?? 0,
      paymentIncome: _toNum(_paymentSummary['income_amount']).toDouble(),
      paymentExpense: _toNum(_paymentSummary['expense_amount']).toDouble(),
      paymentNet: _toNum(_paymentSummary['net_amount']).toDouble(),
      operationalEntryCount: _operational.length,
      operationalIncome: ops.income,
      operationalExpense: ops.expense,
      operationalNet: ops.net,
      paymentRows: _payments,
      operationalRows: _operational,
    );
  }

  Widget _summaryCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color accent,
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
                Icon(icon, color: accent, size: 22),
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

  Widget _moneyLine(String label, num value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            _fmtMoney(value),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentsTable(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final slice = _payments.take(60).toList();
    if (slice.isEmpty) {
      return const Text('Tidak ada pembayaran order pada periode ini.');
    }
    final rows = <DataRow>[];
    for (var i = 0; i < slice.length; i++) {
      final p = slice[i];
      final orderType = (p['order_type'] ?? '—').toString();
      final isExpense = orderType == 'buyback';
      rows.add(
        DataRow(
          color: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.hovered)) {
              return cs.primary.withValues(alpha: 0.06);
            }
            return i.isOdd
                ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
                : null;
          }),
          cells: [
            DataCell(Text(_paymentOrderLabel(p))),
            DataCell(Text(orderType)),
            DataCell(
              Text(
                _paymentMethodLabel(
                  (p['payment_method'] ?? p['method'] ?? '').toString(),
                ),
              ),
            ),
            DataCell(
              Text(
                _fmtMoney(_toNum(p['amount'])),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isExpense ? Colors.red.shade700 : Colors.green.shade800,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final minW = math.max(c.maxWidth, 560.0);
        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minW),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(cs.surfaceContainerHigh),
                dataRowMinHeight: 40,
                columnSpacing: 12,
                horizontalMargin: 10,
                showCheckboxColumn: false,
                columns: [
                  DataColumn(label: dataTableColumnLabel('Nota')),
                  DataColumn(label: dataTableColumnLabel('Jenis')),
                  DataColumn(label: dataTableColumnLabel('Metode')),
                  DataColumn(
                    label: dataTableColumnLabel('Nominal'),
                    numeric: true,
                  ),
                ],
                rows: rows,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _operationalTable(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final timeFmt = DateFormat('d MMM HH:mm', 'id_ID');
    final slice = _operational.take(60).toList();
    if (slice.isEmpty) {
      return const Text('Tidak ada catatan keuangan toko pada periode ini.');
    }
    final rows = <DataRow>[];
    for (var i = 0; i < slice.length; i++) {
      final e = slice[i];
      final income = _entryIsIncome(e);
      final created = DateTime.tryParse(e['created_at']?.toString() ?? '');
      rows.add(
        DataRow(
          color: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.hovered)) {
              return cs.primary.withValues(alpha: 0.06);
            }
            return i.isOdd
                ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
                : null;
          }),
          cells: [
            DataCell(
              Text(
                created != null ? timeFmt.format(created.toLocal()) : '—',
              ),
            ),
            DataCell(Text(income ? 'Masuk' : 'Keluar')),
            DataCell(
              Text(
                (e['category'] ?? '—').toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DataCell(
              Text(
                _fmtMoney(_toNum(e['amount'])),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: income ? Colors.green.shade800 : Colors.red.shade700,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final minW = math.max(c.maxWidth, 520.0);
        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minW),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(cs.surfaceContainerHigh),
                dataRowMinHeight: 40,
                columnSpacing: 12,
                horizontalMargin: 10,
                showCheckboxColumn: false,
                columns: [
                  DataColumn(label: dataTableColumnLabel('Waktu')),
                  DataColumn(label: dataTableColumnLabel('Jenis')),
                  DataColumn(label: dataTableColumnLabel('Kategori')),
                  DataColumn(
                    label: dataTableColumnLabel('Nominal'),
                    numeric: true,
                  ),
                ],
                rows: rows,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userStateProvider);
    ref.listen(userStateProvider, (prev, next) {
      if (prev?.branch != next.branch || prev?.userId != next.userId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load();
        });
      }
    });

    final cashierLabel = user.username.isEmpty ? 'Kasir' : user.username;
    final scopeLabel =
        '${_branchLabel()} · $cashierLabel${user.userId != null ? ' (ID ${user.userId})' : ''}';

    final cs = Theme.of(context).colorScheme;
    final ops = _operationalTotals();
    final payIncome = _toNum(_paymentSummary['income_amount']);
    final payExpense = _toNum(_paymentSummary['expense_amount']);
    final payNet = _toNum(_paymentSummary['net_amount']);
    final grandIncome = payIncome + ops.income;
    final grandExpense = payExpense + ops.expense;
    final grandNet = payNet + ops.net;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Keuangan'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                scopeLabel,
                style: Theme.of(context).textTheme.labelSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        actions: [
          if (!_loading && _error.isEmpty)
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'Cetak / PDF',
              onPressed: _printReport,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'Gabungan pembayaran order dan keuangan toko (non-order) — hanya data Anda di cabang aktif.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 12),
                      ManagerReportPeriodSelector(
                        rangeMode: _rangeMode,
                        rangeStart: _periodStart,
                        rangeEnd: _periodEnd,
                        onRangeModeChanged: (v) => setState(() => _rangeMode = v),
                        onPeriodChanged: _onPeriodChanged,
                      ),
                      const SizedBox(height: 16),
                      _summaryCard(
                        context,
                        title: 'Gabungan periode',
                        icon: Icons.account_balance_wallet_outlined,
                        accent: cs.primary,
                        children: [
                          _moneyLine('Total masuk', grandIncome,
                              color: Colors.green.shade800),
                          _moneyLine('Total keluar', grandExpense,
                              color: Colors.red.shade700),
                          const Divider(height: 16),
                          _moneyLine(
                            'Saldo bersih',
                            grandNet,
                            color: grandNet >= 0
                                ? Colors.green.shade900
                                : Colors.red.shade900,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _summaryCard(
                        context,
                        title: 'Pembayaran order',
                        icon: Icons.receipt_long,
                        accent: Colors.green,
                        children: [
                          Text(
                            '${_paymentSummary['total_payments'] ?? 0} transaksi',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          _moneyLine('Masuk (jual / service / custom)', payIncome),
                          _moneyLine('Keluar (buyback)', payExpense,
                              color: Colors.red.shade700),
                          _moneyLine('Net', payNet),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _summaryCard(
                        context,
                        title: 'Keuangan toko (non-order)',
                        icon: Icons.storefront_outlined,
                        accent: Colors.deepOrange,
                        children: [
                          Text(
                            '${_operational.length} catatan',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          _moneyLine('Pemasukan', ops.income),
                          _moneyLine('Pengeluaran', ops.expense,
                              color: Colors.red.shade700),
                          _moneyLine('Net', ops.net),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Detail pembayaran order (${_payments.length})',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      _paymentsTable(context),
                      if (_payments.length > 60)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Menampilkan 60 transaksi pertama.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      const SizedBox(height: 20),
                      Text(
                        'Detail keuangan toko (${_operational.length})',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      _operationalTable(context),
                      if (_operational.length > 60)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Menampilkan 60 catatan pertama.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }
}
