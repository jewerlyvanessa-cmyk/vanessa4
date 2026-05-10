import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/widgets/qr_scan_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';
import 'faktur_page.dart';
import 'package:vanessa3/providers/order_today_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/utils/order_status_ui.dart';
import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
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

/// Satu baris tabel order hari ini (satu item dalam order, atau order tanpa item).
class _CsOrderTableLine {
  _CsOrderTableLine({required this.order, this.item});
  final Map<String, dynamic> order;
  final Map<String, dynamic>? item;
}

class CSMainPage extends ConsumerStatefulWidget {
  const CSMainPage({super.key});

  @override
  ConsumerState<CSMainPage> createState() => _CSMainPageState();
}

class _CSMainPageState extends ConsumerState<CSMainPage> {
  String _csOrderSearchQuery = '';

  /// `all` | `open` (belum selesai) | `done` (selesai / terjual)
  String _csTodayStatusFilter = 'all';
  bool _refreshingCsToday = false;

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

  /// Baris order item: backend `order_items` sering dikirim sebagai `items` atau `order_items`.
  List<dynamic> _orderLineItemRows(Map<String, dynamic> order) {
    for (final key in const ['items', 'order_items']) {
      final v = order[key];
      if (v is List && v.isNotEmpty) return v;
    }
    return const [];
  }

  List<_CsOrderTableLine> _flattenCsTodayOrders(List<dynamic> orders) {
    final out = <_CsOrderTableLine>[];
    for (final raw in orders) {
      if (raw is! Map) continue;
      final order = Map<String, dynamic>.from(raw);
      final itemRows = _orderLineItemRows(order);
      if (itemRows.isNotEmpty) {
        for (final it in itemRows) {
          if (it is Map) {
            out.add(
              _CsOrderTableLine(
                order: order,
                item: Map<String, dynamic>.from(it),
              ),
            );
          }
        }
      } else {
        out.add(_CsOrderTableLine(order: order, item: null));
      }
    }
    return out;
  }

  String _lineItemName(Map<String, dynamic>? item) {
    if (item == null) return '—';
    for (final key in const ['nama_item', 'item_name', 'name']) {
      final n = item[key]?.toString().trim();
      if (n != null && n.isNotEmpty) return n;
    }
    return '—';
  }

