import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';
import 'payment_queue_page.dart';
import 'daily_payments_page.dart';
import 'keuangan_toko_page.dart';
import 'payment_page.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';
import 'package:vanessa3/modules/cs/pages/customers_page.dart';
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentPage(order: order),
      ),
    ).then((_) {
      if (mounted) _loadPendingOrders();
    });
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
                  Navigator.pushReplacementNamed(context, '/login');
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
                      label: 'Antri Bayar',
                      iconColor: Colors.orange,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PaymentQueuePage(),
                        ),
                      ),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.receipt_long,
                      label: 'Bayar Today',
                      iconColor: Colors.green,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const DailyPaymentsPage(),
                        ),
                      ),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.storefront_outlined,
                      label: 'Keuangan Toko',
                      iconColor: Colors.deepOrange,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const KeuanganTokoPage(),
                        ),
                      ),
                    ),
                    ModuleMenuEntry(
                      icon: DashboardMenuIcons.pelanggan,
                      label: 'Pelanggan',
                      iconColor: Colors.purple,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CustomersPage(),
                        ),
                      ),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.qr_code_scanner,
                      label: 'Cek Stok',
                      iconColor: Colors.teal,
                      onTap: () => Navigator.pushNamed(context, '/cek_stok'),
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
                          'Antri Bayar',
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
                                'Tidak ada order draft',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, c) {
                                final cs = Theme.of(context).colorScheme;
final minW = math.max(c.maxWidth, 520.0);
                                final rows = <DataRow>[];
                                for (var i = 0;
                                    i < _pendingOrders.length;
                                    i++) {
                                  final order = _pendingOrders[i];
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
                                            '#${order['order_id']}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                          onTap: () =>
                                              _openPaymentPageForQueue(order),
                                        ),
                                        DataCell(
                                          Text(
                                            '${order['customer_name'] ?? 'N/A'}',
                                            style: const TextStyle(
                                              fontSize: 12,
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
                                              fontSize: 11,
                                            ),
                                          ),
                                          onTap: () =>
                                              _openPaymentPageForQueue(order),
                                        ),
                                        DataCell(
                                          Text(
                                            'Rp ${order['total']?.toString() ?? '0'}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: cs.primary,
                                            ),
                                          ),
                                          onTap: () =>
                                              _openPaymentPageForQueue(order),
                                        ),
                                        DataCell(
                                          FilledButton.tonal(
                                            style: FilledButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 4,
                                              ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            onPressed: () =>
                                                _openPaymentPageForQueue(order),
                                            child: const Text(
                                              'Bayar',
                                              style: TextStyle(fontSize: 11),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                return Scrollbar(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minWidth: minW,
                                      ),
                                      child: SingleChildScrollView(
                                        child: DataTable(
                                          headingRowHeight: 34,
                                          dataRowMinHeight: 40,
                                          dataRowMaxHeight: 56,
                                          headingRowColor:
                                              WidgetStateProperty.all(
                                            cs.surfaceContainerHigh,
                                          ),
columnSpacing: 8,
                                          horizontalMargin: 8,
                                          showCheckboxColumn: false,
                                          dividerThickness: 0.5,
                                          columns: [
                                            DataColumn(label: dataTableColumnLabel('Order')),
                                            DataColumn(label: dataTableColumnLabel('Customer')),
                                            DataColumn(label: dataTableColumnLabel('Item')),
                                            DataColumn(label: dataTableColumnLabel('Total')),
                                            DataColumn(label: dataTableColumnLabel('Aksi')),
                                          ],
                                          rows: rows,
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
