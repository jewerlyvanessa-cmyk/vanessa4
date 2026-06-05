import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';

import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';
import 'package:vanessa3/shared_widgets/module_dashboard_app_bar.dart';
import 'package:vanessa3/shared_widgets/role_menu_body.dart';
import 'package:vanessa3/utils/responsive_layout.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:intl/intl.dart';

import 'stock_bulk_input_page.dart';
import 'stock_standard_input_page.dart';
import 'stock_reprint_qr_page.dart';
import 'reports_page.dart';
import 'package:vanessa3/routes/app_navigator.dart';
import 'package:vanessa3/routes/app_routes.dart';

class StockistMainPage extends ConsumerStatefulWidget {
  const StockistMainPage({super.key});

  @override
  ConsumerState<StockistMainPage> createState() => _StockistMainPageState();
}

class _StockistMainPageState extends ConsumerState<StockistMainPage> {
  Future<List<Map<String, dynamic>>>? _todayFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _todayFuture ??= _loadTodayInputs();
  }

  String _isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<List<Map<String, dynamic>>> _loadTodayInputs() async {
    final user = ref.read(userStateProvider);
    final uid = user.userId;
    final branchId = user.branch.trim();
    if (uid == null || branchId.isEmpty) return const [];

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final res = await ApiClient.get(
      '/items',
      query: <String, String>{
        'branch_id': branchId,
        'mine': '1',
        'start_date': _isoDate(start),
        'end_date': _isoDate(end),
        'limit': '50',
      },
    );
    if (res.statusCode != 200) {
      String msg = 'Gagal memuat input stok hari ini (${res.statusCode})';
      try {
        final m = jsonDecode(res.body);
        if (m is Map && m['error'] != null) msg = m['error'].toString();
      } catch (_) {}
      throw Exception(msg);
    }
    final decoded = jsonDecode(res.body);
    final list = decoded is List ? decoded : const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  void _refreshToday() {
    setState(() {
      _todayFuture = _loadTodayInputs();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ModuleDashboardAppBar(title: 'Stockist'),
      body: RoleMenuBody(
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
                  onTap: () => pushAppRoute(context, AppRoutes.stockistStock),
                ),
                ModuleMenuEntry(
                  icon: Icons.fact_check_outlined,
                  label: 'STOK OPNAME',
                  iconColor: Colors.blueGrey,
                  onTap: () =>
                      pushAppRoute(context, AppRoutes.stockistStockOpname),
                ),
                ModuleMenuEntry(
                  icon: Icons.qr_code_2,
                  label: 'CETAK ULANG LABEL',
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
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: _TodayStockInputsCard(
              future: _todayFuture,
              onRefresh: _refreshToday,
            ),
          ),
          const SizedBox(height: 24),
        ],
        ),
      ),
    );
  }
}

class _TodayStockInputsCard extends ConsumerWidget {
  const _TodayStockInputsCard({
    required this.future,
    required this.onRefresh,
  });

  final Future<List<Map<String, dynamic>>>? future;
  final VoidCallback onRefresh;

  int _asInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userStateProvider);
    final branchId = user.branch.trim();
    final show = user.userId != null && branchId.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'INPUT STOK HARI INI',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: show ? onRefresh : null,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!show)
              const Text('Sesi/cabang belum lengkap.')
            else
              FutureBuilder<List<Map<String, dynamic>>>(
                future: future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasError) {
                    return Text(
                      snap.error.toString(),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    );
                  }
                  final items = snap.data ?? const [];
                  if (items.isEmpty) {
                    return const Text('Belum ada input stok hari ini.');
                  }
                  final totalQty =
                      items.fold<int>(0, (s, i) => s + _asInt(i['quantity']));

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${items.length} SKU • Total qty: $totalQty',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      ...items.take(8).map((it) {
                        final code = (it['kode_produk'] ?? it['item_code'] ?? '—')
                            .toString()
                            .trim();
                        final name = (it['name'] ?? '—').toString().trim();
                        final qty = _asInt(it['quantity']);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 150,
                                child: Text(
                                  code.isEmpty ? '—' : code,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 64,
                                child: Text(
                                  '$qty',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (items.length > 8) ...[
                        const SizedBox(height: 4),
                        Text(
                          '+${items.length - 8} lainnya (lihat menu Laporan Input Stok)',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
