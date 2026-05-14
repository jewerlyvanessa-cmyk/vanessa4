import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:vanessa3/modules/admin_toko/pages/employee_management_page.dart';
import 'package:vanessa3/modules/admin_toko/pages/goods_transfer_page.dart';
import 'package:vanessa3/modules/admin_toko/pages/stock_mutation_page.dart';
import 'package:vanessa3/modules/admin_toko/pages/stock_page.dart';
import 'package:vanessa3/modules/stockist/pages/dari_toko_page.dart';
import 'package:vanessa3/modules/stockist/pages/kirim_ke_toko_page.dart';
import 'package:vanessa3/modules/stockist/pages/permintaan_stok_toko_page.dart';
import 'package:vanessa3/modules/stockist/pages/reports_page.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/stock_request_transfer.dart';

/// Admin gudang: menu menggabungkan operasi stok/transfer seperti admin toko + alur gudang (stockist).
class AdminWarehouseMainPage extends ConsumerStatefulWidget {
  const AdminWarehouseMainPage({super.key});

  @override
  ConsumerState<AdminWarehouseMainPage> createState() =>
      _AdminWarehouseMainPageState();
}

class _AdminWarehouseMainPageState extends ConsumerState<AdminWarehouseMainPage> {
  bool _loadingPending = true;
  String? _pendingError;
  List<Map<String, dynamic>> _pendingTransfers = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPendingTransfers());
  }

  Future<void> _loadPendingTransfers() async {
    setState(() {
      _loadingPending = true;
      _pendingError = null;
    });

    try {
      final user = ref.read(userStateProvider);
      final branchId = user.branch;
      final baseUrl = NetworkConfig.baseUrl;

      final uri =
          Uri.parse('$baseUrl/transfers?branch_id=$branchId&status=pending');
      final res = await http.get(uri, headers: NetworkConfig.defaultHeaders);

      if (res.statusCode != 200) {
        setState(() {
          _pendingError = 'Gagal memuat pending transfer (${res.statusCode})';
          _loadingPending = false;
        });
        return;
      }

      final json = jsonDecode(res.body);
      final rows = (json is List ? json : const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      setState(() {
        _pendingTransfers = rows;
        _loadingPending = false;
      });
    } catch (e) {
      setState(() {
        _pendingError = e.toString();
        _loadingPending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isServerHealthy = ref.watch(healthCheckProvider);
    final branchId = ref.watch(userStateProvider).branch.toString();

    final pendingOutgoingAll = _pendingTransfers.where((t) {
      return (t['from_branch_id']?.toString() ?? '') == branchId;
    }).toList();
    final pendingIncoming = _pendingTransfers.where((t) {
      return (t['to_branch_id']?.toString() ?? '') == branchId;
    }).toList();
    final stockRequestOutgoing = pendingOutgoingAll.where((t) {
      return transferNotesIsStockRequest((t['notes'] ?? '').toString());
    }).toList();
    final pendingOutgoing = pendingOutgoingAll.where((t) {
      return !transferNotesIsStockRequest((t['notes'] ?? '').toString());
    }).toList();

    ref.listen(userStateProvider, (previous, next) {
      if (next.userId != null && next.role.isNotEmpty) {
        final webSocketChannel = ref.read(webSocketProvider);
        if (webSocketChannel == null) {
          ref.read(webSocketProvider.notifier).initializeAfterLogin();
        }
      }
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
            const Text('Admin Gudang'),
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
      body: RefreshIndicator(
        onRefresh: _loadPendingTransfers,
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
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ModuleMenuGrid(
                minCrossAxisCount: 4,
                entries: [
                  ModuleMenuEntry(
                    icon: Icons.inventory_2,
                    label: 'Stok',
                    iconColor: Colors.teal,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const StockPage()),
                    ),
                  ),
                  ModuleMenuEntry(
                    icon: Icons.local_shipping,
                    label: 'Kirim / terima',
                    iconColor: Colors.orange,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const GoodsTransferPage(),
                      ),
                    ),
                  ),
                  ModuleMenuEntry(
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
                  ModuleMenuEntry(
                    icon: Icons.move_to_inbox,
                    label: 'Permintaan stok toko',
                    iconColor: Colors.deepOrange,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PermintaanStokTokoPage(),
                      ),
                    ),
                  ),
                  ModuleMenuEntry(
                    icon: Icons.call_received,
                    label: 'Dari toko',
                    iconColor: Colors.orange,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DariTokoPage(),
                      ),
                    ),
                  ),
                  ModuleMenuEntry(
                    icon: Icons.local_shipping_outlined,
                    label: 'Kirim ke toko',
                    iconColor: Colors.teal,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const KirimKeTokoPage(),
                      ),
                    ),
                  ),
                  ModuleMenuEntry(
                    icon: DashboardMenuIcons.kelolaPengguna,
                    label: 'Karyawan',
                    iconColor: Colors.purple,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const EmployeeManagementPage(),
                      ),
                    ),
                  ),
                  ModuleMenuEntry(
                    icon: Icons.qr_code_scanner,
                    label: 'Cek Stok',
                    iconColor: Colors.teal,
                    onTap: () => Navigator.pushNamed(context, '/cek_stok'),
                  ),
                  ModuleMenuEntry(
                    icon: DashboardMenuIcons.laporan,
                    label: 'Laporan Input Stok',
                    iconColor: Colors.indigo,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const StockistReportsPage(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _WhPendingSection(
                title: 'Kirim ke toko (Pending)',
                icon: Icons.local_shipping,
                iconColor: Colors.teal,
                loading: _loadingPending,
                error: _pendingError,
                transfers: pendingOutgoing,
                onSeeAll: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const KirimKeTokoPage(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _WhPendingSection(
                title: 'Permintaan stok dari toko',
                icon: Icons.move_to_inbox,
                iconColor: Colors.deepOrange,
                loading: _loadingPending,
                error: _pendingError,
                transfers: stockRequestOutgoing,
                onSeeAll: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PermintaanStokTokoPage(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _WhPendingSection(
                title: 'Dari toko (Pending)',
                icon: Icons.call_received,
                iconColor: Colors.orange,
                loading: _loadingPending,
                error: _pendingError,
                transfers: pendingIncoming,
                onSeeAll: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DariTokoPage()),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _WhPendingSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final bool loading;
  final String? error;
  final List<Map<String, dynamic>> transfers;
  final VoidCallback onSeeAll;

  const _WhPendingSection({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.loading,
    required this.error,
    required this.transfers,
    required this.onSeeAll,
  });

  int _asInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(onPressed: onSeeAll, child: const Text('Lihat semua')),
              ],
            ),
            const SizedBox(height: 8),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (error != null && error!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  error!,
                  style: const TextStyle(color: Colors.red),
                ),
              )
            else if (transfers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Tidak ada data pending'),
              )
            else
              ...transfers.take(5).map((t) {
                final item = (t['item_name'] ?? '-').toString();
                final qty = _asInt(t['quantity']);
                final from = (t['from_branch_name'] ?? t['from_branch_id'] ?? '-')
                    .toString();
                final to =
                    (t['to_branch_name'] ?? t['to_branch_id'] ?? '-').toString();
                final courier =
                    (t['courier'] ?? t['kurir'] ?? '-').toString().trim();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: iconColor.withValues(alpha: 0.15),
                    child: Text(
                      qty.toString(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: iconColor,
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
        ),
      ),
    );
  }
}
