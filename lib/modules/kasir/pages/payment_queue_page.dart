import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:vanessa3/widgets/qr_scan_route.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'payment_page.dart';
import 'package:vanessa3/modules/kasir/kasir_order_display.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../utils/logger.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

class PaymentQueuePage extends ConsumerStatefulWidget {
  const PaymentQueuePage({super.key});

  @override
  ConsumerState<PaymentQueuePage> createState() => _PaymentQueuePageState();
}

class _PaymentQueuePageState extends ConsumerState<PaymentQueuePage> {
  List<dynamic> _pendingOrders = [];
  bool _isLoading = true;
  String _error = '';
  final TextEditingController _searchController = TextEditingController();

  String _orderNota(Map<String, dynamic> order) {
    final n = order['order_number']?.toString().trim() ?? '';
    return n.isEmpty ? '—' : n;
  }

  String _fmtMoney(num n) => NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  ).format(n);

  num _amountDue(Map<String, dynamic> order) {
    for (final k in const ['remaining_amount', 'amount']) {
      final v = order[k];
      if (v == null) continue;
      if (v is num) return v;
      final n = num.tryParse(v.toString());
      if (n != null) return n;
    }
    final t = order['total'];
    if (t is num) return t;
    return num.tryParse(t?.toString() ?? '0') ?? 0;
  }

  String _paymentMethodLabel(Map<String, dynamic> order) {
    final m = (order['payment_method'] ?? order['method'] ?? '')
        .toString()
        .trim();
    if (m.isEmpty) return '—';
    return m;
  }

  Widget _queueMetaLine(
    BuildContext context,
    String label,
    String value,
    ColorScheme cs,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    height: 1.25,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  bool _paymentQueueOrderMatchesSearch(Map<String, dynamic> o, String q) {
    if (q.isEmpty) return true;
    if ('${o['order_id']}'.toLowerCase().contains(q)) return true;
    final nota = _orderNota(o);
    if (nota != '—' && nota.toLowerCase().contains(q)) return true;
    if ((o['customer_name'] ?? '').toString().toLowerCase().contains(q)) {
      return true;
    }
    final phone = (o['customer_phone'] ?? o['phone'] ?? '').toString();
    if (phone.toLowerCase().contains(q)) return true;
    if (kasirOrderItemTitle(o).toLowerCase().contains(q)) return true;
    if ((o['order_type'] ?? '').toString().toLowerCase().contains(q)) {
      return true;
    }
    if (_paymentMethodLabel(o).toLowerCase().contains(q)) return true;
    return false;
  }

  List<Map<String, dynamic>> _filteredPaymentQueue() {
    final q = _searchController.text.trim().toLowerCase();
    final out = <Map<String, dynamic>>[];
    for (final raw in _pendingOrders) {
      if (raw is! Map) continue;
      final o = Map<String, dynamic>.from(raw);
      normalizeKasirOrderMap(o);
      if (_paymentQueueOrderMatchesSearch(o, q)) out.add(o);
    }
    return out;
  }

  Future<void> _scanAndFillSearch() async {
    if (!mounted) return;
    final value = await pushQrScanPage(context, title: 'Scan QR');
    if (!mounted || value == null || value.isEmpty) return;
    _searchController.text = value;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _loadPendingOrders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPendingOrders() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      Logger.logInfo('Loading pending orders for branch: ${userState.branch}');

      if (userState.branch.isEmpty) {
        setState(() {
          _error = 'Branch tidak dikonfigurasi. Silakan login ulang.';
          _isLoading = false;
        });
        return;
      }

      final response = await ApiClient.get(
        '/orders/pending-payment',
        query: {'branch_id': userState.branch},
      );

      Logger.logInfo('Response status: ${response.statusCode}');
      Logger.logInfo('Payment queue fetched with status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        Logger.logInfo('Parsed data: $data');
        final List<dynamic> rawList = (data is List) ? data : [];
        final normalized = rawList.map((e) {
          if (e is! Map) return e;
          final m = Map<String, dynamic>.from(e);
          normalizeKasirOrderMap(m);
          return m;
        }).toList();
        setState(() {
          _pendingOrders = normalized;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Gagal memuat antrian pembayaran: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } on UnauthorizedException catch (_) {
      // ApiClient sudah memicu logout; tidak perlu pesan tambahan.
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.logError('Error loading pending orders: $e');
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for real-time notifications
    ref.listen(notificationProvider, (previous, next) {
      next.whenData((message) {
        if (message.contains('completed')) {
          // Refresh pending orders when payment is completed
          _loadPendingOrders();
        }
      });
    });

    final isServerHealthy = ref.watch(healthCheckProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Antrian Pembayaran'),
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
            icon: const Icon(Icons.refresh),
            onPressed: _loadPendingOrders,
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
                    onPressed: _loadPendingOrders,
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText:
                          'Cari nota, tipe order, item, metode, status…',
                      prefixIcon: const Icon(Icons.search, size: 22),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchController.text.trim().isNotEmpty)
                            IconButton(
                              tooltip: 'Hapus',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            ),
                          IconButton(
                            tooltip: 'Scan QR',
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: _scanAndFillSearch,
                          ),
                        ],
                      ),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Expanded(
                  child: _pendingOrders.isEmpty
                      ? const Center(
                          child: Text('Tidak ada order yang perlu dibayar'),
                        )
                      : Builder(
                          builder: (context) {
                            final filtered = _filteredPaymentQueue();
                            if (filtered.isEmpty) {
                              return const Center(
                                child: Text('Tidak ada hasil pencarian'),
                              );
                            }
                            return Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 8, 12, 12),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final cs = Theme.of(context).colorScheme;
                                  final isNarrow =
                                      constraints.maxWidth < 600;
                                  final w = constraints.maxWidth;
                                  final h = constraints.maxHeight.isFinite
                                      ? constraints.maxHeight
                                      : 320.0;

                                  void goPay(Map<String, dynamic> order) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            PaymentPage(order: order),
                                      ),
                                    );
                                  }

                  if (isNarrow) {
                    return ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final order = filtered[i];
                        if (order.isNotEmpty) normalizeKasirOrderMap(order);
                        final nota = _orderNota(order);
                        final due = _amountDue(order);
                        final type =
                            (order['order_type'] ?? '—').toString();
                        final item = kasirOrderItemTitle(order);
                        return Material(
                          color: cs.surfaceContainerLow.withValues(alpha: 0.65),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.35),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: order.isEmpty ? null : () => goPay(order),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    nota,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  _queueMetaLine(context, 'Order', type, cs),
                                  _queueMetaLine(context, 'Item', item, cs),
                                  const SizedBox(height: 4),
                                  Text(
                                    _fmtMoney(due),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: cs.primary,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }
                  final rows = <DataRow>[];
                  for (var i = 0; i < filtered.length; i++) {
                    final order = filtered[i];
                    if (order.isNotEmpty) normalizeKasirOrderMap(order);
                    rows.add(
                      DataRow(
                        onSelectChanged: order.isEmpty
                            ? null
                            : (selected) {
                                if (selected == true) goPay(order);
                              },
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
                              _orderNota(order),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: AppTypography.tableCell,
                              ),
                            ),
                            onTap: order.isEmpty ? null : () => goPay(order),
                          ),
                          DataCell(
                            Text(
                              '${order['order_type'] ?? '—'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: order.isEmpty ? null : () => goPay(order),
                          ),
                          DataCell(
                            Text(
                              kasirOrderItemTitle(order),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: order.isEmpty ? null : () => goPay(order),
                          ),
                          DataCell(
                            Text(
                              _fmtMoney(_amountDue(order)),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: cs.primary,
                              ),
                            ),
                            onTap: order.isEmpty ? null : () => goPay(order),
                          ),
                        ],
                      ),
                    );
                  }
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
                      child: SizedBox(
                        width: w,
                        height: h,
                        child: ClipRect(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topLeft,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(
                                  cs.surfaceContainerHigh,
                                ),
                                dataRowMinHeight: 40,
                                dataRowMaxHeight: 56,
                                columnSpacing: 6,
                                horizontalMargin: 6,
                                showCheckboxColumn: false,
                                dividerThickness: 0.5,
                                columns: [
                                  DataColumn(
                                    label: dataTableColumnLabel('No. Nota'),
                                  ),
                                  DataColumn(
                                    label: dataTableColumnLabel('Order'),
                                  ),
                                  DataColumn(
                                    label: dataTableColumnLabel('Item'),
                                  ),
                                  DataColumn(
                                    label: dataTableColumnLabel('Jumlah'),
                                    numeric: true,
                                  ),
                                ],
                                rows: rows,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
