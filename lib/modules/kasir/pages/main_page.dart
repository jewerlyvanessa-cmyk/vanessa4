import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/routes/app_navigator.dart';
import 'package:vanessa3/routes/app_routes.dart' hide SwitchBranchRoleWidget;
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';
import '../../../utils/network_config.dart';
import 'package:vanessa3/modules/kasir/kasir_order_display.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

String getMainModuleForRole(String role) {
  switch (role) {
    case 'cs':
      return 'cs';
    case 'kasir':
      return 'kasir';
    case 'superadmin':
      return 'superadmin';
    case 'admin_toko':
      return 'admin_toko';
    case 'admin_workshop':
      return 'admin_workshop';
    case 'admin_warehouse':
      return 'admin_warehouse';
    case 'tukang':
      return 'tukang';
    case 'manajer':
      return 'manajer';
    case 'stockist':
      return 'stockist';
    default:
      return 'dashboard';
  }
}

void navigateToMainModule(BuildContext context, String mainModule) {
  final navigator = Navigator.of(context);
  switch (mainModule) {
    case 'cs':
      navigator.pushReplacementNamed('/cs');
      break;
    case 'kasir':
      navigator.pushReplacementNamed('/kasir');
      break;
    case 'admin_toko':
      navigator.pushReplacementNamed('/admin_toko');
      break;
    case 'admin_workshop':
      navigator.pushReplacementNamed('/admin_workshop');
      break;
    case 'admin_warehouse':
      navigator.pushReplacementNamed('/admin_warehouse');
      break;
    case 'tukang':
      navigator.pushReplacementNamed('/tukang');
      break;
    case 'superadmin':
      navigator.pushReplacementNamed('/superadmin');
      break;
    case 'manajer':
      navigator.pushReplacementNamed('/manager');
      break;
    case 'stockist':
      navigator.pushReplacementNamed('/stockist');
      break;
    default:
      navigator.pushReplacementNamed('/dashboard');
  }
}

class KasirMainPage extends ConsumerStatefulWidget {
  const KasirMainPage({super.key});

  @override
  ConsumerState<KasirMainPage> createState() => _KasirMainPageState();
}

class _KasirMainPageState extends ConsumerState<KasirMainPage> {
  List<dynamic> _pendingOrders = [];
  bool _isLoadingQueue = false;

  @override
  void initState() {
    super.initState();
    // WebSocket listener will be set up in build method
    _loadPendingOrders();
  }

