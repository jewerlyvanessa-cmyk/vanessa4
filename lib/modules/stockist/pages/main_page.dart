import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';

import 'stock_warehouse_page.dart';
import 'stock_bulk_input_page.dart';
import 'stock_standard_input_page.dart';
import 'stock_reprint_qr_page.dart';
import 'reports_page.dart';

class StockistMainPage extends ConsumerWidget {
  const StockistMainPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            const Text('Stockist'),
          ],
        ),
        actions: [
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
      body: ListView(
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
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ModuleMenuGrid(
              minCrossAxisCount: 4,
              entries: [
                ModuleMenuEntry(
                  icon: Icons.playlist_add,
                  label: 'INPUT STOK (MASSAL)',
                  iconColor: Colors.deepPurple,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => const StockBulkInputPage(),
                    ),
                  ),
                ),
                ModuleMenuEntry(
                  icon: Icons.post_add,
                  label: 'INPUT STOK (STANDAR)',
                  iconColor: Colors.deepOrange,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => const StockStandardInputPage(),
                    ),
                  ),
                ),
                ModuleMenuEntry(
                  icon: Icons.inventory_2,
                  label: 'STOK',
                  iconColor: Colors.blue,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const StockWarehousePage(),
                    ),
                  ),
                ),
                ModuleMenuEntry(
                  icon: Icons.qr_code_2,
                  label: 'CETAK ULANG QR',
                  iconColor: Colors.brown,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => const StockReprintQrPage(),
                    ),
                  ),
                ),
                ModuleMenuEntry(
                  icon: DashboardMenuIcons.laporan,
                  label: 'LAPORAN INPUT STOK',
                  iconColor: Colors.indigo,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const StockistReportsPage(),
                    ),
                  ),
                ),
                ModuleMenuEntry(
                  icon: Icons.qr_code_scanner,
                  label: 'CEK STOK',
                  iconColor: Colors.teal,
                  onTap: () => Navigator.pushNamed(context, '/cek_stok'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
