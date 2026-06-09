import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/modules/owner/data/owner_dashboard_service.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/routes/app_navigator.dart';
import 'package:vanessa3/routes/app_routes.dart';
import 'package:vanessa3/shared_widgets/module_destination_sheet.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';
import 'package:vanessa3/shared_widgets/module_dashboard_app_bar.dart';
import 'package:vanessa3/shared_widgets/role_menu_body.dart';
import 'package:vanessa3/shared_widgets/global_summary_card.dart';
import 'package:vanessa3/utils/business_calendar.dart';
import 'package:vanessa3/utils/responsive_layout.dart';
import 'package:vanessa3/providers/manager_dashboard_provider.dart';

class ManajerMainPage extends ConsumerStatefulWidget {
  const ManajerMainPage({super.key});

  @override
  ConsumerState<ManajerMainPage> createState() => _ManajerMainPageState();
}

class _ManajerMainPageState extends ConsumerState<ManajerMainPage> {
  bool _loadingSummary = true;
  OwnerDashboardSnapshot _snapshot = OwnerDashboardSnapshot.empty;

  final _moneyFmt = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(managerDashboardProvider.notifier).listenToUserStateChanges();
      _loadSummary();
    });
  }

  Future<void> _loadSummary({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() => _loadingSummary = true);
    try {
      final snap = await OwnerDashboardService.loadSummary(
        dateYmd: BusinessCalendar.todayYmd(),
        forceRefresh: forceRefresh,
        globalScope: true,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _loadingSummary = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _snapshot = OwnerDashboardSnapshot.empty;
        _loadingSummary = false;
      });
    }
  }

  void _openLaporanHarian(BuildContext context) {
    showModuleDestinationSheet(
      context,
      title: 'Laporan harian',
      options: [
        ModuleDestinationOption(
          label: 'Laporan penjualan',
          subtitle: 'Penjualan hari ini per cabang',
          icon: Icons.trending_up,
          iconColor: Colors.orange,
          onTap: () => pushAppRoute(context, AppRoutes.manajerSalesToday),
        ),
        ModuleDestinationOption(
          label: 'Laporan buyback',
          subtitle: 'Buyback hari ini per cabang',
          icon: Icons.currency_exchange,
          iconColor: Colors.deepOrange,
          onTap: () => pushAppRoute(context, AppRoutes.manajerBuybackReport),
        ),
      ],
    );
  }

  void _openStok(BuildContext context) {
    showModuleDestinationSheet(
      context,
      title: 'Stok',
      options: [
        ModuleDestinationOption(
          label: 'Stok global',
          subtitle: 'Inventori seluruh cabang',
          icon: DashboardMenuIcons.stokGlobal,
          iconColor: Colors.purple,
          onTap: () => pushAppRoute(context, AppRoutes.manajerGlobalStock),
        ),
        ModuleDestinationOption(
          label: 'Stok per cabang',
          subtitle: 'Inventori detail per toko',
          icon: Icons.store,
          iconColor: Colors.green,
          onTap: () => pushAppRoute(context, AppRoutes.manajerStockCabang),
        ),
        ModuleDestinationOption(
          label: 'Laporan rekap stok',
          subtitle: 'Ringkasan per jenis & periode',
          icon: Icons.inventory_2_outlined,
          iconColor: Colors.teal,
          onTap: () => pushAppRoute(context, AppRoutes.manajerStockReport),
        ),
      ],
    );
  }

  Widget _summaryCards(BuildContext context) {
    final snap = _snapshot;
    final tokoCount = snap.branchCount > 0 ? snap.branchCount : 0;
    final stockBranchCount = snap.stockBranchCount > 0
        ? snap.stockBranchCount
        : tokoCount;

    return GlobalSummaryCardsLayout(
      cards: [
        GlobalSummaryCard(
          icon: Icons.trending_up,
          color: Colors.orange,
          title: 'PENJUALAN GLOBAL',
          primaryText: _moneyFmt.format(snap.salesAmount),
          secondaryText:
              '${snap.salesPaymentCount} pembayaran · $tokoCount toko',
          loading: _loadingSummary,
          onTap: () => pushAppRoute(context, AppRoutes.manajerSalesToday),
        ),
        GlobalSummaryCard(
          icon: Icons.currency_exchange,
          color: Colors.deepOrange,
          title: 'BUYBACK GLOBAL',
          primaryText: _moneyFmt.format(snap.buybackAmount),
          secondaryText:
              '${snap.buybackPaymentCount} transaksi · $tokoCount toko',
          loading: _loadingSummary,
          onTap: () => pushAppRoute(context, AppRoutes.manajerBuybackReport),
        ),
        GlobalSummaryCard(
          icon: Icons.inventory,
          color: Colors.teal,
          title: 'STOK GLOBAL',
          primaryText: '${snap.stockReadyQty} unit',
          secondaryText: snap.stockReadySku > 0
              ? '${snap.stockReadySku} SKU ready · $stockBranchCount cabang'
              : 'Status ready · $stockBranchCount cabang',
          loading: _loadingSummary,
          onTap: () => pushAppRoute(context, AppRoutes.manajerGlobalStock),
        ),
      ],
    );
  }

  void _showWorkNotification(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pemberitahuan Manajer: $message'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(userStateProvider, (previous, next) {
      if (next.userId != null && next.role.isNotEmpty) {
        final webSocketChannel = ref.read(webSocketProvider);
        if (webSocketChannel == null) {
          ref.read(webSocketProvider.notifier).initializeAfterLogin();
        }
      }
    });

    ref.listen(realTimeOrderUpdatesProvider, (previous, next) {
      next.whenData((update) {
        if (update['type'] == 'order_update' ||
            update['type'] == 'manager_alert') {
          ref.read(managerDashboardProvider.notifier).refresh();
          _loadSummary(forceRefresh: true);
          _showWorkNotification(context, update['data']);
        }
      });
    });

    return Scaffold(
      appBar: const ModuleDashboardAppBar(title: 'Manajer'),
      body: RoleMenuBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: ResponsiveLayout.roleMenuHeaderPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UserBranchRoleHeader(),
                  SizedBox(height: 8),
                  Text(
                    'Ringkasan global hari ini. Ketuk kartu untuk detail.',
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  OwnerDashboardService.invalidateCache();
                  await Future.wait([
                    _loadSummary(forceRefresh: true),
                    ref.read(managerDashboardProvider.notifier).refresh(),
                  ]);
                },
                child: SingleChildScrollView(
                  physics: ResponsiveLayout.scrollPhysics,
                  padding: ResponsiveLayout.roleMenuHorizontalPadding.copyWith(
                    bottom: ResponsiveLayout.scrollEndGap(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _summaryCards(context),
                      const SizedBox(height: 20),
                      ModuleMenuGrid(
                          minCrossAxisCount: 4,
                          entries: [
                            ModuleMenuEntry(
                              icon: Icons.bar_chart,
                              label: 'PERFORMA CABANG',
                              iconColor: Colors.blue,
                              onTap: () => pushAppRoute(
                                context,
                                AppRoutes.manajerBranchPerformance,
                              ),
                            ),
                            ModuleMenuEntry(
                              icon: DashboardMenuIcons.laporan,
                              label: 'LAPORAN HARIAN',
                              iconColor: Colors.orange,
                              onTap: () => _openLaporanHarian(context),
                            ),
                            ModuleMenuEntry(
                              icon: Icons.account_balance_wallet_outlined,
                              label: 'PENCATATAN KEUANGAN',
                              iconColor: Colors.indigo,
                              onTap: () => pushAppRoute(
                                context,
                                AppRoutes.manajerKeuangan,
                              ),
                            ),
                            ModuleMenuEntry(
                              icon: DashboardMenuIcons.stokGlobal,
                              label: 'STOK',
                              iconColor: Colors.teal,
                              onTap: () => _openStok(context),
                            ),
                            ModuleMenuEntry(
                              icon: Icons.fact_check_outlined,
                              label: 'STOK OPNAME',
                              iconColor: Colors.blueGrey,
                              onTap: () => pushAppRoute(
                                context,
                                AppRoutes.manajerStockOpname,
                              ),
                            ),
                            ModuleMenuEntry(
                              icon: DashboardMenuIcons.kelolaPengguna,
                              label: 'USER',
                              iconColor: Colors.purple,
                              onTap: () => pushAppRoute(
                                context,
                                AppRoutes.manajerEmployees,
                              ),
                            ),
                            ModuleMenuEntry(
                              icon: Icons.fact_check,
                              label: 'ORDER SELESAI',
                              iconColor: Colors.green,
                              onTap: () => pushAppRoute(
                                context,
                                AppRoutes.manajerCompletedOrdersToday,
                              ),
                            ),
                            ModuleMenuEntry(
                              icon: DashboardMenuIcons.pelanggan,
                              label: 'PELANGGAN',
                              iconColor: Colors.cyan,
                              onTap: () =>
                                  pushAppRoute(context, AppRoutes.customers),
                            ),
                            ModuleMenuEntry(
                              icon: Icons.business_outlined,
                              label: 'SUPPLIER',
                              iconColor: Colors.brown,
                              onTap: () => pushAppRoute(
                                context,
                                AppRoutes.manajerSuppliers,
                              ),
                            ),
                          ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
