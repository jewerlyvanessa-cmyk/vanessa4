import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/routes/app_navigator.dart';
import 'package:vanessa3/routes/app_routes.dart' hide SwitchBranchRoleWidget;
import 'package:vanessa3/providers/store_dashboard_provider.dart';
import 'package:vanessa3/providers/store_workshop_receipt_count_provider.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/shared_widgets/module_destination_sheet.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';
import 'package:vanessa3/shared_widgets/module_menu_group_labels.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/shared_widgets/module_dashboard_app_bar.dart';
import 'package:vanessa3/shared_widgets/role_menu_body.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

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

// userStateProvider: package:vanessa3/providers/user_state_provider.dart

class AdminTokoMainPage extends ConsumerStatefulWidget {
  const AdminTokoMainPage({super.key});

  @override
  ConsumerState<AdminTokoMainPage> createState() => _AdminTokoMainPageState();
}

class _AdminTokoMainPageState extends ConsumerState<AdminTokoMainPage> {
  void _openWarehouseSheet(BuildContext context) {
    showModuleDestinationSheet(
      context,
      title: ModuleMenuGroupLabels.sheetWarehouse,
      options: [
        ModuleDestinationOption(
          label: 'Pesan stok ke warehouse',
          subtitle: 'Permintaan barang dari gudang pusat',
          icon: Icons.warehouse_outlined,
          iconColor: Colors.deepOrange,
          onTap: () => pushAppRoute(context, AppRoutes.adminTokoStockRequest),
        ),
        ModuleDestinationOption(
          label: 'Transfer dengan gudang',
          subtitle: 'Terima kiriman / kirim kembali ke warehouse',
          icon: Icons.local_shipping_outlined,
          iconColor: Colors.orange,
          onTap: () => pushAppRoute(context, AppRoutes.adminTokoGoodsTransfer),
        ),
      ],
    );
  }

  void _openWorkshopSheet(BuildContext context) {
    showModuleDestinationSheet(
      context,
      title: ModuleMenuGroupLabels.sheetWorkshop,
      options: [
        ModuleDestinationOption(
          label: 'Service / custom',
          subtitle: 'Kirim order ke workshop',
          icon: Icons.build_circle_outlined,
          iconColor: Colors.deepOrange,
          onTap: () => pushAppRoute(context, AppRoutes.adminTokoServiceCustom),
        ),
        ModuleDestinationOption(
          label: 'Terima dari workshop',
          subtitle: 'Konfirmasi barang kembali dari bengkel',
          icon: Icons.handyman_outlined,
          iconColor: Colors.indigo,
          onTap: () async {
            await Navigator.pushNamed(
              context,
              AppRoutes.adminTokoWorkshopReceipt,
            );
            if (!context.mounted) return;
            ref.read(storeWorkshopReceiptCountProvider.notifier).refresh();
          },
        ),
      ],
    );
  }

