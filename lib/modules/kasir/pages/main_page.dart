import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/main.dart'; // Import global userStateProvider
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';
import 'payment_queue_page.dart';
import 'daily_payments_page.dart';
import 'payment_page.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/modules/cs/pages/customers_page.dart';
import '../../../utils/network_config.dart';

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
    case 'tukang':
      return 'tukang';
    case 'manajer':
      return 'manajer';
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
    case 'tukang':
      navigator.pushReplacementNamed('/tukang');
      break;
    case 'superadmin':
      navigator.pushReplacementNamed('/superadmin');
      break;
    case 'manajer':
      navigator.pushReplacementNamed('/manajer');
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
        setState(() {
          _pendingOrders = data;
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
                  final userState = ref.watch(userStateProvider);
                  String branchName = '';
                  if (userState.branch.isNotEmpty &&
                      userState.branches.isNotEmpty) {
                    final found = userState.branches.firstWhere(
                      (b) => b['branch_id'].toString() == userState.branch,
                      orElse: () => <String, dynamic>{},
                    );
                    branchName = found['name'] ?? userState.branch;
                  }
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
                        Text(
                          'User: ${userState.username.isNotEmpty ? userState.username : '-'}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Branch aktif: $branchName',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Role aktif: ${userState.role}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _MenuButton(
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
                    _MenuButton(
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
                    _MenuButton(
                      icon: Icons.people,
                      label: 'Customer',
                      iconColor: Colors.purple,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CustomersPage(),
                        ),
                      ),
                    ),
                    _MenuButton(
                      icon: Icons.analytics,
                      label: 'Laporan',
                      iconColor: Colors.blue,
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Fitur ini akan segera hadir'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
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
                          : ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: _pendingOrders.length,
                              itemBuilder: (context, index) {
                                final order = _pendingOrders[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    dense: true,
                                    title: Text(
                                      'Order #${order['order_id']}',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                    subtitle: Text(
                                      'Customer: ${order['customer_name'] ?? 'N/A'}\n'
                                      'Item: ${order['nama_item'] ?? 'N/A'}\n'
                                      'Total: Rp ${order['total']?.toString() ?? '0'}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    trailing: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 12,
                                        ),
                                      ),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                PaymentPage(order: order),
                                          ),
                                        ).then(
                                          (_) => _loadPendingOrders(),
                                        ); // Refresh after payment
                                      },
                                      child: const Text('Bayar'),
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

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback? onTap;
  const _MenuButton({
    required this.icon,
    required this.label,
    required this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: iconColor),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
