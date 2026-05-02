import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:vanessa3/main.dart'; // Import global userStateProvider
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';
import 'daily_orders_payments_page.dart';
import 'goods_transfer_page.dart';
import 'stock_mutation_page.dart';
import 'stock_page.dart';
import 'employee_management_page.dart';
import 'package:vanessa3/modules/cs/pages/customers_page.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/providers/store_dashboard_provider.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/utils/network_config.dart';

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

// Hapus definisi lokal userStateProvider, gunakan yang dari main.dart

class AdminTokoMainPage extends ConsumerWidget {
  const AdminTokoMainPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch health check status for Live indicator
    final isServerHealthy = ref.watch(healthCheckProvider);

    // React to user changes outside of build (avoid modifying providers during build)
    ref.listen(userStateProvider, (previous, next) {
      ref.read(storeDashboardProvider.notifier).listenToUserStateChanges();
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

    // Listen to real-time order updates for store management
    ref.listen(realTimeOrderUpdatesProvider, (previous, next) {
      next.whenData((update) {
        if (update['type'] == 'order_update' ||
            update['type'] == 'store_assignment') {
          // Refresh store dashboard when orders or transactions occur
          ref.read(storeDashboardProvider.notifier).refresh();
          // Show notification for new store orders or updates
          _showStoreNotification(context, update['data']);
        }
      });
    });

    final pendingKey = GlobalKey<_AdminTokoPendingTransfersCardState>();

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
            const Text('Admin Toko'),
          ],
        ),
        actions: [
          // Real-time connection indicator
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: Row(
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
          ),
          SwitchBranchRoleWidget(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              ref.read(userStateProvider.notifier).logout();
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await pendingKey.currentState?._load();
        },
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: 24.0,
                top: 24.0,
                right: 24.0,
                bottom: 8.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [UserBranchRoleHeader()],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: GridView.count(
                crossAxisCount: 4,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.75,
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                children: [
                  _MenuButton(
                    icon: Icons.receipt_long,
                    label: 'Order & Bayar',
                    iconColor: Colors.blue,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DailyOrdersPaymentsPage(),
                      ),
                    ),
                  ),
                  _MenuButton(
                    icon: Icons.inventory_2,
                    label: 'Stok',
                    iconColor: Colors.teal,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const StockPage()),
                    ),
                  ),
                  _MenuButton(
                    icon: Icons.local_shipping,
                    label: 'Transfer',
                    iconColor: Colors.orange,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const GoodsTransferPage(),
                      ),
                    ),
                  ),
                  _MenuButton(
                    icon: Icons.inventory,
                    label: 'Mutasi Stok',
                    iconColor: Colors.green,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const StockMutationPage(),
                      ),
                    ),
                  ),
                  _MenuButton(
                    icon: Icons.people,
                    label: 'Karyawan',
                    iconColor: Colors.purple,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const EmployeeManagementPage(),
                      ),
                    ),
                  ),
                  _MenuButton(
                    icon: Icons.groups_2,
                    label: 'Pelanggan',
                    iconColor: Colors.cyan,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CustomersPage(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _AdminTokoPendingTransfersCard(
                key: pendingKey,
                onSeeAll: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const GoodsTransferPage()),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showStoreNotification(BuildContext context, String message) {
    // Show notification for store orders, stock updates, etc.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pemberitahuan Toko: $message'),
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

  String _twoLineLabel(String text) {
    final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= 1) return text;
    final mid = (words.length / 2).ceil();
    final first = words.sublist(0, mid).join(' ');
    final second = words.sublist(mid).join(' ');
    if (second.isEmpty) return first;
    return '$first\n$second';
  }

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
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: iconColor),
            const SizedBox(height: 6),
            Text(
              _twoLineLabel(label),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminTokoPendingTransfersCard extends ConsumerStatefulWidget {
  final VoidCallback onSeeAll;
  const _AdminTokoPendingTransfersCard({super.key, required this.onSeeAll});

  @override
  ConsumerState<_AdminTokoPendingTransfersCard> createState() =>
      _AdminTokoPendingTransfersCardState();
}

class _AdminTokoPendingTransfersCardState
    extends ConsumerState<_AdminTokoPendingTransfersCard> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _pending = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _pending = const [];
    });

    try {
      final user = ref.read(userStateProvider);
      final branchId = user.branch.toString();
      final baseUrl = NetworkConfig.baseUrl;

      // Keep compatibility: endpoint already used elsewhere without status param.
      final uri = Uri.parse('$baseUrl/transfers?branch_id=$branchId');
      final res = await http.get(uri, headers: NetworkConfig.defaultHeaders);
      if (res.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _error = 'Gagal memuat transfer (${res.statusCode})';
          _loading = false;
        });
        return;
      }

      final decoded = jsonDecode(res.body);
      final rows = (decoded is List ? decoded : const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((t) => (t['status'] ?? '').toString() == 'pending')
          .toList();

      if (!mounted) return;
      setState(() {
        _pending = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int _asInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final branchId = ref.watch(userStateProvider).branch.toString();

    final incoming = _pending.where((t) {
      return (t['to_branch_id']?.toString() ?? '') == branchId;
    }).toList();
    final outgoing = _pending.where((t) {
      return (t['from_branch_id']?.toString() ?? '') == branchId;
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Transfer Pending',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(onPressed: widget.onSeeAll, child: const Text('Lihat semua')),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _error!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _PendingChip(
                          label: 'Masuk',
                          count: incoming.length,
                          color: Colors.blue,
                          icon: Icons.arrow_downward,
                        ),
                        const SizedBox(height: 10),
                        _PendingChip(
                          label: 'Keluar',
                          count: outgoing.length,
                          color: Colors.orange,
                          icon: Icons.arrow_upward,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_pending.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Tidak ada transfer pending'),
                )
              else
                ..._pending.take(5).map((t) {
                  final item = (t['item_name'] ?? t['nama_item'] ?? '-').toString();
                  final qty = _asInt(t['quantity'] ?? t['qty']);
                  final from =
                      (t['from_branch_name'] ?? t['from_branch_id'] ?? '-').toString();
                  final to = (t['to_branch_name'] ?? t['to_branch_id'] ?? '-').toString();
                  final courier = (t['courier'] ?? t['kurir'] ?? '-').toString().trim();
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.orange.withValues(alpha: 0.15),
                      child: Text(
                        qty.toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                    title: Text(
                      item,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('$from → $to • Kurir: ${courier.isEmpty ? '-' : courier}'),
                    trailing: const Text(
                      'pending',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.orange,
                      ),
                    ),
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }
}

class _PendingChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  const _PendingChip({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w700, color: color),
            ),
          ),
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text(
              count.toString(),
              style: TextStyle(fontWeight: FontWeight.w800, color: color),
            ),
            backgroundColor: color.withValues(alpha: 0.10),
            side: BorderSide(color: color.withValues(alpha: 0.20)),
          ),
        ],
      ),
    );
  }
}