  void _openAntarTokoSheet(BuildContext context) {
    showModuleDestinationSheet(
      context,
      title: ModuleMenuGroupLabels.sheetAntarToko,
      options: [
        ModuleDestinationOption(
          label: 'Kirim / terima barang',
          subtitle: 'Transfer antar cabang toko (etalase)',
          icon: Icons.hub_outlined,
          iconColor: Colors.blueGrey,
          onTap: () => pushAppRoute(context, AppRoutes.adminTokoGoodsTransfer),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(storeWorkshopReceiptCountProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
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
        final type = (update['type'] ?? '').toString();
        final event = (update['event'] ?? '').toString();
        if (type == 'order_update' ||
            type == 'store_assignment' ||
            event == 'workshop_sent_to_store') {
          ref.read(storeDashboardProvider.notifier).refresh();
          ref.read(storeWorkshopReceiptCountProvider.notifier).refresh();
          _showStoreNotification(context, update['data']);
        }
      });
    });

    final workshopReceiptPending = ref.watch(storeWorkshopReceiptCountProvider);

    final pendingKey = GlobalKey<_AdminTokoPendingTransfersCardState>();

    return Scaffold(
      appBar: const ModuleDashboardAppBar(title: 'Admin Toko'),
      body: RoleMenuBody(
        child: RefreshIndicator(
        onRefresh: () async {
          await pendingKey.currentState?._load();
        },
        child: ResponsiveLayout.roleMenuListView(
          context: context,
          children: [
            Padding(
              padding: ResponsiveLayout.roleMenuHeaderPadding,
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
                    icon: Icons.receipt_long,
                    label: 'ORDER & BAYAR',
                    iconColor: Colors.blue,
                    onTap: () =>
                        pushAppRoute(context, AppRoutes.adminTokoOrders),
                  ),
                  ModuleMenuEntry(
                    icon: Icons.inventory_2,
                    label: 'STOK ETALASE',
                    iconColor: Colors.teal,
                    onTap: () => pushAppRoute(context, AppRoutes.adminTokoStock),
                  ),
                  ModuleMenuEntry(
                    icon: Icons.inventory,
                    label: 'MUTASI STOK',
                    iconColor: Colors.green,
                    onTap: () =>
                        pushAppRoute(context, AppRoutes.adminTokoStockMutation),
                  ),
                  ModuleMenuEntry(
                    icon: Icons.warehouse_outlined,
                    label: ModuleMenuGroupLabels.warehouse,
                    iconColor: Colors.deepOrange,
                    onTap: () => _openWarehouseSheet(context),
                  ),
                  ModuleMenuEntry(
                    icon: Icons.build_circle_outlined,
                    label: ModuleMenuGroupLabels.workshop,
                    iconColor: Colors.indigo,
                    badgeCount: workshopReceiptPending > 0
                        ? workshopReceiptPending
                        : null,
                    onTap: () => _openWorkshopSheet(context),
                  ),
                  ModuleMenuEntry(
                    icon: Icons.hub_outlined,
                    label: ModuleMenuGroupLabels.antarToko,
                    iconColor: Colors.blueGrey,
                    onTap: () => _openAntarTokoSheet(context),
                  ),
                  ModuleMenuEntry(
                    icon: DashboardMenuIcons.kelolaPengguna,
                    label: 'KARYAWAN',
                    iconColor: Colors.purple,
                    onTap: () =>
                        pushAppRoute(context, AppRoutes.adminTokoEmployees),
                  ),
                  ModuleMenuEntry(
                    icon: DashboardMenuIcons.pelanggan,
                    label: 'PELANGGAN',
                    iconColor: Colors.cyan,
                    onTap: () => pushAppRoute(context, AppRoutes.customers),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _AdminTokoPendingTransfersCard(
                key: pendingKey,
                onSeeAll: () =>
                    pushAppRoute(context, AppRoutes.adminTokoGoodsTransfer),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
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

  String _namaBarang(Map<String, dynamic> t) {
    return (t['item_name'] ?? t['nama_item'] ?? '-').toString().trim();
  }

  /// Masuk: cabang pengirim. Keluar: tujuan pengiriman (barang dari toko ini).
  String _asalBarang(Map<String, dynamic> t, String currentBranchId) {
    final fromN =
        (t['from_branch_name'] ?? t['from_branch_id'] ?? '-').toString();
    final toN = (t['to_branch_name'] ?? t['to_branch_id'] ?? '-').toString();
    final isIncoming = (t['to_branch_id']?.toString() ?? '') == currentBranchId;
    if (isIncoming) return fromN.isEmpty ? '-' : fromN;
    return toN.isEmpty ? '-' : 'Ke $toN';
  }

  int _comparePendingCreated(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ta = a['created_at']?.toString() ?? '';
    final tb = b['created_at']?.toString() ?? '';
    return tb.compareTo(ta);
  }

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
                    'TRANSFER PENDING',
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _PendingChip(
                      label: 'MASUK',
                      count: incoming.length,
                      color: Colors.blue,
                      icon: Icons.arrow_downward,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PendingChip(
                      label: 'KELUAR',
                      count: outgoing.length,
                      color: Colors.orange,
                      icon: Icons.arrow_upward,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _load,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    icon: const Icon(Icons.refresh_rounded),
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    final sorted = List<Map<String, dynamic>>.from(_pending)
                      ..sort(_comparePendingCreated);
                    final cs = Theme.of(context).colorScheme;
                    final rows = <DataRow>[];
                    for (var i = 0; i < sorted.length && i < 12; i++) {
                      final t = sorted[i];
                      final isIncoming =
                          (t['to_branch_id']?.toString() ?? '') == branchId;
                      rows.add(
                        DataRow(
                          color: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.hovered)) {
                              return cs.primary.withValues(alpha: 0.05);
                            }
                            return i.isOdd
                                ? cs.surfaceContainerHighest
                                    .withValues(alpha: 0.4)
                                : null;
                          }),
                          cells: [
                            DataCell(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _namaBarang(t),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    isIncoming ? 'Masuk' : 'Keluar',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: isIncoming
                                          ? Colors.blue.shade800
                                          : Colors.orange.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DataCell(
                              Text(
                                _asalBarang(t, branchId),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            DataCell(
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '${_asInt(t['quantity'] ?? t['qty'])}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: constraints.maxWidth,
                              ),
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(
                                  cs.surfaceContainerHigh,
                                ),
dataRowMinHeight: 44,
                                dataRowMaxHeight: 72,
                                columnSpacing: 12,
                                horizontalMargin: 8,
                                showCheckboxColumn: false,
                                dividerThickness: 0.5,
                                columns: const [
                                  DataColumn(
                                    label: Text(
                                      'Nama barang',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Asal',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    numeric: true,
                                    label: Text(
                                      'Qty',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: color,
              ),
            ),
          ),
          Chip(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
            label: Text(
              count.toString(),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: color,
              ),
            ),
            backgroundColor: color.withValues(alpha: 0.10),
            side: BorderSide(color: color.withValues(alpha: 0.20)),
          ),
        ],
      ),
    );
  }
}
