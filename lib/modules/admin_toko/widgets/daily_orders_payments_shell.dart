import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Scaffold / embed host untuk [DailyOrdersPaymentsPage].
class DailyOrdersPaymentsShell extends StatelessWidget {
  const DailyOrdersPaymentsShell({
    super.key,
    required this.serviceCustomMode,
    required this.embedInParent,
    required this.ordersOnly,
    required this.isLoading,
    required this.error,
    required this.selectedDate,
    required this.orderCount,
    required this.svcCustomCount,
    required this.payTx,
    required this.openOrderCount,
    required this.body,
    required this.onRefresh,
    required this.onPrintReport,
    required this.onSelectDate,
  });

  final bool serviceCustomMode;
  final bool embedInParent;
  final bool ordersOnly;
  final bool isLoading;
  final String error;
  final DateTime selectedDate;
  final int orderCount;
  final int svcCustomCount;
  final int payTx;
  final int openOrderCount;
  final Widget body;
  final VoidCallback onRefresh;
  final VoidCallback onPrintReport;
  final void Function(BuildContext context) onSelectDate;

  String get _pageTitle {
    if (serviceCustomMode) return 'Service / Custom';
    if (ordersOnly) return 'Order';
    return 'Order & Pembayaran';
  }

  String _appBarSubtitle() {
    if (serviceCustomMode) {
      return '${DateFormat('EEEE, d MMM yyyy', 'id_ID').format(selectedDate)} · kirim ke workshop dari toko';
    }
    return DateFormat('EEEE, d MMM yyyy', 'id_ID').format(selectedDate);
  }

  String _embedOrderSubtitle() {
    final open = openOrderCount;
    final done = orderCount - open;
    if (open > 0 && done > 0) {
      return '$orderCount order · $open belum selesai';
    }
    if (open > 0) return '$orderCount order · belum selesai';
    return '$orderCount order';
  }

  TabBar? _tabBar(BuildContext context, {required bool forAppBar}) {
    final showTabs = !ordersOnly && !isLoading && error.isEmpty;
    if (!showTabs) return null;

    final orderTab = serviceCustomMode
        ? 'Service/custom ($svcCustomCount)'
        : 'Order ($orderCount)';

    if (forAppBar) {
      return TabBar(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
        tabs: [
          Tab(text: orderTab),
          Tab(text: 'Pembayaran ($payTx)'),
        ],
      );
    }

    final cs = Theme.of(context).colorScheme;
    return TabBar(
      labelColor: cs.primary,
      unselectedLabelColor: cs.onSurfaceVariant,
      indicatorColor: cs.primary,
      tabs: [
        Tab(text: orderTab),
        Tab(text: 'Pembayaran ($payTx)'),
      ],
    );
  }

  Widget _embeddedHost(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tabBar = _tabBar(context, forAppBar: false);

    final content = Material(
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ordersOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        'Order Today',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      isLoading ? '…' : _embedOrderSubtitle(),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: isLoading
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary,
                            ),
                          )
                        : const Icon(Icons.refresh),
                    onPressed: isLoading ? null : onRefresh,
                    tooltip: 'Muat ulang',
                  ),
                ],
              ),
            ),
          if (!isLoading && error.isEmpty && !ordersOnly)
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.print_outlined),
                onPressed: onPrintReport,
                tooltip: 'Cetak laporan',
              ),
            ),
          if (tabBar != null)
            Material(color: cs.surface, child: tabBar),
          Expanded(child: body),
        ],
      ),
    );

    if (ordersOnly) return content;
    return DefaultTabController(length: 2, child: content);
  }

  Widget _standaloneScaffold(BuildContext context) {
    final scaffold = Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_pageTitle),
            Text(
              _appBarSubtitle(),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            onPressed: onPrintReport,
            tooltip: 'Cetak laporan',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () => onSelectDate(context),
            tooltip: 'Pilih tanggal',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: onRefresh,
            tooltip: 'Refresh',
          ),
        ],
        bottom: _tabBar(context, forAppBar: true),
      ),
      body: body,
    );

    if (ordersOnly) return scaffold;
    return DefaultTabController(length: 2, child: scaffold);
  }

  @override
  Widget build(BuildContext context) {
    if (embedInParent) return _embeddedHost(context);
    return _standaloneScaffold(context);
  }
}
