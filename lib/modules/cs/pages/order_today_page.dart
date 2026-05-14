import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/providers/order_today_provider.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'faktur_page.dart';
import 'package:vanessa3/utils/order_today_report_print.dart';
import 'package:vanessa3/utils/order_faktur_resolve.dart';
import 'package:vanessa3/utils/order_status_ui.dart';
import 'package:vanessa3/utils/business_calendar.dart';

class OrderTodayPage extends ConsumerStatefulWidget {
  const OrderTodayPage({super.key});

  @override
  ConsumerState<OrderTodayPage> createState() => _OrderTodayPageState();
}

class _OrderTodayPageState extends ConsumerState<OrderTodayPage> {
  int _orderTodayTablePage = 0;
  static const int _kOrderTodayPageSize = 50;

  @override
  Widget build(BuildContext context) {
    final orderStatsAsync = ref.watch(orderTodayStatsProvider);
    final todayOrdersAsync = ref.watch(todayOrdersProvider);
    final isServerHealthy = ref.watch(healthCheckProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    ref.listen(userStateProvider, (previous, next) {
      ref.read(orderTodayStatsProvider.notifier).listenToUserStateChanges();
      ref.read(todayOrdersProvider.notifier).listenToUserStateChanges();
    });

    ref.listen(realTimeOrderUpdatesProvider, (previous, next) {
      next.whenData((update) {
        if (update['type'] == 'order_update' ||
            update['type'] == 'mock_update') {
          Future.wait([
            ref.read(orderTodayStatsProvider.notifier).refresh(),
            ref.read(todayOrdersProvider.notifier).refresh(),
          ]);
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Today'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Icon(
                  isServerHealthy ? Icons.wifi : Icons.wifi_off,
                  color: isServerHealthy ? Colors.green : cs.error,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  'Live',
                  style: tt.labelMedium?.copyWith(
                    fontSize: AppTypography.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              Future.wait([
                ref.read(orderTodayStatsProvider.notifier).refresh(),
                ref.read(todayOrdersProvider.notifier).refresh(),
              ]);
            },
          ),
          IconButton(
            tooltip: 'Print laporan',
            icon: const Icon(Icons.print_outlined),
            onPressed: () async {
              final stats = ref.read(orderTodayStatsProvider).value;
              final orders = ref.read(todayOrdersProvider).value;
              if (stats == null || orders == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Data belum siap untuk dicetak'),
                  ),
                );
                return;
              }
              final userState = ref.read(userStateProvider);
              final bid = userState.branch.trim();
              String branchLabel = bid.isEmpty ? '-' : bid;
              try {
                final found = userState.branches.firstWhere(
                  (b) => b['branch_id']?.toString() == bid,
                );
                branchLabel =
                    (found['alias']?.toString().trim().isNotEmpty == true)
                    ? found['alias'].toString().trim()
                    : (found['name'] ?? branchLabel).toString();
              } catch (_) {}

              await printOrderTodayReportPdf(
                context,
                reportDate: BusinessCalendar.todayWibDateOnly(),
                branchLabel: branchLabel,
                branchIdForLogo: bid,
                ordersByType: stats.ordersByType,
                ordersByMode: stats.ordersByMode,
                totalOrders: stats.totalOrders,
                pendingOrders: stats.pendingOrders,
                completedOrders: stats.completedOrders,
                revenueJualCompleted: stats.revenueJualCompleted,
                expenseBuybackCompleted: stats.expenseBuybackCompleted,
                netRevenue: stats.totalRevenue,
                orders: List<Map<String, dynamic>>.from(orders),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.read(orderTodayStatsProvider.notifier).refresh(),
            ref.read(todayOrdersProvider.notifier).refresh(),
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            _headerCard(context),
            const SizedBox(height: 12),
            orderStatsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Error: $e')),
              ),
              data: (stats) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _topCards(context, stats),
                  const SizedBox(height: 14),
                  Text(
                    'Order per mode',
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _orderModeGrid(context, stats.ordersByMode),
                  const SizedBox(height: 16),
                  Text(
                    'Order per Jenis',
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _orderTypeGrid(context, stats.ordersByType),
                  const SizedBox(height: 16),
                  Text(
                    'Daftar Order',
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  todayOrdersAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('Gagal memuat daftar order: $e'),
                      ),
                    ),
                    data: (orders) => _todayOrdersTable(context, orders),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = BusinessCalendar.todayWibDateOnly();
    final formatter = DateFormat('EEEE, dd MMMM yyyy', 'id_ID');
    return Card(
      child: ListTile(
        leading: const Icon(Icons.analytics_outlined),
        title: Text(
          formatter.format(today),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        subtitle: Text(
          'Ringkasan order hari ini',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: AppTypography.bodySmall,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _miniTopCard(
    BuildContext context, {
    required String title,
    required String value,
    required Color accent,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 0,
      color: cs.surfaceContainerLow.withValues(alpha: 0.65),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                      fontSize: 16,
                      height: 1.05,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topCards(BuildContext context, OrderTodayStats stats) {
    final money = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _miniTopCard(
                context,
                title: 'Revenue jual',
                value: money.format(stats.revenueJualCompleted),
                accent: Colors.green.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _miniTopCard(
                context,
                title: 'Buyback (keluar)',
                value: money.format(stats.expenseBuybackCompleted),
                accent: Colors.red.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _miniTopCard(
                context,
                title: 'Net',
                value: money.format(stats.totalRevenue),
                accent: Colors.blueGrey.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _miniTopCard(
                context,
                title: 'Total order',
                value: '${stats.totalOrders}',
                accent: cs.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _miniTopCard(
                context,
                title: 'Pending',
                value: '${stats.pendingOrders}',
                accent: Colors.orange.shade800,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _miniTopCard(
                context,
                title: 'Selesai',
                value: '${stats.completedOrders}',
                accent: Colors.green.shade700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metricChip(
    BuildContext context, {
    required String label,
    required int value,
  }) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '$value',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderModeGrid(BuildContext context, Map<String, int> ordersByMode) {
    int v(String k) => ordersByMode[k] ?? 0;
    return Row(
      children: [
        Expanded(
          child: _metricChip(context, label: 'Toko', value: v('toko')),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _metricChip(context, label: 'Online', value: v('online')),
        ),
      ],
    );
  }

  Widget _orderTypeGrid(BuildContext context, Map<String, int> ordersByType) {
    int v(String k) => ordersByType[k] ?? 0;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _metricChip(context, label: 'Jual', value: v('jual')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metricChip(
                context,
                label: 'Buyback',
                value: v('buyback'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _metricChip(
                context,
                label: 'Service',
                value: v('service'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metricChip(context, label: 'Custom', value: v('custom')),
            ),
          ],
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _flattenOrders(List<Map<String, dynamic>> orders) {
    final out = <Map<String, dynamic>>[];
    for (final o in orders) {
      final items = (o['items'] is List)
          ? (o['items'] as List)
          : (o['order_items'] is List)
          ? (o['order_items'] as List)
          : const [];
      if (items.isEmpty) {
        out.add({'order': o, 'item': null});
        continue;
      }
      for (final it in items) {
        if (it is Map) {
          out.add({'order': o, 'item': Map<String, dynamic>.from(it)});
        }
      }
    }
    return out;
  }

  String _fmtRp(dynamic v) {
    final n = double.tryParse(v?.toString() ?? '');
    if (n == null) return '0';
    return NumberFormat('#,###', 'id_ID').format(n);
  }

  String _lineBerat(Map<String, dynamic>? item) {
    if (item == null) return '—';
    final raw = item['berat'] ?? item['weight'] ?? item['item_weight'];
    final b = double.tryParse(raw?.toString() ?? '');
    if (b == null || b <= 0) return '—';
    return '${raw.toString()} g';
  }

  String _lineNama(Map<String, dynamic>? item) =>
      _itemFieldStr(item, const ['nama_item', 'item_name', 'name']);

  String _lineTotal(Map<String, dynamic> order) {
    final raw = order['jumlah'] ?? order['total'];
    final d = double.tryParse(raw?.toString() ?? '');
    if (d == null || d == 0) return '—';
    return 'Rp ${_fmtRp(raw)}';
  }

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

  String _itemKategoriLine(Map<String, dynamic>? item) =>
      _itemFieldStr(item, const ['kategori', 'item_kategori']);

  String _itemJenisLine(Map<String, dynamic>? item) =>
      _itemFieldStr(item, const ['jenis', 'item_jenis']);

  String _itemTipeLine(Map<String, dynamic>? item) =>
      _itemFieldStr(item, const ['tipe', 'item_tipe']);

  String _itemMaterialLine(Map<String, dynamic>? item) =>
      _itemFieldStr(item, const ['material', 'item_material']);

  String _itemKadarLine(Map<String, dynamic>? item) =>
      _itemFieldStr(item, const ['purity', 'kadar', 'item_purity']);

  String _itemQtyLine(Map<String, dynamic>? item) =>
      _itemFieldStr(item, const ['qty', 'quantity', 'item_qty']);

  String _itemHargaPerGramLine(Map<String, dynamic>? item) {
    if (item == null) return '—';
    final raw = item['harga_per_gram'];
    final d = double.tryParse(raw?.toString() ?? '');
    if (d != null && d > 0) return 'Rp ${_fmtRp(raw)}';
    return '—';
  }

  String _getStatusLabel(String? status) => OrderStatusUi.label(status);

  Color _getStatusColor(String? status) => OrderStatusUi.color(status);

  /// Tampilan user-facing: nomor order bila ada, else id internal.
  String _orderDisplayRef(Map<String, dynamic> order) {
    final n = (order['order_number'] ?? '').toString().trim();
    if (n.isNotEmpty) return n;
    final id = (order['order_id'] ?? '').toString().trim();
    if (id.isNotEmpty) return '#$id';
    return '—';
  }

  Widget _todayOrdersTable(
    BuildContext context,
    List<Map<String, dynamic>> orders,
  ) {
    final cs = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final webWide = kIsWeb && !narrow;
    final lines = _flattenOrders(orders);
    final pageCount = lines.isEmpty
        ? 1
        : (lines.length + _kOrderTodayPageSize - 1) ~/ _kOrderTodayPageSize;
    final page = min(_orderTodayTablePage, pageCount - 1);
    final start = page * _kOrderTodayPageSize;
    final end = start + _kOrderTodayPageSize > lines.length
        ? lines.length
        : start + _kOrderTodayPageSize;
    final linesPage = lines.sublist(start, end);

    Future<void> openFaktur(Map<String, dynamic> data) async {
      final fakturData = await loadOrderDataForFakturPage(data);
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FakturPage(orderData: fakturData)),
      );
    }

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
      FontWeight? weight,
      Color? color,
    }) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style:
            (narrow ? mobileCellStyle : Theme.of(context).textTheme.bodyMedium)
                ?.copyWith(fontWeight: weight, color: color),
      );
    }

    final columns = narrow
        ? <DataColumn>[
            DataColumn(label: dataTableColumnLabel('Nomor order')),
            DataColumn(label: dataTableColumnLabel('Jenis')),
            DataColumn(label: dataTableColumnLabel('Nama item')),
            DataColumn(label: dataTableColumnLabel('Berat'), numeric: true),
            DataColumn(label: dataTableColumnLabel('Total'), numeric: true),
          ]
        : webWide
        ? <DataColumn>[
            DataColumn(label: dataTableColumnLabel('Nomor order')),
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
            DataColumn(label: dataTableColumnLabel('Nomor order')),
            DataColumn(label: dataTableColumnLabel('Nama item')),
            DataColumn(label: dataTableColumnLabel('Berat'), numeric: true),
            DataColumn(label: dataTableColumnLabel('Total'), numeric: true),
            DataColumn(label: dataTableColumnLabel('Pelanggan')),
            DataColumn(label: dataTableColumnLabel('Status')),
            DataColumn(label: dataTableColumnLabel('Jenis')),
            const DataColumn(label: SizedBox(width: 44)),
          ];

    final rows = <DataRow>[];
    for (var j = 0; j < linesPage.length; j++) {
      final i = start + j;
      final order = Map<String, dynamic>.from(linesPage[j]['order'] as Map);
      final item = linesPage[j]['item'] as Map<String, dynamic>?;
      final nama = _lineNama(item);
      final berat = _lineBerat(item);
      final total = _lineTotal(order);

      final cells = <DataCell>[
        DataCell(cell(_orderDisplayRef(order), maxLines: 1)),
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
            child: cell(total, maxLines: 1, align: TextAlign.end),
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
          color: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.hovered)) {
              return cs.primary.withValues(alpha: 0.07);
            }
            if (s.contains(WidgetState.pressed)) {
              return cs.primary.withValues(alpha: 0.11);
            }
            return i.isOdd
                ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
                : null;
          }),
          onSelectChanged: (_) => openFaktur(order),
          cells: cells,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lines.length > _kOrderTodayPageSize)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Baris ${start + 1}–$end dari ${lines.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Halaman sebelumnya',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: page > 0
                      ? () => setState(() => _orderTodayTablePage = page - 1)
                      : null,
                ),
                Text('${page + 1} / $pageCount'),
                IconButton(
                  tooltip: 'Halaman berikutnya',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: page < pageCount - 1
                      ? () => setState(() => _orderTodayTablePage = page + 1)
                      : null,
                ),
              ],
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final minW = narrow
                ? constraints.maxWidth
                : (webWide ? 1280.0 : 920.0);
            return Material(
              elevation: 0,
              color: cs.surfaceContainerLow.withValues(alpha: 0.65),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              // Avoid Scrollbar assertion on Web when the PrimaryScrollController
              // isn't attached (nested scroll views + hover).
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
                        cs.surfaceContainerHigh,
                      ),
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
        ),
      ],
    );
  }
}
