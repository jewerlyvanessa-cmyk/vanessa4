import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/modules/owner/data/owner_dashboard_service.dart';
import 'package:vanessa3/modules/owner/widgets/owner_global_orders_section.dart';
import 'package:vanessa3/modules/owner/widgets/owner_summary_card.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/routes/app_navigator.dart';
import 'package:vanessa3/routes/app_routes.dart';
import 'package:vanessa3/shared_widgets/module_dashboard_app_bar.dart';
import 'package:vanessa3/shared_widgets/role_menu_body.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/utils/business_calendar.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

/// Dashboard Owner — kartu ringkasan + daftar order global.
class OwnerMainPage extends ConsumerStatefulWidget {
  const OwnerMainPage({super.key});

  @override
  ConsumerState<OwnerMainPage> createState() => _OwnerMainPageState();
}

class _OwnerMainPageState extends ConsumerState<OwnerMainPage> {
  DateTime _selectedDate = BusinessCalendar.todayWibDateOnly();
  bool _loading = true;
  String _error = '';
  OwnerDashboardSnapshot _snapshot = OwnerDashboardSnapshot.empty;
  List<Map<String, dynamic>> _ordersRaw = const [];

  String get _dateYmd =>
      _selectedDate == BusinessCalendar.todayWibDateOnly()
          ? BusinessCalendar.todayYmd()
          : DateFormat('yyyy-MM-dd').format(_selectedDate);

  final _moneyFmt = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ws = ref.read(webSocketProvider);
      if (ws == null) {
        ref.read(webSocketProvider.notifier).initializeAfterLogin();
      }
      _loadDashboard(forceRefresh: true);
    });
  }

  Future<void> _loadDashboard({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final branches = ref.read(userStateProvider).branches;
      final data = await OwnerDashboardService.loadDashboard(
        branches: branches,
        dateYmd: _dateYmd,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = data.snapshot;
        _ordersRaw = data.orders;
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

  Future<void> _onOrdersDateChanged(DateTime date) async {
    setState(() => _selectedDate = date);
    OwnerDashboardService.invalidateCache();
    await _loadDashboard(forceRefresh: true);
  }

  Future<void> _onPullRefresh() async {
    OwnerDashboardService.invalidateCache();
    await _loadDashboard(forceRefresh: true);
  }

  Widget _summaryCards(BuildContext context) {
    final branchCount = ref.read(userStateProvider).branches.length;
    final snap = _snapshot;
    final cardLoading = _loading;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 900 ? 3 : (w >= 520 ? 2 : 1);
        const gap = 12.0;
        final cardW = cols == 1
            ? w
            : (w - gap * (cols - 1)) / cols;

        final cards = [
          OwnerSummaryCard(
            icon: Icons.trending_up,
            color: Colors.orange,
            title: 'PENJUALAN GLOBAL',
            primaryText: _moneyFmt.format(snap.salesAmount),
            secondaryText:
                '${snap.salesPaymentCount} pembayaran · $branchCount cabang',
            loading: cardLoading,
            onTap: () =>
                pushAppRoute(context, AppRoutes.ownerSalesGlobal),
          ),
          OwnerSummaryCard(
            icon: Icons.currency_exchange,
            color: Colors.deepOrange,
            title: 'BUYBACK GLOBAL',
            primaryText: _moneyFmt.format(snap.buybackAmount),
            secondaryText:
                '${snap.buybackPaymentCount} transaksi · $branchCount cabang',
            loading: cardLoading,
            onTap: () =>
                pushAppRoute(context, AppRoutes.ownerBuybackGlobal),
          ),
          OwnerSummaryCard(
            icon: Icons.inventory,
            color: Colors.teal,
            title: 'STOK GLOBAL',
            primaryText: '${snap.stockReadyQty} unit',
            secondaryText: snap.stockReadySku > 0
                ? '${snap.stockReadySku} SKU ready · $branchCount cabang'
                : 'Status ready · $branchCount cabang',
            loading: cardLoading,
            onTap: () => pushAppRoute(context, AppRoutes.ownerGlobalStock),
          ),
        ];

        if (cols == 1) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: gap),
                cards[i],
              ],
            ],
          );
        }

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: cards
              .map((c) => SizedBox(width: cardW, child: c))
              .toList(),
        );
      },
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

    return Scaffold(
      appBar: const ModuleDashboardAppBar(title: 'Owner'),
      body: RoleMenuBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: ResponsiveLayout.roleMenuHeaderPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UserBranchRoleHeader(),
                  SizedBox(height: 8),
                  Text(
                    'Ringkasan hari ini. Ketuk kartu untuk detail. Daftar order di bawah.',
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onPullRefresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: ResponsiveLayout.roleMenuHorizontalPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _summaryCards(context),
                      if (_error.isNotEmpty && !_loading) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      OwnerGlobalOrdersSection(
                        ordersRaw: _ordersRaw,
                        loading: _loading,
                        error: '',
                        selectedDate: _selectedDate,
                        onDateChanged: _onOrdersDateChanged,
                        onRefresh: _onPullRefresh,
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
