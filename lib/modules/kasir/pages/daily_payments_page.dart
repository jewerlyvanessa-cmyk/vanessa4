import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:vanessa3/main.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/utils/network_config.dart';

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
  DateTime _selectedDate = DateTime.now();

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
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
                _detailRow('Order', '#${payment['order_id'] ?? '-'}'),
                _detailRow('Order Number', '${payment['order_number'] ?? '-'}'),
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
      if (userId == null) {
        setState(() {
          _error = 'User belum login. Silakan login ulang.';
          _isLoading = false;
        });
        return;
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      // Hanya pembayaran yang divalidasi oleh user login (payments.validated_by = user_id dari JWT).
      final response = await ApiClient.get(
        '/payments/daily-summary',
        query: {
          'branch_id': userState.branch,
          'date': dateStr,
          'validated_by_only': '1',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          // Kasir fokus pada transaksi yang sudah selesai (completed) hari ini.
          final tx = (data['transactions'] as List?) ?? [];
          _dailyPayments = tx
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .where((e) => (e['status'] ?? '').toString() == 'completed')
              .toList();
          _summary = data['summary'] ?? {};
          // Ringkasan metode pembayaran: NOMINAL dari field `amount` per metode.
          final Map<String, num> byMethodAmount = {};
          for (final tx in _dailyPayments) {
            if (tx is! Map) continue;
            final method = (tx['payment_method'] ?? '').toString().trim();
            if (method.isEmpty) continue;
            final rawAmount = tx['amount'];
            final amount = rawAmount is num
                ? rawAmount
                : num.tryParse(rawAmount?.toString() ?? '') ?? 0;
            byMethodAmount[method] = (byMethodAmount[method] ?? 0) + amount;
          }
          _summary['payment_methods'] = byMethodAmount;
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
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadDailyPayments();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isServerHealthy = ref.watch(healthCheckProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pembayaran Hari Ini'),
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
                  child: Row(
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
                ),

                // Summary Cards
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                const Text('Total Transaksi'),
                                const SizedBox(height: 8),
                                Text(
                                  '${_summary['total_payments'] ?? 0}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                const Text('Total Pendapatan'),
                                const SizedBox(height: 8),
                                Text(
                                  'Rp ${NumberFormat('#,###', 'id_ID').format(_toNum(_summary['total_amount']))}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(color: Colors.green),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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
                            ...(_summary['payment_methods']
                                    as Map<String, dynamic>)
                                .entries
                                .map((entry) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(_getPaymentMethodName(entry.key)),
                                        Text(
                                          'Rp ${NumberFormat('#,###', 'id_ID').format(_toNum(entry.value))}',
                                        ),
                                      ],
                                    ),
                                  );
                                }),
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
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _dailyPayments.length,
                          itemBuilder: (context, index) {
                            final payment = _dailyPayments[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text('Order #${payment['order_id']}'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Customer: ${payment['customer_name'] ?? 'N/A'}',
                                    ),
                                    Text(
                                      'Metode: ${_getPaymentMethodName(payment['payment_method'])}',
                                    ),
                                    Text(
                                      'Waktu: ${DateFormat('HH:mm').format(DateTime.parse(payment['created_at']))}',
                                    ),
                                  ],
                                ),
                                trailing: Text(
                                  'Rp ${NumberFormat('#,###', 'id_ID').format(_toNum(payment['amount']))}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                                onTap: () => _showPaymentDetail(
                                  context,
                                  Map<String, dynamic>.from(payment as Map),
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
