import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';
import 'workshop_orders_page.dart';
import '../../stockist/pages/service_incoming_page.dart';
import 'material_stock_page.dart';
import 'workshop_reports_page.dart';
import '../../admin_toko/pages/goods_transfer_page.dart';
import 'return_to_store_page.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/providers/workshop_dashboard_provider.dart';
import 'package:vanessa3/providers/workshop_service_incoming_provider.dart';
import 'package:vanessa3/providers/workshop_return_pending_provider.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/shared_widgets/module_destination_sheet.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';
import 'package:vanessa3/shared_widgets/module_menu_group_labels.dart';
import 'package:vanessa3/routes/app_navigator.dart';
import 'package:vanessa3/routes/app_routes.dart' hide SwitchBranchRoleWidget;

class AdminWorkshopMainPage extends ConsumerStatefulWidget {
  const AdminWorkshopMainPage({super.key});

  @override
  ConsumerState<AdminWorkshopMainPage> createState() =>
      _AdminWorkshopMainPageState();
}

class _AdminWorkshopMainPageState extends ConsumerState<AdminWorkshopMainPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(workshopServiceIncomingCountProvider.notifier).refresh();
      ref.read(workshopReturnPendingCountProvider.notifier).refresh();
      ref.read(workshopDashboardProvider.notifier).listenToUserStateChanges();
    });
  }

  void _openTokoSheet(BuildContext context) {
    showModuleDestinationSheet(
      context,
      title: ModuleMenuGroupLabels.sheetToko,
      options: [
        ModuleDestinationOption(
          label: 'Service dari toko',
          subtitle: 'Persetujuan service/custom masuk workshop',
          icon: Icons.inventory_2_outlined,
          iconColor: Colors.deepOrange,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ServiceIncomingPage(),
              ),
            );
            if (!context.mounted) return;
            ref.read(workshopServiceIncomingCountProvider.notifier).refresh();
            ref.read(workshopDashboardProvider.notifier).refresh();
          },
        ),
        ModuleDestinationOption(
          label: 'Kirim ke toko',
          subtitle: 'Order selesai — kirim balik ke etalase',
          icon: Icons.local_shipping_outlined,
          iconColor: Colors.indigo,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ReturnToStorePage(),
              ),
            );
            if (!context.mounted) return;
            ref.read(workshopReturnPendingCountProvider.notifier).refresh();
          },
        ),
      ],
    );
  }

  void _openAntarWorkshopSheet(BuildContext context) {
    showModuleDestinationSheet(
      context,
      title: ModuleMenuGroupLabels.sheetAntarWorkshop,
      options: [
        ModuleDestinationOption(
          label: 'Kirim / terima barang',
          subtitle: 'Transfer antar cabang workshop (bengkel)',
          icon: Icons.hub_outlined,
          iconColor: Colors.blueGrey,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const GoodsTransferPage(),
            ),
          ),
        ),
      ],
    );
  }

  void _onRealtimeUpdate(Map<String, dynamic> update) {
    final type = (update['type'] ?? '').toString();
    final event = (update['event'] ?? '').toString();
    final shouldRefresh = type == 'order_update' ||
        type == 'workshop_assignment' ||
        event == 'workshop_service_pending' ||
        event == 'workshop_approved' ||
        event == 'workshop_assigned' ||
        event == 'workshop_in_progress' ||
        event == 'workshop_done_tukang';
    if (!shouldRefresh) return;

    ref.read(workshopDashboardProvider.notifier).refresh();
    ref.read(workshopServiceIncomingCountProvider.notifier).refresh();
    ref.read(workshopReturnPendingCountProvider.notifier).refresh();

    final msg = update['message']?.toString();
    if (msg != null && msg.isNotEmpty && mounted) {
      _showWorkshopNotification(context, msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isServerHealthy = ref.watch(healthCheckProvider);
    final dashboardAsync = ref.watch(workshopDashboardProvider);
    final inProgressCount = dashboardAsync.maybeWhen(
      data: (d) => d.inProgressOrders,
      orElse: () => 0,
    );
    final pendingAntrianCount = dashboardAsync.maybeWhen(
      data: (d) => d.pendingOrders,
      orElse: () => 0,
    );
    final pendingApprovalCount = ref.watch(workshopServiceIncomingCountProvider);
    final returnPendingCount = ref.watch(workshopReturnPendingCountProvider);
    final tokoBadge = pendingApprovalCount + returnPendingCount;

    ref.listen(userStateProvider, (previous, next) {
      if (next.userId != null && next.role.isNotEmpty) {
        final webSocketChannel = ref.read(webSocketProvider);
        if (webSocketChannel == null) {
          ref.read(webSocketProvider.notifier).initializeAfterLogin();
        }
        ref.read(workshopServiceIncomingCountProvider.notifier).refresh();
      }
    });

    ref.listen(realTimeOrderUpdatesProvider, (previous, next) {
      next.whenData(_onRealtimeUpdate);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Workshop'),
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/logo_bulat.png', fit: BoxFit.contain),
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ModuleMenuGrid(
                  minCrossAxisCount: 4,
                  entries: [
                    ModuleMenuEntry(
                      icon: Icons.build,
                      label: 'ANTRIAN PEKERJAAN',
                      iconColor: Colors.blue,
                      badgeCount:
                          pendingAntrianCount > 0 ? pendingAntrianCount : null,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const WorkshopOrdersPage(),
                        ),
                      ),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.engineering_outlined,
                      label: 'ON PROGRESS',
                      iconColor: Colors.orange,
                      badgeCount:
                          inProgressCount > 0 ? inProgressCount : null,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const WorkshopOrdersPage(
                            viewMode: WorkshopOrdersViewMode.inProgress,
                          ),
                        ),
                      ),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.inventory,
                      label: 'STOK MATERIAL',
                      iconColor: Colors.green,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MaterialStockPage(),
                        ),
                      ),
                    ),
                    ModuleMenuEntry(
                      icon: DashboardMenuIcons.laporan,
                      label: 'LAPORAN WORKSHOP',
                      iconColor: Colors.purple,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const WorkshopReportsPage(),
                        ),
                      ),
                    ),
                    ModuleMenuEntry(
                      icon: DashboardMenuIcons.kelolaPengguna,
                      label: 'KARYAWAN',
                      iconColor: Colors.purple,
                      onTap: () => pushAppRoute(
                        context,
                        AppRoutes.adminWorkshopEmployees,
                      ),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.storefront_outlined,
                      label: ModuleMenuGroupLabels.toko,
                      iconColor: Colors.deepOrange,
                      badgeCount: tokoBadge > 0 ? tokoBadge : null,
                      onTap: () => _openTokoSheet(context),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.hub_outlined,
                      label: ModuleMenuGroupLabels.antarWorkshop,
                      iconColor: Colors.blueGrey,
                      onTap: () => _openAntarWorkshopSheet(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showWorkshopNotification(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pemberitahuan Workshop: $message'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {},
        ),
      ),
    );
  }
}
