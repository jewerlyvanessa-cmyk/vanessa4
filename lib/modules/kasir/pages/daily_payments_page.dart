import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/business_calendar.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/utils/kasir_report_print.dart';
import 'package:vanessa3/utils/kasir_scope_filter.dart';

class DailyPaymentsPage extends ConsumerStatefulWidget {
  const DailyPaymentsPage({super.key});

  @override
  ConsumerState<DailyPaymentsPage> createState() => _DailyPaymentsPageState();
}

class _DailyPaymentsPageState extends ConsumerState<DailyPaymentsPage> {
  List<dynamic> _dailyPayments = [];
  Map<String, dynamic> _summary = {};
  bool _isLoading = true;
  String _error = '';
  DateTime _selectedDate = BusinessCalendar.todayWibDateOnly();

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  String _displayOrderRef(Map<String, dynamic> m) {
    final n = (m['order_number'] ?? '').toString().trim();
    if (n.isNotEmpty) return n;
    final id = (m['order_id'] ?? '').toString().trim();
    if (id.isNotEmpty) return '#$id';
    return '—';
  }

  String? _normalizeUrl(dynamic raw) {
    final s = raw?.toString().trim();
    if (s == null || s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    if (s.startsWith('/')) return '${NetworkConfig.baseUrl}$s';
    return '${NetworkConfig.baseUrl}/uploads/$s';
  }

  String? _extractProofUrlFromNotes(dynamic rawNotes) {
    final notes = rawNotes?.toString() ?? '';
    if (notes.trim().isEmpty) return null;
    final m = RegExp(r'^\s*Bukti:\s*(\S+)\s*$', multiLine: true).firstMatch(notes);
    if (m == null) return null;
    return m.group(1);
  }

  Widget _moneyRow(
    BuildContext context, {
    required String label,
    required num value,
    required Color color,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        Text(
          'Rp ${NumberFormat('#,###', 'id_ID').format(value)}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _paymentMethodBreakdownTable(
    BuildContext context,
    Map<String, dynamic> byMethod,
  ) {
    final cs = Theme.of(context).colorScheme;
    final keys = byMethod.keys.toList()..sort();
    num getNum(Map<String, dynamic>? m, String k) =>
        m == null ? 0 : _toNum(m[k]);

    Widget headerCell(String t, {TextAlign align = TextAlign.left}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          t,
          textAlign: align,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
        ),
      );
    }

    Widget moneyCell(num v, {Color? c}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          NumberFormat('#,###', 'id_ID').format(v),
          textAlign: TextAlign.right,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: c ?? cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.2),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1),
          3: FlexColumnWidth(1),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              headerCell('Metode'),
              headerCell('Masuk', align: TextAlign.right),
              headerCell('Keluar', align: TextAlign.right),
              headerCell('Net', align: TextAlign.right),
            ],
          ),
          for (final k in keys)
            () {
              final raw = byMethod[k];
              final breakdown = raw is Map
                  ? Map<String, dynamic>.from(raw)
                  : null;
              final income = breakdown != null ? getNum(breakdown, 'income') : _toNum(raw);
              final expense = breakdown != null ? getNum(breakdown, 'expense') : 0;
              final net = breakdown != null ? getNum(breakdown, 'net') : income;
              return TableRow(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      _getPaymentMethodName(k),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  moneyCell(income, c: Colors.green.shade700),
                  moneyCell(expense, c: Colors.red.shade700),
                  moneyCell(net, c: cs.primary),
                ],
              );
            }(),
        ],
      ),
    );
  }

  void _showPaymentDetail(BuildContext context, Map<String, dynamic> payment) {
    final method = (payment['payment_method'] ?? '').toString().trim();
    final isCash = method == 'cash';
    final proofUrl = _normalizeUrl(
      payment['proof_url'] ?? _extractProofUrlFromNotes(payment['notes']),
    );
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Detail Pembayaran #${payment['payment_id'] ?? '-'}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow('Nomor order', _displayOrderRef(payment)),
                _detailRow('Customer', '${payment['customer_name'] ?? '-'}'),
                _detailRow(
                  'Metode',
                  _getPaymentMethodName(
                    (payment['payment_method'] ?? '').toString(),
                  ),
                ),
                _detailRow(
                  'Nominal',
                  'Rp ${NumberFormat('#,###', 'id_ID').format(_toNum(payment['amount']))}',
                ),
                _detailRow('Status', '${payment['status'] ?? '-'}'),
                if ((payment['created_at'] ?? '').toString().isNotEmpty)
                  _detailRow('Waktu', '${payment['created_at']}'),
                if ((payment['notes'] ?? '').toString().trim().isNotEmpty)
                  _detailRow('Catatan', '${payment['notes']}'),
                if (!isCash && proofUrl != null) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Bukti Pembayaran',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      proofUrl,
                      height: 220,
                      width: 220,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 220,
                          width: 220,
                          color: Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: const Text('Gagal memuat bukti'),
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return SizedBox(
                          height: 220,
                          width: 220,
                          child: Center(
                            child: CircularProgressIndicator(
                              value: (loadingProgress.expectedTotalBytes != null &&
                                      loadingProgress.expectedTotalBytes! > 0)
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadDailyPayments();
  }

  Future<void> _loadDailyPayments() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final userId = userState.userId;
      final branchId = userState.branch.trim();
      if (userId == null) {
        setState(() {
          _error = 'User belum login. Silakan login ulang.';
          _isLoading = false;
        });
        return;
      }
      if (branchId.isEmpty) {
        setState(() {
          _error =
              'Cabang aktif tidak tersedia. Ganti cabang lewat profil lalu coba lagi.';
          _isLoading = false;
        });
        return;
      }

      final uid = userId;
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      // Pembayaran completed: cabang aktif + yang divalidasi user login (validated_by).
      final response = await ApiClient.get(
        '/payments/daily-summary',
        query: {
          'branch_id': branchId,
          'user_id': uid.toString(),
          'date': dateStr,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          final tx = (data['transactions'] as List?) ?? [];
          // Cadangan klien: production kadang masih mengembalikan seluruh cabang.
          final filtered = filterKasirPaymentsForUser(tx, uid);
          _dailyPayments = filtered;
          _summary = summarizeKasirPaymentTransactions(filtered);
          // Ringkasan metode pembayaran: pakai rule yang sama seperti total.
          // - jual/service/custom = masuk
          // - buyback = keluar
          final Map<String, Map<String, num>> byMethodBreakdown = {};
          for (final tx in _dailyPayments) {
            if (tx is! Map) continue;
            final method = (tx['payment_method'] ?? '').toString().trim();
            if (method.isEmpty) continue;
            final orderType = (tx['order_type'] ?? '').toString().trim();
            final rawAmount = tx['amount'];
            final amount = rawAmount is num
                ? rawAmount
                : num.tryParse(rawAmount?.toString() ?? '') ?? 0;

            final bucket = byMethodBreakdown.putIfAbsent(method, () {
              return {'income': 0, 'expense': 0, 'net': 0};
            });

            final isExpense = orderType == 'buyback';
            if (isExpense) {
              bucket['expense'] = (bucket['expense'] ?? 0) + amount;
            } else {
              // Default: treat as income (jual/service/custom)
              bucket['income'] = (bucket['income'] ?? 0) + amount;
            }
            bucket['net'] = (bucket['income'] ?? 0) - (bucket['expense'] ?? 0);
          }
          _summary['payment_methods'] = byMethodBreakdown;
          _isLoading = false;
        });
      } else {
        var msg = 'Gagal memuat data pembayaran harian';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            final details = decoded['details']?.toString().trim();
            final err = decoded['error']?.toString().trim();
            if (details != null && details.isNotEmpty) {
              msg = details;
            } else if (err != null && err.isNotEmpty) {
              msg = err;
            }
          }
        } catch (_) {}
        setState(() {
          _error = '$msg (HTTP ${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: BusinessCalendar.todayWibDateOnly(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadDailyPayments();
    }
  }

  String _branchLabel() {
    final s = ref.read(userStateProvider);
    for (final b in s.branches) {
      if (b['branch_id']?.toString() == s.branch.toString()) {
        return (b['name'] ?? b['branch_id']).toString();
      }
    }
    return s.branch.toString();
  }

  Future<void> _printDailyPaymentsReport() async {
    final us = ref.read(userStateProvider);
    final dateLabel =
        DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(_selectedDate);
    final dateSlug = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final paymentRows = _dailyPayments
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final totalPayments =
        int.tryParse(_summary['total_payments']?.toString() ?? '') ?? 0;
    final income = _toNum(_summary['income_amount']).toDouble();
    final expense = _toNum(_summary['expense_amount']).toDouble();
    final net = _toNum(_summary['net_amount']).toDouble();
    final methodsRaw = _summary['payment_methods'];
    final methods = methodsRaw is Map
        ? Map<String, dynamic>.from(methodsRaw)
        : <String, dynamic>{};

    await printKasirDailyPaymentsReport(
      context,
      reportDateLabel: dateLabel,
      reportDateSlug: dateSlug,
      branchLabel: '${_branchLabel()} (${us.branch})',
      branchIdForLogo: us.branch.trim(),
      cashierLabel:
          '${us.username.isEmpty ? 'Kasir' : us.username}${us.userId != null ? ' · ID ${us.userId}' : ''}',
      paymentTransactionCount: totalPayments,
      incomeAmount: income,
      expenseAmount: expense,
      netAmount: net,
      paymentMethods: methods,
      paymentRows: paymentRows,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isServerHealthy = ref.watch(healthCheckProvider);
    final user = ref.watch(userStateProvider);
    ref.listen(userStateProvider, (prev, next) {
      if (prev?.branch != next.branch || prev?.userId != next.userId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadDailyPayments();
        });
      }
    });

    final cashierLabel = user.username.isEmpty ? 'Kasir' : user.username;
    final scopeLabel =
        '${_branchLabel()} · $cashierLabel${user.userId != null ? ' (ID ${user.userId})' : ''}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pembayaran Hari Ini'),
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
          Row(
            children: [
              Icon(
                isServerHealthy ? Icons.wifi : Icons.wifi_off,
                color: isServerHealthy ? Colors.green : Colors.red,
                size: 20,
              ),
              const SizedBox(width: 4),
              const Text('Live', style: TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectDate,
            tooltip: 'Pilih Tanggal',
          ),
          if (!_isLoading && _error.isEmpty)
            IconButton(
              icon: const Icon(Icons.print),
              onPressed: _printDailyPaymentsReport,
              tooltip: 'Cetak Laporan Harian',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDailyPayments,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadDailyPayments,
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Date Header
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.calendar_today),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat(
                              'EEEE, dd MMMM yyyy',
                              'id_ID',
                            ).format(_selectedDate),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Hanya pembayaran Anda di cabang ini',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade700,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                // Summary Cards
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 4,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Total Transaksi',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: Colors.grey.shade700,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${_summary['total_payments'] ?? 0}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 8,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Pendapatan / Pengeluaran',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: Colors.grey.shade700,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Net: Rp ${NumberFormat('#,###', 'id_ID').format(_toNum(_summary['net_amount']))}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(color: Colors.blueGrey),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 10),
                                  _moneyRow(
                                    context,
                                    label: 'Masuk',
                                    value: _toNum(_summary['income_amount']),
                                    color: Colors.green.shade700,
                                  ),
                                  const SizedBox(height: 6),
                                  _moneyRow(
                                    context,
                                    label: 'Keluar',
                                    value: _toNum(_summary['expense_amount']),
                                    color: Colors.red.shade700,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Payment Methods Summary
                if (_summary['payment_methods'] != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Ringkasan Metode Pembayaran'),
                            const SizedBox(height: 12),
                            _paymentMethodBreakdownTable(
                              context,
                              Map<String, dynamic>.from(
                                _summary['payment_methods'] as Map,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Payments List
                Expanded(
                  child: _dailyPayments.isEmpty
                      ? const Center(
                          child: Text('Tidak ada pembayaran pada tanggal ini'),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final cs = Theme.of(context).colorScheme;
                            final minW = constraints.maxWidth;
                            final rows = <DataRow>[];
                            for (var i = 0; i < _dailyPayments.length; i++) {
                              final payment = _dailyPayments[i];
                              final m = Map<String, dynamic>.from(
                                payment as Map,
                              );
                              rows.add(
                                DataRow(
                                  color: WidgetStateProperty.resolveWith((s) {
                                    if (s.contains(WidgetState.hovered)) {
                                      return cs.primary.withValues(alpha: 0.06);
                                    }
                                    return i.isOdd
                                        ? cs.surfaceContainerHighest
                                            .withValues(alpha: 0.45)
                                        : null;
                                  }),
                                  onSelectChanged: (_) => _showPaymentDetail(
                                    context,
                                    m,
                                  ),
                                  cells: [
                                    DataCell(
                                      Text(
                                        _displayOrderRef(m),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        (m['order_type'] ?? '—').toString(),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '${m['customer_name'] ?? 'N/A'}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        _getPaymentMethodName(
                                          (m['payment_method'] ?? '')
                                              .toString(),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        'Rp ${NumberFormat('#,###', 'id_ID').format(_toNum(m['amount']))}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: cs.primary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(minWidth: minW),
                                      child: DataTable(
                                        headingRowColor: WidgetStateProperty.all(
                                          cs.surfaceContainerHigh,
                                        ),
dataRowMinHeight: 44,
                                        dataRowMaxHeight: 64,
                                        columnSpacing: 10,
                                        horizontalMargin: 10,
                                        showCheckboxColumn: false,
                                        dividerThickness: 0.5,
                                        columns: [
                                          DataColumn(label: dataTableColumnLabel('Nomor order')),
                                          DataColumn(label: dataTableColumnLabel('Jenis')),
                                          DataColumn(label: dataTableColumnLabel('Customer')),
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
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  String _getPaymentMethodName(String method) {
    switch (method) {
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
        return method;
    }
  }
}