  /// Berat dari `order_items`: kolom DB biasanya `weight`; JSON lama bisa `berat` / `item_weight`.
  String _lineBerat(Map<String, dynamic>? item) {
    if (item == null) return '—';
    dynamic raw;
    for (final key in const ['berat', 'weight', 'item_weight']) {
      final v = item[key];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isEmpty) continue;
      raw = v;
      break;
    }
    if (raw == null) return '—';
    final b = double.tryParse(raw.toString());
    if (b == null || b <= 0) return '—';
    return '${raw.toString()} g';
  }

  String _lineTotalDisplay(
    Map<String, dynamic>? item,
    Map<String, dynamic> order,
  ) {
    // Selalu pakai total order SETELAH pembulatan (kolom orders.jumlah).
    final raw = order['jumlah'] ?? order['total'];
    if (raw == null) return '—';
    final d = double.tryParse(raw.toString());
    if (d == null || d == 0) return '—';
    return 'Rp ${_fmtRp(raw)}';
  }

  /// Field item order (API bisa memakai beberapa nama kunci).
  String _itemFieldStr(Map<String, dynamic>? item, List<String> keys) {
    if (item == null) return '—';
    for (final k in keys) {
      final v = item[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return '—';
  }

  String _itemKodeLine(Map<String, dynamic>? item) =>
      _itemFieldStr(item, const ['kode_produk', 'item_code', 'item_id']);

  String _itemQtyLine(Map<String, dynamic>? item) =>
      _itemFieldStr(item, const ['qty', 'quantity', 'item_qty']);

  String _itemHargaPerGramLine(Map<String, dynamic>? item) {
    if (item == null) return '—';
    final raw = item['harga_per_gram'];
    final d = double.tryParse(raw?.toString() ?? '');
    if (d != null && d > 0) return 'Rp ${_fmtRp(raw)}';
    return '—';
  }

  String _itemKategoriLine(Map<String, dynamic>? item) =>
      _itemFieldStr(item, const ['kategori', 'item_kategori']);

  String _itemJenisLine(Map<String, dynamic>? item) =>
      _itemFieldStr(item, const ['jenis', 'item_jenis']);

  String _itemTipeLine(Map<String, dynamic>? item) =>
      _itemFieldStr(item, const ['tipe', 'item_tipe']);

  String _itemMaterialLine(Map<String, dynamic>? item) =>
      _itemFieldStr(item, const ['material', 'item_material']);

  Future<void> _scanAndFillSearch() async {
    final value = await pushQrScanPage(context, title: 'Scan QR Order');
    if (!mounted || value == null || value.isEmpty) return;
    setState(() => _csOrderSearchQuery = value);
  }

  String _itemKadarLine(Map<String, dynamic>? item) =>
      _itemFieldStr(item, const ['purity', 'kadar', 'item_purity']);

  bool _csOrderMatchesStatus(Map<String, dynamic> order) {
    switch (_csTodayStatusFilter) {
      case 'open':
        final s = order['status']?.toString().toLowerCase() ?? '';
        return !const {'completed', 'sold', 'cancelled'}.contains(s);
      case 'done':
        final s = order['status']?.toString().toLowerCase() ?? '';
        return const {'completed', 'sold'}.contains(s);
      default:
        return true;
    }
  }

  bool _csOrderMatchesSearch(Map<String, dynamic> order, String q) {
    if (q.isEmpty) return true;
    if ('${order['order_id']}'.toLowerCase().contains(q)) return true;
    final nota = (order['order_number'] ?? '').toString().trim().toLowerCase();
    if (nota.isNotEmpty && nota.contains(q)) return true;
    if ((order['customer_name'] ?? '').toString().toLowerCase().contains(q)) {
      return true;
    }
    final phone = (order['customer_phone'] ?? order['phone'] ?? '')
        .toString()
        .toLowerCase();
    if (phone.isNotEmpty && phone.contains(q)) return true;
    for (final it in _orderLineItemRows(order)) {
      if (it is! Map) continue;
      final m = Map<String, dynamic>.from(it);
      if (_lineItemName(m).toLowerCase().contains(q)) return true;
      final k = _itemKodeLine(m);
      if (k != '—' && k.toLowerCase().contains(q)) return true;
    }
    return false;
  }

  List<Map<String, dynamic>> _filteredCsTodayOrders(
    List<Map<String, dynamic>> orders,
  ) {
    final q = _csOrderSearchQuery.trim().toLowerCase();
    return orders
        .where((o) => _csOrderMatchesStatus(o) && _csOrderMatchesSearch(o, q))
        .toList();
  }

  int _countCsTodayTableLines(List<Map<String, dynamic>> orders) {
    var n = 0;
    for (final o in orders) {
      final items = _orderLineItemRows(o);
      n += items.isEmpty ? 1 : items.length;
    }
    return n;
  }

  Future<void> _refreshCsOrderToday() async {
    if (_refreshingCsToday) return;
    setState(() => _refreshingCsToday = true);
    try {
      await ref.read(orderTodayStatsProvider.notifier).refresh();
      await ref.read(todayOrdersProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _refreshingCsToday = false);
    }
  }

  Widget _csStatPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final baseSmall = Theme.of(context).textTheme.labelSmall;
    final pill = Container(
      margin: const EdgeInsets.only(right: 6, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 5),
          Text.rich(
            TextSpan(
              style: baseSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                height: 1.05,
              ),
              children: [
                TextSpan(text: '$label '),
                TextSpan(
                  text: value,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                    height: 1.05,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
          ),
        ],
      ),
    );

    if (onTap == null) return pill;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: pill,
    );
  }

  Widget _buildCsTodayOrdersTable(BuildContext context, List<dynamic> orders) {
    final lines = _flattenCsTodayOrders(orders);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final webWide = kIsWeb && !narrow;
    final mobileCellStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontSize: 12, height: 1.15);
    final mobileHeaderStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );

    Widget cell(
      String text, {
      int maxLines = 2,
      TextAlign align = TextAlign.start,
      Color? color,
      FontWeight? weight,
    }) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style:
            (narrow ? mobileCellStyle : Theme.of(context).textTheme.bodyMedium)
                ?.copyWith(color: color, fontWeight: weight),
      );
    }

    final columns = narrow
        ? <DataColumn>[
            DataColumn(label: dataTableColumnLabel('Order')),
            DataColumn(label: dataTableColumnLabel('Jenis')),
            DataColumn(label: dataTableColumnLabel('Nama item')),
            DataColumn(label: dataTableColumnLabel('Berat'), numeric: true),
            DataColumn(label: dataTableColumnLabel('Total'), numeric: true),
          ]
        : webWide
        ? <DataColumn>[
            DataColumn(label: dataTableColumnLabel('Order')),
            DataColumn(label: dataTableColumnLabel('Kode')),
            DataColumn(label: dataTableColumnLabel('Nama item')),
            DataColumn(label: dataTableColumnLabel('Kategori')),
            DataColumn(label: dataTableColumnLabel('Jenis')),
            DataColumn(label: dataTableColumnLabel('Tipe item')),
            DataColumn(label: dataTableColumnLabel('Material')),
            DataColumn(label: dataTableColumnLabel('Kadar')),
            DataColumn(label: dataTableColumnLabel('Berat'), numeric: true),
            DataColumn(label: dataTableColumnLabel('Qty'), numeric: true),
            DataColumn(label: dataTableColumnLabel('Harga/g'), numeric: true),
            DataColumn(label: dataTableColumnLabel('Total'), numeric: true),
            DataColumn(label: dataTableColumnLabel('Pelanggan')),
            DataColumn(label: dataTableColumnLabel('Status')),
            DataColumn(label: dataTableColumnLabel('Jenis')),
            const DataColumn(label: SizedBox(width: 44)),
          ]
        : <DataColumn>[
            DataColumn(label: dataTableColumnLabel('Order')),
            DataColumn(label: dataTableColumnLabel('Nama item')),
            DataColumn(label: dataTableColumnLabel('Berat'), numeric: true),
            DataColumn(label: dataTableColumnLabel('Total'), numeric: true),
            DataColumn(label: dataTableColumnLabel('Pelanggan')),
            DataColumn(label: dataTableColumnLabel('Status')),
            DataColumn(label: dataTableColumnLabel('Jenis')),
            const DataColumn(label: SizedBox(width: 44)),
          ];

    Future<void> openFaktur(Map<String, dynamic> order) async {
      Map<String, dynamic> fakturData = Map<String, dynamic>.from(order);
      final orderNumber = (order['order_number'] ?? '').toString().trim();

      if (orderNumber.isNotEmpty) {
        try {
          final uri = Uri.parse(
            '${NetworkConfig.baseUrl}/orders',
          ).replace(queryParameters: {'order_number': orderNumber});
          final resp = await http.get(
            uri,
            headers: NetworkConfig.defaultHeaders,
          );
          if (resp.statusCode == 200) {
            final decoded = jsonDecode(resp.body);
            if (decoded is Map<String, dynamic>) {
              fakturData = decoded;
            }
          }
        } catch (_) {
          // Fallback to current row data when detail fetch fails.
        }
      }

      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FakturPage(orderData: fakturData),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final rows = <DataRow>[];
    for (var idx = 0; idx < lines.length; idx++) {
      final line = lines[idx];
      final order = line.order;
      final item = line.item;
      final oid = order['order_id']?.toString() ?? 'N/A';
      final nama = _lineItemName(item);
      final berat = _lineBerat(item);
      final totalStr = _lineTotalDisplay(item, order);

      final cells = <DataCell>[
        DataCell(cell('#$oid', maxLines: 1)),
        if (narrow)
          DataCell(cell(order['order_type']?.toString() ?? '—', maxLines: 1)),
        if (!narrow && webWide) ...[
          DataCell(cell(_itemKodeLine(item), maxLines: 1)),
        ],
        DataCell(cell(nama)),
        if (!narrow && webWide) ...[
          DataCell(cell(_itemKategoriLine(item), maxLines: 1)),
          DataCell(cell(_itemJenisLine(item), maxLines: 1)),
          DataCell(cell(_itemTipeLine(item), maxLines: 1)),
          DataCell(cell(_itemMaterialLine(item), maxLines: 1)),
          DataCell(cell(_itemKadarLine(item), maxLines: 1)),
        ],
        DataCell(
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: cell(berat, maxLines: 1, align: TextAlign.end),
          ),
        ),
        if (!narrow && webWide)
          DataCell(
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: cell(
                _itemQtyLine(item),
                maxLines: 1,
                align: TextAlign.end,
              ),
            ),
          ),
        if (!narrow && webWide)
          DataCell(
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: cell(
                _itemHargaPerGramLine(item),
                maxLines: 1,
                align: TextAlign.end,
              ),
            ),
          ),
        DataCell(
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: cell(totalStr, maxLines: 1, align: TextAlign.end),
          ),
        ),
      ];

      if (!narrow) {
        cells.add(
          DataCell(
            cell(
              order['customer_name']?.toString().trim().isNotEmpty == true
                  ? order['customer_name'].toString()
                  : '—',
            ),
          ),
        );
        cells.add(
          DataCell(
            cell(
              _getStatusLabel(order['status']),
              maxLines: 1,
              color: _getStatusColor(order['status']),
              weight: FontWeight.w600,
            ),
          ),
        );
        cells.add(
          DataCell(cell(order['order_type']?.toString() ?? '—', maxLines: 1)),
        );
        cells.add(
          DataCell(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.visibility_outlined, size: 20),
                  tooltip: 'Cetak Faktur',
                  onPressed: () => openFaktur(order),
                ),
              ],
            ),
          ),
        );
      }

      rows.add(
        DataRow(
          color: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return colorScheme.primary.withValues(alpha: 0.07);
            }
            if (states.contains(WidgetState.pressed)) {
              return colorScheme.primary.withValues(alpha: 0.11);
            }
            return idx.isOdd
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
                : null;
          }),
          onSelectChanged: (_) => openFaktur(order),
          cells: cells,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final minW = narrow
            ? constraints.maxWidth
            : webWide
            ? 1280.0
            : 920.0;
        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: minW),
                child: DataTable(
                  headingTextStyle: narrow ? mobileHeaderStyle : null,
                  dataTextStyle: narrow ? mobileCellStyle : null,
                  headingRowColor: WidgetStateProperty.all(
                    colorScheme.surfaceContainerHigh,
                  ),
                  // Sedikit lebih rapat agar tinggi baris pas dengan teks.
                  dataRowMinHeight: narrow ? 34 : 40,
                  dataRowMaxHeight: narrow ? 42 : 52,
                  columnSpacing: narrow ? 10 : (webWide ? 14 : 18),
                  horizontalMargin: 10,
                  showCheckboxColumn: false,
                  dividerThickness: 0.6,
                  columns: columns,
                  rows: rows,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getStatusColor(String? status) => OrderStatusUi.color(status);

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
                      children: [const UserBranchRoleHeader()],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ModuleMenuGrid(
                  minCrossAxisCount: 4,
                  entries: [
                    ModuleMenuEntry(
                      icon: Icons.shopping_cart,
                      label: 'JUAL',
                      iconColor: Colors.orange,
                      onTap: () => Navigator.pushNamed(context, '/jual'),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.replay,
                      label: 'BUYBACK',
                      iconColor: Colors.green,
                      onTap: () => Navigator.pushNamed(context, '/buyback'),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.build,
                      label: 'SERVICE',
                      iconColor: Colors.blue,
                      onTap: () => Navigator.pushNamed(context, '/service'),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.design_services,
                      label: 'CUSTOM',
                      iconColor: Colors.purple,
                      onTap: () => Navigator.pushNamed(context, '/custom'),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.assignment_return,
                      label: 'AMBIL',
                      iconColor: Colors.indigo,
                      onTap: () => Navigator.pushNamed(context, '/ambil'),
                    ),
                    ModuleMenuEntry(
                      icon: Icons.today,
                      label: 'ORDER TODAY',
                      iconColor: Colors.amber,
                      onTap: () => Navigator.pushNamed(context, '/dashboard'),
                    ),
                    ModuleMenuEntry(
                      icon: DashboardMenuIcons.pelanggan,
                      label: 'PELANGGAN',
                      iconColor: Colors.cyan,
                      onTap: () => Navigator.pushNamed(context, '/customers'),
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
              const SizedBox(height: 16),

              // Order Today — ringkasan, filter, tabel
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Material(
                        elevation: 0,
                        color: Theme.of(context).colorScheme.surfaceContainerLow
                            .withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                          .withValues(alpha: 0.65),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Icon(
                                        Icons.today_rounded,
                                        size: 20,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Order hari ini · ${DateFormat('EEEE, d MMM yyyy', 'id_ID').format(DateTime.now())}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.2,
                                          ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Muat ulang',
                                    style: IconButton.styleFrom(
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.all(4),
                                    ),
                                    iconSize: 20,
                                    onPressed: _refreshingCsToday
                                        ? null
                                        : _refreshCsOrderToday,
                                    icon: _refreshingCsToday
                                        ? SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                          )
                                        : Icon(
                                            Icons.refresh_rounded,
                                            size: 20,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Consumer(
                                builder: (context, ref, _) {
                                  final orderStatsAsync = ref.watch(
                                    orderTodayStatsProvider,
                                  );
                                  return orderStatsAsync.when(
                                    loading: () => Wrap(
                                      children: List.generate(
                                        3,
                                        (i) => Padding(
                                          padding: const EdgeInsets.only(
                                            right: 6,
                                            bottom: 2,
                                          ),
                                          child: SizedBox(
                                            width: 72,
                                            height: 26,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest
                                                    .withValues(alpha: 0.5),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    error: (_, _) => Text(
                                      'Ringkasan tidak tersedia',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                        fontSize: 12,
                                      ),
                                    ),
                                    data: (stats) {
                                      return Wrap(
                                        spacing: 0,
                                        runSpacing: 6,
                                        alignment: WrapAlignment.start,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          _csStatPill(
                                            context,
                                            icon: Icons.receipt_long_rounded,
                                            label: 'Total order',
                                            value: '${stats.totalOrders}',
                                            accent: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            onTap: () => setState(
                                              () =>
                                                  _csTodayStatusFilter = 'all',
                                            ),
                                          ),
                                          _csStatPill(
                                            context,
                                            icon: Icons.hourglass_top_rounded,
                                            label: 'Pending',
                                            value: '${stats.pendingOrders}',
                                            accent: Colors.orange.shade800,
                                            onTap: () => setState(
                                              () =>
                                                  _csTodayStatusFilter = 'open',
                                            ),
                                          ),
                                          _csStatPill(
                                            context,
                                            icon: Icons.check_circle_rounded,
                                            label: 'Selesai',
                                            value: '${stats.completedOrders}',
                                            accent: Colors.green.shade700,
                                            onTap: () => setState(
                                              () =>
                                                  _csTodayStatusFilter = 'done',
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: TextEditingController(
                          text: _csOrderSearchQuery,
                        ),
                        onChanged: (v) =>
                            setState(() => _csOrderSearchQuery = v),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.35),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 20,
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.qr_code_scanner, size: 20),
                            tooltip: 'Scan QR order',
                            onPressed: _scanAndFillSearch,
                          ),
                          hintText: 'Nomor order, pelanggan, item…',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outline.withValues(alpha: 0.25),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
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
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.cloud_off_outlined,
                                        size: 52,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Gagal memuat order hari ini',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        error.toString(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 16),
                                      FilledButton.icon(
                                        onPressed: _refreshCsOrderToday,
                                        icon: const Icon(
                                          Icons.refresh,
                                          size: 20,
                                        ),
                                        label: const Text('Coba lagi'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              data: (orders) {
                                if (orders.isEmpty) {
                                  return Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.inbox_outlined,
                                          size: 56,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.outline,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Belum ada order hari ini',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Order yang Anda buat hari ini akan muncul di sini.',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                final typed = orders
                                    .map(
                                      (e) =>
                                          Map<String, dynamic>.from(e as Map),
                                    )
                                    .toList();
                                final filtered = _filteredCsTodayOrders(typed);
                                final hasFilter =
                                    _csOrderSearchQuery.trim().isNotEmpty ||
                                    _csTodayStatusFilter != 'all';
                                final filteredLines = _countCsTodayTableLines(
                                  filtered,
                                );
                                final totalLines = _countCsTodayTableLines(
                                  typed,
                                );

                                if (filtered.isEmpty) {
                                  return Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.search_off_rounded,
                                            size: 52,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.outline,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Tidak ada yang cocok',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          if (hasFilter) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              'Ubah kata kunci atau filter, atau kosongkan pencarian.',
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                            const SizedBox(height: 16),
                                            OutlinedButton.icon(
                                              onPressed: () => setState(() {
                                                _csOrderSearchQuery = '';
                                                _csTodayStatusFilter = 'all';
                                              }),
                                              icon: const Icon(
                                                Icons.filter_alt_off,
                                                size: 20,
                                              ),
                                              label: const Text('Reset filter'),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                }

                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 4,
                                        left: 2,
                                      ),
                                      child: Text(
                                        !hasFilter &&
                                                filtered.length == typed.length
                                            ? '$filteredLines baris · ${filtered.length} order'
                                            : 'Menampilkan $filteredLines baris (${filtered.length} order) dari $totalLines baris (${typed.length} order)',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                    Expanded(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outline
                                                .withValues(alpha: 0.12),
                                          ),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            13,
                                          ),
                                          child: _buildCsTodayOrdersTable(
                                            context,
                                            filtered,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
