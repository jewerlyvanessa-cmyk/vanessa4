import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/main.dart'; // Import global userStateProvider
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';
import 'order_detail_page.dart';
import 'package:vanessa3/providers/order_today_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';

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

class CSMainPage extends ConsumerStatefulWidget {
  const CSMainPage({super.key});

  @override
  ConsumerState<CSMainPage> createState() => _CSMainPageState();
}

class _CSMainPageState extends ConsumerState<CSMainPage> {
  String _fmtRp(dynamic v) {
    final n = double.tryParse(v?.toString() ?? '');
    if (n == null) return '0';
    final s = n.toStringAsFixed(0);
    return s.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

  @override
  void initState() {
    super.initState();
  }

  Color _getOrderTypeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'jual':
        return Colors.orange;
      case 'buyback':
        return Colors.green;
      case 'service':
        return Colors.blue;
      case 'custom':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getOrderTypeIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'jual':
        return Icons.shopping_cart;
      case 'buyback':
        return Icons.replay;
      case 'service':
        return Icons.build;
      case 'custom':
        return Icons.design_services;
      default:
        return Icons.receipt;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status?.toLowerCase()) {
      case 'draft':
        return 'Draft';
      case 'pending':
        return 'Pending';
      case 'reserved':
        return 'Reserved';
      case 'sold':
        return 'Terjual';
      case 'buyback':
        return 'Buyback';
      case 'on-service':
        return 'Sedang Service';
      case 'production':
        return 'Produksi';
      case 'completed':
        return 'Selesai';
      case 'cancelled':
        return 'Dibatalkan';
      default:
        return status ?? 'Unknown';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'draft':
        return Colors.grey;
      case 'pending':
        return Colors.orange;
      case 'reserved':
        return Colors.blue;
      case 'sold':
        return Colors.green;
      case 'buyback':
        return Colors.teal;
      case 'on-service':
        return Colors.orange;
      case 'production':
        return Colors.purple;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        // Watch health check status for Live indicator
        final isServerHealthy = ref.watch(healthCheckProvider);

        // Listen to user state changes
        ref.listen(userStateProvider, (previous, next) {
          ref.read(orderTodayStatsProvider.notifier).listenToUserStateChanges();
          ref.read(todayOrdersProvider.notifier).listenToUserStateChanges();

          // Initialize WebSocket if user is logged in and WebSocket is not connected
          if (next.userId != null && next.role.isNotEmpty) {
            final webSocketChannel = ref.read(webSocketProvider);
            if (webSocketChannel == null) {
              ref.read(webSocketProvider.notifier).initializeAfterLogin();
            }
          }
        });

        // Listen to real-time order updates
        ref.listen(realTimeOrderUpdatesProvider, (previous, next) {
          next.whenData((update) {
            if (update['type'] == 'order_update' ||
                update['type'] == 'notification' ||
                update['type'] == 'mock_update') {
              // Refresh order statistics and orders list when real-time update received
              ref.read(orderTodayStatsProvider.notifier).refresh();
              ref.read(todayOrdersProvider.notifier).refresh();
            }
          });
        });

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
                const Text('CS'),
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
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: GridView.count(
                  crossAxisCount:
                      4,
                  shrinkWrap: true,
                  mainAxisSpacing: 12, // Reduced from 16
                  crossAxisSpacing: 12, // Reduced from 16
                  childAspectRatio: 0.75,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _MenuButton(
                      icon: Icons.shopping_cart,
                      label: 'JUAL',
                      iconColor: Colors.orange,
                      onTap: () => Navigator.pushNamed(context, '/jual'),
                    ),
                    _MenuButton(
                      icon: Icons.replay,
                      label: 'BUYBACK',
                      iconColor: Colors.green,
                      onTap: () => Navigator.pushNamed(context, '/buyback'),
                    ),
                    _MenuButton(
                      icon: Icons.build,
                      label: 'SERVICE',
                      iconColor: Colors.blue,
                      onTap: () => Navigator.pushNamed(context, '/service'),
                    ),
                    _MenuButton(
                      icon: Icons.design_services,
                      label: 'CUSTOM',
                      iconColor: Colors.purple,
                      onTap: () => Navigator.pushNamed(context, '/custom'),
                    ),
                    _MenuButton(
                      icon: Icons.assignment_return,
                      label: 'AMBIL',
                      iconColor: Colors.indigo,
                      onTap: () => Navigator.pushNamed(context, '/ambil'),
                    ),
                    _MenuButton(
                      icon: Icons.today,
                      label: 'ORDER TODAY',
                      iconColor: Colors.amber,
                      onTap: () => Navigator.pushNamed(context, '/dashboard'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Order Today Section
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '📋 Order Hari Ini',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Consumer(
                            builder: (context, ref, child) {
                              final orderStatsAsync = ref.watch(
                                orderTodayStatsProvider,
                              );
                              return orderStatsAsync.when(
                                loading: () => const SizedBox.shrink(),
                                error: (error, stack) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Error',
                                    style: TextStyle(
                                      color: Colors.red[700],
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                data: (stats) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${stats.totalOrders} order',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Order List
                    Expanded(
                      child: Consumer(
                        builder: (context, ref, child) {
                          final todayOrdersAsync = ref.watch(
                            todayOrdersProvider,
                          );

                          return todayOrdersAsync.when(
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (error, stack) => Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: 48,
                                    color: Colors.red,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Gagal memuat data order',
                                    style: TextStyle(
                                      color: Colors.red[600],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    error.toString(),
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                            data: (orders) {
                              if (orders.isEmpty) {
                                return Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.receipt_long,
                                        size: 48,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Belum ada order hari ini',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              return ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                itemCount: orders.length,
                                itemBuilder: (context, index) {
                                  final order = orders[index];
                                  final qty =
                                      int.tryParse(order['qty'].toString()) ??
                                      1;

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ExpansionTile(
                                      leading: Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: _getOrderTypeColor(
                                            order['order_type'],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Icon(
                                          _getOrderTypeIcon(
                                            order['order_type'],
                                          ),
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(
                                        'Order #${order['order_id'] ?? 'N/A'}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${order['customer_name'] ?? 'Customer Tidak Ditemukan'} • ${order['order_type'] ?? 'Unknown'}',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                          Text(
                                            'Status: ${_getStatusLabel(order['status'])}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: _getStatusColor(
                                                order['status'],
                                              ),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          if (qty > 0)
                                            Text(
                                              '$qty item${qty > 1 ? 's' : ''}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                        ],
                                      ),
                                      trailing: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            order['jumlah'] != null
                                                ? 'Rp ${_fmtRp(order['jumlah'])}'
                                                : 'Rp 0',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Jumlah (Order)',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                      children: [
                                        // Order Details
                                        Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Customer Info
                                              if (order['customer_phone'] !=
                                                      null ||
                                                  order['customer_address'] !=
                                                      null)
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    12,
                                                  ),
                                                  margin: const EdgeInsets.only(
                                                    bottom: 12,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue[50],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Text(
                                                        'Informasi Pelanggan',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      if (order['customer_phone'] !=
                                                          null)
                                                        Text(
                                                          '📞 ${order['customer_phone']}',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                              ),
                                                        ),
                                                      if (order['customer_address'] !=
                                                          null)
                                                        Text(
                                                          '📍 ${order['customer_address']}',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                              ),
                                                        ),
                                                    ],
                                                  ),
                                                ),

                                              // Order Details
                                              const Text(
                                                'Detail Order:',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey[50],
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: Colors.grey[200]!,
                                                  ),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Tipe: ${order['order_type'] ?? 'N/A'}',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                    if (order['harga_per_gram'] !=
                                                        null)
                                                      Text(
                                                        'Harga per gram: Rp ${order['harga_per_gram']}',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    if (order['qty'] != null)
                                                      Text(
                                                        'Qty: ${order['qty']}',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    if (order['jumlah'] != null)
                                                      Text(
                                                        'Jumlah: Rp ${_fmtRp(order['jumlah'])}',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    if (order['diskon'] !=
                                                            null &&
                                                        order['diskon'] !=
                                                            '0.00')
                                                      Text(
                                                        'Diskon: Rp ${order['diskon']}',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    // Total order should follow `orders.jumlah` (rounded, after discount).
                                                    // Keep `total` (raw) hidden here to avoid confusion.
                                                  ],
                                                ),
                                              ),

                                              // Order Items
                                              if (order['items'] != null &&
                                                  (order['items'] as List)
                                                      .isNotEmpty) ...[
                                                const SizedBox(height: 12),
                                                const Text(
                                                  'Item Details:',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                ...(order['items'] as List).map(
                                                  (item) => Container(
                                                    margin:
                                                        const EdgeInsets.only(
                                                          bottom: 8,
                                                        ),
                                                    padding:
                                                        const EdgeInsets.all(
                                                          12,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.grey[50],
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                      border: Border.all(
                                                        color:
                                                            Colors.grey[200]!,
                                                      ),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .spaceBetween,
                                                          children: [
                                                            Expanded(
                                                              child: Text(
                                                                item['nama_item'] ??
                                                                    'Unknown Item',
                                                                style: const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                  fontSize: 13,
                                                                ),
                                                              ),
                                                            ),
                                                            Text(
                                                              item['total'] !=
                                                                          null &&
                                                                      double.tryParse(
                                                                            item['total'].toString(),
                                                                          ) !=
                                                                          null &&
                                                                      double.parse(
                                                                            item['total'].toString(),
                                                                          ) >
                                                                          0
                                                                  ? 'Rp ${_fmtRp(item['total'])}'
                                                                  : 'Belum dihitung',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 12,
                                                                color:
                                                                    item['total'] !=
                                                                            null &&
                                                                        double.tryParse(
                                                                              item['total'].toString(),
                                                                            ) !=
                                                                            null &&
                                                                        double.parse(
                                                                              item['total'].toString(),
                                                                            ) >
                                                                            0
                                                                    ? Colors
                                                                          .black
                                                                    : Colors
                                                                          .orange,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Text(
                                                              'Total (Item)',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                color: Colors
                                                                    .grey[600],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        // Photo Produk
                                                        if (item['photo_produk'] !=
                                                                null &&
                                                            item['photo_produk']
                                                                .toString()
                                                                .isNotEmpty)
                                                          Container(
                                                            margin:
                                                                const EdgeInsets.only(
                                                                  bottom: 8,
                                                                ),
                                                            child: ClipRRect(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    6,
                                                                  ),
                                                              child: Image.network(
                                                                item['photo_produk'],
                                                                height: 80,
                                                                width: double
                                                                    .infinity,
                                                                fit: BoxFit
                                                                    .cover,
                                                                errorBuilder:
                                                                    (
                                                                      context,
                                                                      error,
                                                                      stackTrace,
                                                                    ) {
                                                                      return Container(
                                                                        height:
                                                                            80,
                                                                        width: double
                                                                            .infinity,
                                                                        decoration: BoxDecoration(
                                                                          color:
                                                                              Colors.grey[200],
                                                                          borderRadius:
                                                                              BorderRadius.circular(
                                                                                6,
                                                                              ),
                                                                        ),
                                                                        child: const Icon(
                                                                          Icons
                                                                              .image_not_supported,
                                                                          color:
                                                                              Colors.grey,
                                                                          size:
                                                                              32,
                                                                        ),
                                                                      );
                                                                    },
                                                                loadingBuilder:
                                                                    (
                                                                      context,
                                                                      child,
                                                                      loadingProgress,
                                                                    ) {
                                                                      if (loadingProgress ==
                                                                          null) {
                                                                        return child;
                                                                      }
                                                                      return Container(
                                                                        height:
                                                                            80,
                                                                        width: double
                                                                            .infinity,
                                                                        decoration: BoxDecoration(
                                                                          color:
                                                                              Colors.grey[100],
                                                                          borderRadius:
                                                                              BorderRadius.circular(
                                                                                6,
                                                                              ),
                                                                        ),
                                                                        child: const Center(
                                                                          child: SizedBox(
                                                                            width:
                                                                                20,
                                                                            height:
                                                                                20,
                                                                            child: CircularProgressIndicator(
                                                                              strokeWidth: 2,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      );
                                                                    },
                                                              ),
                                                            ),
                                                          ),
                                                        Wrap(
                                                          spacing: 12,
                                                          runSpacing: 4,
                                                          children: [
                                                            if (item['berat'] !=
                                                                    null &&
                                                                double.tryParse(
                                                                      item['berat']
                                                                          .toString(),
                                                                    ) !=
                                                                    null &&
                                                                double.parse(
                                                                      item['berat']
                                                                          .toString(),
                                                                    ) >
                                                                    0)
                                                              Text(
                                                                'Berat: ${item['berat']}g',
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  color: Colors
                                                                      .grey[700],
                                                                ),
                                                              ),
                                                            if (item['harga_per_gram'] !=
                                                                    null &&
                                                                double.tryParse(
                                                                      item['harga_per_gram']
                                                                          .toString(),
                                                                    ) !=
                                                                    null &&
                                                                double.parse(
                                                                      item['harga_per_gram']
                                                                          .toString(),
                                                                    ) >
                                                                    0)
                                                              Text(
                                                                'Harga/g: Rp ${_fmtRp(item['harga_per_gram'])}',
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  color: Colors
                                                                      .grey[700],
                                                                ),
                                                              ),
                                                            if (item['total'] !=
                                                                    null &&
                                                                double.tryParse(
                                                                      item['total']
                                                                          .toString(),
                                                                    ) !=
                                                                    null &&
                                                                double.parse(
                                                                      item['total']
                                                                          .toString(),
                                                                    ) >
                                                                    0)
                                                              Text(
                                                                'Total: Rp ${_fmtRp(item['total'])}',
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  color: Colors
                                                                      .grey[700],
                                                                ),
                                                              ),
                                                            if (item['kategori'] !=
                                                                null)
                                                              Text(
                                                                'Kategori: ${item['kategori']}',
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  color: Colors
                                                                      .grey[700],
                                                                ),
                                                              ),
                                                            if (item['jenis'] !=
                                                                null)
                                                              Text(
                                                                'Jenis: ${item['jenis']}',
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  color: Colors
                                                                      .grey[700],
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ] else ...[
                                                const Padding(
                                                  padding: EdgeInsets.symmetric(
                                                    vertical: 8,
                                                  ),
                                                  child: Text(
                                                    'Tidak ada detail item',
                                                    style: TextStyle(
                                                      fontStyle:
                                                          FontStyle.italic,
                                                      color: Colors.grey,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ],

                                              // Action Button
                                              const SizedBox(height: 12),
                                              SizedBox(
                                                width: double.infinity,
                                                child: ElevatedButton.icon(
                                                  onPressed: () {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) =>
                                                            OrderDetailPage(
                                                              order: order,
                                                            ),
                                                      ),
                                                    );
                                                  },
                                                  icon: const Icon(
                                                    Icons.visibility,
                                                    size: 16,
                                                  ),
                                                  label: const Text(
                                                    'Lihat Detail Lengkap',
                                                  ),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.blue[600],
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 8,
                                                        ),
                                                  ),
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
                            },
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

// Widget custom untuk menu grid dengan ikon di atas dan label di bawah
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
