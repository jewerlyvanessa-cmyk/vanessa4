import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/routes/app_navigator.dart';
import 'package:vanessa3/routes/app_routes.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';
import 'package:vanessa3/shared_widgets/module_dashboard_app_bar.dart';
import 'package:vanessa3/shared_widgets/role_menu_body.dart';
import 'package:vanessa3/utils/responsive_layout.dart';
import 'package:vanessa3/modules/kasir/kasir_order_display.dart';
import 'package:vanessa3/modules/kasir/widgets/kasir_payment_queue_table.dart';
import 'package:vanessa3/shared_widgets/offline_status_banner.dart';

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

      final response = await ApiClient.get(
        '/orders/pending-payment',
        query: {'branch_id': userState.branch},
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

  List<Map<String, dynamic>> get _pendingOrdersNormalized {
    final out = <Map<String, dynamic>>[];
    for (final raw in _pendingOrders) {
      if (raw is! Map) continue;
      final order = Map<String, dynamic>.from(raw);
      normalizeKasirOrderMap(order);
      out.add(order);
    }
    return out;
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

        return Scaffold(
          appBar: const ModuleDashboardAppBar(title: 'Kasir'),
          body: RoleMenuBody(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const OfflineStatusBanner(),
              Builder(
                builder: (context) {
                  return Padding(
                    padding: ResponsiveLayout.roleMenuHeaderPadding,
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
                                return KasirPaymentQueueTable(
                                  orders: _pendingOrdersNormalized,
                                  width: c.maxWidth,
                                  maxHeight: c.maxHeight,
                                  showOrderTypeColumn: false,
                                  decorated: false,
                                  cellPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  onOrderTap: (order) =>
                                      _openPaymentPageForQueue(order),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: ResponsiveLayout.scrollEndGap(context)),
            ],
            ),
          ),
        );
      },
    );
  }
}