  void _showNotification(String message) {
    if (!mounted) return;

    // Show notification for new orders, payment updates, etc.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Notifikasi Kasir: $message'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {
            // Handle notification action
          },
        ),
      ),
    );
  }

  Future<void> _loadPendingOrders() async {
    setState(() {
      _isLoadingQueue = true;
    });

    try {
      final userState = ref.read(userStateProvider);

      final response = await http.get(
        Uri.parse(
          '${NetworkConfig.baseUrl}/orders/pending-payment?branch_id=${userState.branch}',
        ),
        headers: NetworkConfig.defaultHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawList = (data is List) ? data : <dynamic>[];
        final normalized = rawList.map((e) {
          if (e is! Map) return e;
          final m = Map<String, dynamic>.from(e);
          normalizeKasirOrderMap(m);
          return m;
        }).toList();
        setState(() {
          _pendingOrders = normalized;
          _isLoadingQueue = false;
        });
      } else {
        setState(() {
          _isLoadingQueue = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingQueue = false;
      });
    }
  }

  void _openPaymentPageForQueue(dynamic raw) {
    if (raw is! Map) return;
    final order = Map<String, dynamic>.from(raw);
    normalizeKasirOrderMap(order);
    pushKasirPayment(context, order).then((_) {
      if (mounted) _loadPendingOrders();
    });
  }

  String _queueNota(Map<String, dynamic> order) {
    final n = order['order_number']?.toString().trim() ?? '';
    return n.isEmpty ? '—' : n;
  }

  String _queueFmtMoney(num n) => NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  ).format(n);

  num _queueAmountDue(Map<String, dynamic> order) {
    for (final k in const ['remaining_amount', 'amount']) {
      final v = order[k];
      if (v == null) continue;
      if (v is num) return v;
      final parsed = num.tryParse(v.toString());
      if (parsed != null) return parsed;
    }
    final t = order['total'];
    if (t is num) return t;
    return num.tryParse(t?.toString() ?? '0') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        // Setup WebSocket listener for real-time notifications
        ref.listen(realTimeOrderUpdatesProvider, (previous, next) {
          next.when(
            data: (update) {
              if (update['type'] == 'notification') {
                _showNotification(update['message']);
                if (update['message'].contains('completed')) {
                  // Refresh payment queue when payment is completed
                  _loadPendingOrders();
                }
              }
            },
            error: (error, stackTrace) {
              // Handle error if needed
            },
            loading: () {
              // Handle loading state if needed
            },
          );
        });

        // Listen to user state changes and initialize WebSocket if needed
        ref.listen(userStateProvider, (previous, next) {
          if (next.userId != null && next.role.isNotEmpty) {
            final webSocketChannel = ref.read(webSocketProvider);
            if (webSocketChannel == null) {
              ref.read(webSocketProvider.notifier).initializeAfterLogin();
            }
          }
        });

        // Watch health check status for Live indicator
        final isServerHealthy = ref.watch(healthCheckProvider);

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Image.asset(
                  'assets/logo_bulat.png',
                  height: 36,
                  width: 36,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 12),
                const Text('Kasir'),
              ],
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
              SwitchBranchRoleWidget(),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Logout',
                onPressed: () {
                  ref.read(webSocketProvider.notifier).disconnect();
                  ref.read(userStateProvider.notifier).logout();
                  Navigator.pushReplacementNamed(context, AppRoutes.login);
                },
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Builder(
                builder: (context) {
                  return Padding(
                    padding: const EdgeInsets.only(
                      left: 24.0,
                      top: 24.0,
                      right: 24.0,
                      bottom: 8.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const UserBranchRoleHeader(),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ModuleMenuGrid(
                  minCrossAxisCount: 4,
                  entries: [
                    ModuleMenuEntry(
                      icon: Icons.queue,
                      label: 'ANTRI BAYAR',
                      iconColor: Colors.orange,
                      onTap: () =>
                          pushAppRoute(context, AppRoutes.kasirPaymentQueue),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.receipt_long,
                      label: 'BAYAR TODAY',
                      iconColor: Colors.green,
                      onTap: () =>
                          pushAppRoute(context, AppRoutes.kasirDailyPayments),
                    ),
                    ModuleMenuEntry(
                      icon: DashboardMenuIcons.laporan,
                      label: 'LAPORAN',
                      iconColor: Colors.indigo,
                      onTap: () => pushAppRoute(context, AppRoutes.kasirReports),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.storefront_outlined,
                      label: 'KEUANGAN TOKO',
                      iconColor: Colors.deepOrange,
                      onTap: () => pushAppRoute(context, AppRoutes.kasirKeuangan),
                    ),
                    ModuleMenuEntry(
                      icon: DashboardMenuIcons.pelanggan,
                      label: 'PELANGGAN',
                      iconColor: Colors.purple,
                      onTap: () => pushAppRoute(context, AppRoutes.customers),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Payment Queue Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ANTRI BAYAR',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: [
                            Text(
                              '${_pendingOrders.length} order',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh, size: 20),
                              onPressed: _loadPendingOrders,
                              tooltip: 'Refresh',
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _isLoadingQueue
                          ? const Center(child: CircularProgressIndicator())
                          : _pendingOrders.isEmpty
                          ? const Center(
                              child: Text(
                                'Tidak ada order yang perlu dibayar',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, c) {
                                final cs = Theme.of(context).colorScheme;
                                final w = c.maxWidth;
                                final h = c.maxHeight;
                                final rows = <DataRow>[];
                                for (var i = 0;
                                    i < _pendingOrders.length;
                                    i++) {
                                  final raw = _pendingOrders[i];
                                  if (raw is! Map) continue;
                                  final order = Map<String, dynamic>.from(raw);
                                  normalizeKasirOrderMap(order);
                                  rows.add(
                                    DataRow(
                                      color: WidgetStateProperty.resolveWith(
                                        (s) {
                                          if (s.contains(
                                            WidgetState.hovered,
                                          )) {
                                            return cs.primary
                                                .withValues(alpha: 0.06);
                                          }
                                          return i.isOdd
                                              ? cs.surfaceContainerHighest
                                                  .withValues(alpha: 0.4)
                                              : null;
                                        },
                                      ),
                                      onSelectChanged: (selected) {
                                        if (selected == true) {
                                          _openPaymentPageForQueue(order);
                                        }
                                      },
                                      cells: [
                                        DataCell(
                                          Text(
                                            _queueNota(order),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: AppTypography.tableCell,
                                            ),
                                          ),
                                          onTap: () =>
                                              _openPaymentPageForQueue(order),
                                        ),
                                        DataCell(
                                          Text(
                                            '${order['order_type'] ?? '—'}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: AppTypography.tableCell,
                                            ),
                                          ),
                                          onTap: () =>
                                              _openPaymentPageForQueue(order),
                                        ),
                                        DataCell(
                                          Text(
                                            kasirOrderItemTitle(order),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: AppTypography.tableCell,
                                            ),
                                          ),
                                          onTap: () =>
                                              _openPaymentPageForQueue(order),
                                        ),
                                        DataCell(
                                          Text(
                                            _queueFmtMoney(
                                              _queueAmountDue(order),
                                            ),
                                            style: TextStyle(
                                              fontSize: AppTypography.tableCell,
                                              fontWeight: FontWeight.w700,
                                              color: cs.primary,
                                            ),
                                          ),
                                          onTap: () =>
                                              _openPaymentPageForQueue(order),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                return Scrollbar(
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
                                            headingRowHeight: 32,
                                            dataRowMinHeight: 36,
                                            dataRowMaxHeight: 52,
                                            headingRowColor:
                                                WidgetStateProperty.all(
                                              cs.surfaceContainerHigh,
                                            ),
                                            columnSpacing: 6,
                                            horizontalMargin: 6,
                                            showCheckboxColumn: false,
                                            dividerThickness: 0.5,
                                            columns: [
                                              DataColumn(
                                                label: dataTableColumnLabel(
                                                  'No. Nota',
                                                ),
                                              ),
                                              DataColumn(
                                                label: dataTableColumnLabel(
                                                  'Order',
                                                ),
                                              ),
                                              DataColumn(
                                                label: dataTableColumnLabel(
                                                  'Item',
                                                ),
                                              ),
                                              DataColumn(
                                                label: dataTableColumnLabel(
                                                  'Jumlah',
                                                ),
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
              ),
            ],
          ),
        );
      },
    );
  }
}
