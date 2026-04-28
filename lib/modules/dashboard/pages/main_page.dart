import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../providers/order_today_provider.dart';
import '../../../providers/websocket_provider.dart';
import '../../../main.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderStatsAsync = ref.watch(orderTodayStatsProvider);
    final isServerHealthy = ref.watch(healthCheckProvider);

    // Listen to user state changes
    ref.listen(userStateProvider, (previous, next) {
      ref.read(orderTodayStatsProvider.notifier).listenToUserStateChanges();
    });

    // Listen to real-time updates
    ref.listen(realTimeOrderUpdatesProvider, (previous, next) {
      next.whenData((update) {
        if (update['type'] == 'order_update' ||
            update['type'] == 'mock_update') {
          // Refresh data when real-time update received
          ref.read(orderTodayStatsProvider.notifier).refresh();
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Today'),
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(orderTodayStatsProvider.notifier).refresh();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(orderTodayStatsProvider.notifier).refresh();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header dengan tanggal hari ini
              _buildHeader(),

              const SizedBox(height: 30),

              // Stats Cards - Summary of orders by type
              orderStatsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(child: Text('Error: $error')),
                data: (stats) => _buildStatsCards(stats),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final today = DateTime.now();
    final formatter = DateFormat('EEEE, dd MMMM yyyy', 'id_ID');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade600, Colors.blue.shade800],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.today, color: Colors.white, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Order Today',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  formatter.format(today),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards(OrderTodayStats stats) {
    return Column(
      children: [
        // Row 1: Total Orders & Revenue
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Total Order',
                value: stats.totalOrders.toString(),
                icon: Icons.assignment,
                color: Colors.blue,
                subtitle: 'Hari ini',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: 'Revenue',
                value: 'Rp ${NumberFormat('#,###').format(stats.totalRevenue)}',
                icon: Icons.attach_money,
                color: Colors.green,
                subtitle: 'Hari ini',
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Row 2: Completed & Pending
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Completed',
                value: stats.completedOrders.toString(),
                icon: Icons.check_circle,
                color: Colors.green,
                subtitle: stats.totalOrders > 0
                    ? '${((stats.completedOrders / stats.totalOrders) * 100).round()}% dari total'
                    : '0% dari total',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: 'Pending',
                value: stats.pendingOrders.toString(),
                icon: Icons.pending,
                color: Colors.orange,
                subtitle: 'Butuh perhatian',
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Order by Type Section
        const Text(
          '📊 Order by Type',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),

        _buildOrderTypeGrid(stats.ordersByType),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderTypeGrid(Map<String, int> ordersByType) {
    final orderTypes = [
      {
        'type': 'jual',
        'label': 'Jual',
        'icon': Icons.sell,
        'color': Colors.blue,
      },
      {
        'type': 'buyback',
        'label': 'Buyback',
        'icon': Icons.replay,
        'color': Colors.purple,
      },
      {
        'type': 'service',
        'label': 'Service',
        'icon': Icons.settings,
        'color': Colors.orange,
      },
      {
        'type': 'custom',
        'label': 'Custom',
        'icon': Icons.palette,
        'color': Colors.teal,
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.2, // Adjusted for horizontal layout
      ),
      itemCount: orderTypes.length,
      itemBuilder: (context, index) {
        final typeData = orderTypes[index];
        final count = ordersByType[typeData['type']] ?? 0;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.1),
                spreadRadius: 1,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Icon and label on the left
              Row(
                children: [
                  Icon(
                    typeData['icon'] as IconData,
                    color: typeData['color'] as Color,
                    size: 24, // Slightly smaller for horizontal layout
                  ),
                  const SizedBox(width: 8),
                  Text(
                    typeData['label'] as String,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              // Count number on the right
              Text(
                count.toString(),
                style: const TextStyle(
                  fontSize: 20, // Slightly smaller for better fit
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
