import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/kasir_report_print.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/business_calendar.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

class KasirReportsPage extends ConsumerStatefulWidget {
  const KasirReportsPage({super.key});

  @override
  ConsumerState<KasirReportsPage> createState() => _KasirReportsPageState();
}

String _kasirPaymentMethodLabel(String method) {
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
      return method.isEmpty ? '-' : method;
  }
}

/// Key = kode metode dari API; value = jumlah nominal.
Map<String, double> _aggregatePaymentAmountsByMethod(Iterable<dynamic> payments) {
  final map = <String, double>{};
  for (final p in payments) {
    if (p is! Map) continue;
    final method = (p['payment_method'] ?? p['method'] ?? '').toString().trim();
    if (method.isEmpty) continue;
    final amount = double.tryParse(p['amount']?.toString() ?? '') ?? 0;
    map[method] = (map[method] ?? 0) + amount;
  }
  return map;
}

class _KasirReportsPageState extends ConsumerState<KasirReportsPage> {
  DateTime _selectedDate = BusinessCalendar.todayWibDateOnly();
  bool _isLoading = true;
  String _error = '';

  List<dynamic> _orders = const [];
  Map<String, dynamic> _paymentsSummary = const {};
  List<dynamic> _payments = const [];

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: BusinessCalendar.todayWibDateOnly(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      await _loadReport();
    }
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      final ordersUri = Uri.parse(
        '$baseUrl/orders/by-date?branch_id=${userState.branch}&date=$dateStr',
      );
      final paymentsUri = Uri.parse('$baseUrl/payments/daily-summary').replace(
        queryParameters: {
          'branch_id': userState.branch,
          'date': dateStr,
        },
      );

      final responses = await Future.wait([
        http.get(ordersUri, headers: NetworkConfig.defaultHeaders),
        http.get(paymentsUri, headers: NetworkConfig.defaultHeaders),
      ]);

      final ordersRes = responses[0];
      final paymentsRes = responses[1];

      if (ordersRes.statusCode != 200 || paymentsRes.statusCode != 200) {
        var paymentsHint = '';
        if (paymentsRes.statusCode != 200) {
          try {
            final decoded = jsonDecode(paymentsRes.body);
            if (decoded is Map) {
              final details = decoded['details']?.toString().trim();
              final err = decoded['error']?.toString().trim();
              if (details != null && details.isNotEmpty) {
                paymentsHint = ' — $details';
              } else if (err != null && err.isNotEmpty) {
                paymentsHint = ' — $err';
              }
            }
          } catch (_) {}
        }
        setState(() {
          _error =
              'Gagal memuat laporan (orders: ${ordersRes.statusCode}, payments: ${paymentsRes.statusCode})$paymentsHint';
          _isLoading = false;
        });
        return;
      }

      final ordersData = jsonDecode(ordersRes.body);
      final paymentsData = jsonDecode(paymentsRes.body);

      setState(() {
        _orders = ordersData is List ? ordersData : const [];
        _paymentsSummary =
            paymentsData is Map ? (paymentsData['summary'] ?? const {}) : const {};
        _payments =
            paymentsData is Map ? (paymentsData['transactions'] ?? const []) : const [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
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

  Future<void> _printReport() async {
    final us = ref.read(userStateProvider);
    final dateLabel =
        DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(_selectedDate);
    final dateSlug = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final totalOrderAmount = _orders.fold<double>(0, (sum, o) {
      final n = double.tryParse((o is Map ? o['total'] : null)?.toString() ?? '');
      return sum + (n ?? 0);
    });
    final totalPaymentAmount =
        double.tryParse(_paymentsSummary['total_amount']?.toString() ?? '') ?? 0;
    final totalPayments =
        int.tryParse(_paymentsSummary['total_payments']?.toString() ?? '') ?? 0;
    final paymentMaps = _payments
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    await printKasirDailyReport(
      context,
      reportDateLabel: dateLabel,
      reportDateSlug: dateSlug,
      branchLabel: '${_branchLabel()} (${us.branch})',
      branchIdForLogo: us.branch.trim(),
      cashierLabel:
          '${us.username.isEmpty ? 'Kasir' : us.username}${us.userId != null ? ' · ID ${us.userId}' : ''}',
      orderCount: _orders.length,
      totalOrderAmount: totalOrderAmount,
      paymentTransactionCount: totalPayments,
      totalPaymentAmount: totalPaymentAmount,
      paymentRows: paymentMaps,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(_selectedDate);
    final money = NumberFormat('#,###', 'id_ID');

    final totalOrderAmount = _orders.fold<double>(0, (sum, o) {
      final n = double.tryParse((o is Map ? o['total'] : null)?.toString() ?? '');
      return sum + (n ?? 0);
    });

    final totalPaymentAmount =
        double.tryParse(_paymentsSummary['total_amount']?.toString() ?? '') ?? 0;
    final totalPayments =
        int.tryParse(_paymentsSummary['total_payments']?.toString() ?? '') ?? 0;
    final amountByMethod = _aggregatePaymentAmountsByMethod(_payments);
    final methodEntries = amountByMethod.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Kasir'),
        actions: [
          if (!_isLoading && _error.isEmpty)
            IconButton(
              icon: const Icon(Icons.print),
              onPressed: _printReport,
              tooltip: 'Cetak / PDF',
            ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectDate,
            tooltip: 'Pilih tanggal',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReport,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(child: Text(_error))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  dateLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),

                // Orders summary
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ringkasan Order',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text('Total order: ${_orders.length}'),
                        Text('Total nilai order: Rp ${money.format(totalOrderAmount)}'),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Payments summary
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ringkasan Pembayaran',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text('Total transaksi: $totalPayments'),
                        Text('Total pembayaran: Rp ${money.format(totalPaymentAmount)}'),
                        if (methodEntries.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Per metode pembayaran',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          ...methodEntries.map(
                            (e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _kasirPaymentMethodLabel(e.key),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Rp ${money.format(e.value)}',
                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  'Pembayaran (${_payments.length})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                if (_payments.isEmpty)
                  const Text('Tidak ada pembayaran pada tanggal ini')
                else
                  LayoutBuilder(
                    builder: (context, c) {
                      final cs = Theme.of(context).colorScheme;
final slice = _payments.take(50).toList();
                      final rows = <DataRow>[];
                      for (var i = 0; i < slice.length; i++) {
                        final p = slice[i];
                        if (p is! Map) continue;
                        final orderId = p['order_id']?.toString() ?? '-';
                        final methodRaw =
                            (p['payment_method'] ?? p['method'] ?? '-')
                                .toString();
                        final amount =
                            double.tryParse(p['amount']?.toString() ?? '') ?? 0;
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
                            cells: [
                              DataCell(
                                Text(
                                  '#$orderId',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(_kasirPaymentMethodLabel(methodRaw)),
                              ),
                              DataCell(
                                Text(
                                  'Rp ${money.format(amount)}',
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
                      final minW = math.max(c.maxWidth, 520.0);
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
dataRowMinHeight: 40,
                                dataRowMaxHeight: 48,
                                columnSpacing: 12,
                                horizontalMargin: 10,
                                showCheckboxColumn: false,
                                dividerThickness: 0.5,
                                columns: [
                                  DataColumn(label: dataTableColumnLabel('Order')),
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
                      );
                    },
                  ),
                if (_payments.length > 50)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Menampilkan 50 transaksi terbaru.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
    );
  }
}

