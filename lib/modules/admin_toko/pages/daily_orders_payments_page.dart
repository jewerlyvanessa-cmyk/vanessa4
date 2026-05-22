import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/cs_daily_orders_refresh_provider.dart';
import 'package:vanessa3/modules/cs/pages/faktur_page.dart';
import 'package:vanessa3/modules/admin_toko/data/daily_orders_payments_repository.dart';
import 'package:vanessa3/modules/admin_toko/utils/daily_orders_payments_helpers.dart';
import 'package:vanessa3/utils/app_date_picker.dart';
import 'package:vanessa3/utils/business_calendar.dart';
import 'package:vanessa3/shared_widgets/workshop_order_document_sheet.dart';
import 'package:vanessa3/utils/surat_jalan_workshop_print.dart';
import 'package:vanessa3/utils/workshop_order_batch_group.dart';
import 'package:vanessa3/utils/daily_orders_payments_report_print.dart';
import 'package:vanessa3/modules/stockist/widgets/stock_inventory_grouped_table.dart'
    show stockBranchDisplayName;
import 'package:vanessa3/modules/admin_toko/widgets/daily_orders_daily_table.dart';
import 'package:vanessa3/modules/admin_toko/widgets/daily_orders_payments_table.dart';
import 'package:vanessa3/modules/admin_toko/widgets/daily_orders_workshop_status_cell.dart';
import 'package:vanessa3/modules/admin_toko/widgets/daily_orders_summary_strip.dart';
import 'package:vanessa3/modules/admin_toko/widgets/daily_orders_payments_shell.dart';

class DailyOrdersPaymentsPage extends ConsumerStatefulWidget {
  const DailyOrdersPaymentsPage({
    super.key,
    this.serviceCustomMode = false,
    this.embedInParent = false,
    this.ordersOnly = false,
  });

  /// Dari menu khusus admin toko: daftar difilter service/custom, aksi kirim ke workshop tetap sama.
  final bool serviceCustomMode;

  /// Tanpa [Scaffold]/[AppBar] — untuk disematkan di halaman induk (dashboard CS).
  /// Di mode ini strip ringkasan (chip tanggal/order) dan bar judul kalender/refresh disembunyikan.
  final bool embedInParent;

  /// Hanya tab/isi order (tanpa pembayaran). Dipakai peran CS.
  final bool ordersOnly;

  @override
  ConsumerState<DailyOrdersPaymentsPage> createState() =>
      _DailyOrdersPaymentsPageState();
}

class _DailyOrdersPaymentsPageState
    extends ConsumerState<DailyOrdersPaymentsPage> {
  DateTime _selectedDate = BusinessCalendar.todayWibDateOnly();
  Map<String, dynamic> _dailyData = {};
  bool _isLoading = true;
  String _error = '';
  AdminOrderFilter _orderFilter = AdminOrderFilter.all;

  @override
  void initState() {
    super.initState();
    if (widget.serviceCustomMode) {
      // Hanya service/custom: basis tampilan = semua order tipe itu (subfilter toko/dll. di atasnya).
      _orderFilter = AdminOrderFilter.all;
    }
    _loadDailyData();
  }

  Future<void> _loadDailyData() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final bundle = await DailyOrdersPaymentsRepository.fetchDaily(
        user: userState,
        selectedDate: _selectedDate,
        ordersOnly: widget.ordersOnly,
      );
      var ordersData = bundle.orders;
      ordersData = filterOrdersForCsIfNeeded(userState, ordersData);

      setState(() {
        _dailyData = {'orders': ordersData, 'payments': bundle.payments};
        _orderFilter = AdminOrderFilter.all;
        _isLoading = false;
      });
    } on DailyOrdersPaymentsLoadException catch (e) {
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _error = 'Error: $error';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showAppDatePicker(
      context: context,
      initialDate: _selectedDate,
      lastDate: BusinessCalendar.todayWibDateOnly(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadDailyData();
    }
  }

  List<dynamic> get _ordersRaw => _dailyData['orders'] as List<dynamic>? ?? [];

  List<Map<String, dynamic>> _paymentsTxView() =>
      paymentsTransactionsForView(
        dailyData: _dailyData,
        serviceCustomMode: widget.serviceCustomMode,
      );

  List<Map<String, dynamic>> _filterDeduped(List<Map<String, dynamic>> deduped) =>
      filterDedupedOrders(
        deduped,
        filter: _orderFilter,
        serviceCustomMode: widget.serviceCustomMode,
      );

  List<dynamic> _rawOrdersForTable(List<dynamic> ordersRaw) =>
      rawOrdersForTable(
        ordersRaw,
        filter: _orderFilter,
        serviceCustomMode: widget.serviceCustomMode,
      );

  void _setOrderFilter(AdminOrderFilter f) {
    setState(() => _orderFilter = f);
  }

  String _orderFilterLabel() => adminOrderFilterLabel(
        _orderFilter,
        serviceCustomMode: widget.serviceCustomMode,
      );

  String _reportTitle() {
    if (widget.serviceCustomMode) return 'Service / Custom';
    if (widget.ordersOnly) return 'Order';
    return 'Order & Pembayaran';
  }

  Future<void> _printReport() async {
    if (_isLoading || _error.isNotEmpty) return;

    final ordersRaw = _dailyData['orders'] as List<dynamic>? ?? [];
    if (ordersRaw.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada data untuk dicetak')),
      );
      return;
    }

    final user = ref.read(userStateProvider);
    final branchId = user.branch.trim();
    final branchLabel = stockBranchDisplayName(
          branches: user.branches,
          branchId: branchId,
        ) ??
        branchId;

    final tableRaw = _rawOrdersForTable(ordersRaw);
    final orderRowsAreLineItems = kIsWeb;
    final List<Map<String, dynamic>> orderRows;
    if (orderRowsAreLineItems) {
      orderRows = rawOrderLineRows(tableRaw);
    } else {
      orderRows = _filterDeduped(dedupeOrdersById(tableRaw));
    }

    final dedupedForSummary = widget.serviceCustomMode
        ? dedupeOrdersById(ordersRaw).where(isServiceCustomOrder).toList()
        : _filterDeduped(dedupeOrdersById(ordersRaw));
    final modeCounts = orderModeCounts(dedupedForSummary);
    final completed = dedupedForSummary
        .where((o) => isCompletedOrderStatus(o['status']?.toString()))
        .length;
    final pending = dedupedForSummary
        .where((o) => isOpenOrderStatus(o['status']?.toString()))
        .length;

    num payIncome = 0;
    num payExpense = 0;
    num payNet = 0;
    var payTrx = 0;
    if (!widget.ordersOnly) {
      final pay = paymentTotalsFromDailyData(
        dailyData: _dailyData,
        serviceCustomMode: widget.serviceCustomMode,
      );
      payIncome = pay.income;
      payExpense = pay.expense;
      payNet = pay.net;
      payTrx = pay.count;
    }

    final userLabel = user.role.trim().toLowerCase() == 'cs'
        ? 'CS: ${user.username.isNotEmpty ? user.username : user.userId}'
        : null;

    await printDailyOrdersPaymentsReportPdf(
      context,
      reportDate: _selectedDate,
      branchLabel: branchLabel.isEmpty ? 'Cabang' : branchLabel,
      branchIdForLogo: branchId,
      reportTitle: _reportTitle(),
      filterDescription: _orderFilterLabel(),
      userLabel: userLabel,
      ordersOnly: widget.ordersOnly,
      totalOrders: dedupedForSummary.length,
      completedOrders: completed,
      pendingOrders: pending,
      tokoCount: modeCounts.toko,
      onlineCount: modeCounts.online,
      paymentIncome: payIncome,
      paymentExpense: payExpense,
      paymentNet: payNet,
      paymentTrxCount: payTrx,
      orderRows: orderRows,
      orderRowsAreLineItems: orderRowsAreLineItems,
      paymentRows: widget.ordersOnly ? null : _paymentsTxView(),
    );
  }

  Widget _workshopStatusCell(Map<String, dynamic> row) {
    return DailyOrdersWorkshopStatusCell(
      row: row,
      onWorkshopAction: _updateWorkshopStatusAdminToko,
    );
  }

  Future<void> _openFaktur(
    BuildContext context,
    Map<String, dynamic> order,
  ) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final data =
          await DailyOrdersPaymentsRepository.fetchFullOrderForFaktur(order);
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!context.mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (context) => FakturPage(orderData: data),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat faktur: $e')),
        );
      }
    }
  }

  void _openOrderDetail(BuildContext context, Map<String, dynamic> order) {
    _openFaktur(context, order);
  }

  String _storeBranchName() {
    final userState = ref.read(userStateProvider);
    final id = userState.branch.trim();
    for (final b in userState.branches) {
      if (b['branch_id']?.toString() == id) {
        final n = b['name']?.toString().trim();
        if (n != null && n.isNotEmpty) return n;
      }
    }
    return id.isEmpty ? 'Toko' : 'Cabang $id';
  }

  Future<void> _printWorkshopSuratJalan(List<Map<String, dynamic>> orders) async {
    if (orders.isEmpty) return;
    final userState = ref.read(userStateProvider);
    final branches = await resolveWorkshopSuratJalanBranches(
      storeBranchId: userState.branch.trim(),
      storeBranchName: _storeBranchName(),
    );
    if (!mounted) return;
    await printSuratJalanWorkshopOrders(
      context,
      orders: orders,
      branches: branches,
    );
  }

  Future<void> _openBatchSendToWorkshop(
    List<Map<String, dynamic>> orders,
  ) async {
    final pending = orders
        .where((o) => nextAdminTokoWorkshopStatus(o) == 'awaiting_warehouse')
        .toList();
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada order untuk dikirim ke workshop')),
      );
      return;
    }

    final batch = WorkshopOrderDocumentBatch(
      lines: pending,
      groupKey: 'send_workshop_manual',
      flowLabel: 'Kirim ke workshop',
    );

    final userState = ref.read(userStateProvider);
    final branchId = int.tryParse(userState.branch);
    if (branchId == null) return;

    final suratJalan = await resolveWorkshopSuratJalanBranches(
      storeBranchId: userState.branch.trim(),
      storeBranchName: _storeBranchName(),
    );

    if (!mounted) return;
    await showWorkshopOrderDocumentSheet(
      context: context,
      batch: batch,
      actionKind: WorkshopDocumentActionKind.sendToWorkshop,
      branchId: branchId,
      branchIdStr: userState.branch.trim(),
      suratJalanBranches: suratJalan,
      onCompleted: _loadDailyData,
    );
  }

  Future<void> _updateWorkshopStatusAdminToko(
    Map<String, dynamic> row,
    String nextStatus,
  ) async {
    try {
      final userState = ref.read(userStateProvider);
      final branchId = int.tryParse(userState.branch);
      final orderId = int.tryParse((row['order_id'] ?? '').toString());
      if (branchId == null || orderId == null) return;
      final response = await DailyOrdersPaymentsRepository.updateWorkshopOrderStatus(
        orderId: orderId,
        branchId: branchId,
        nextStatus: nextStatus,
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Order #$orderId -> $nextStatus')),
          );
        }
        if (nextStatus == 'awaiting_warehouse' && mounted) {
          await _printWorkshopSuratJalan([row]);
        }
        await _loadDailyData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal update status: ${response.body}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error update status: $e')));
      }
    }
  }

  Widget _ordersOnlyEmbedFilterStrip(BuildContext context) {
    return DailyOrdersEmbedFilterStrip(
      ordersRaw: _ordersRaw,
      orderFilter: _orderFilter,
      onFilterChanged: _setOrderFilter,
    );
  }

  Widget _compactSummaryStrip(BuildContext context) {
    return DailyOrdersCompactSummaryStrip(
      selectedDate: _selectedDate,
      dailyData: _dailyData,
      orderFilter: _orderFilter,
      serviceCustomMode: widget.serviceCustomMode,
      ordersOnly: widget.ordersOnly,
      onFilterChanged: _setOrderFilter,
      onBatchSendToWorkshop: () {
        final pending = dedupeOrdersById(_ordersRaw)
            .where((o) => nextAdminTokoWorkshopStatus(o) == 'awaiting_warehouse')
            .toList();
        _openBatchSendToWorkshop(pending);
      },
      onPrintSuratJalan: () {
        final sudah = dedupeOrdersById(_ordersRaw)
            .where(
              (o) =>
                  isServiceCustomOrder(o) &&
                  (o['status'] ?? '').toString().trim().toLowerCase() ==
                      'awaiting_warehouse',
            )
            .toList();
        _printWorkshopSuratJalan(sudah);
      },
    );
  }

  String _emptyOrdersHint() {
    final dateLabel = DateFormat('d MMM yyyy', 'id_ID').format(_selectedDate);
    final role = ref.read(userStateProvider).role.trim().toLowerCase();
    final csNote = role == 'cs'
        ? '\n(CS hanya melihat order yang Anda buat.)'
        : '';
    return 'Tidak ada order pada $dateLabel.$csNote\n'
        'Coba tanggal kemarin di pemilih tanggal, atau refresh setelah membuat order.';
  }

  Widget _ordersTable(BuildContext context) {
    final ordersRaw = _ordersRaw;
    return DailyOrdersDailyTable(
      ordersRaw: ordersRaw,
      filteredTableRaw: _rawOrdersForTable(ordersRaw),
      emptyHint: _emptyOrdersHint(),
      emptyFilterMessage: widget.serviceCustomMode
          ? 'Tidak ada order Service atau Custom pada tanggal ini'
          : 'Tidak ada order untuk filter ini',
      onOrderTap: (o) => _openOrderDetail(context, o),
      statusCellBuilder: _workshopStatusCell,
      filterDeduped: _filterDeduped,
    );
  }

  Widget _paymentsTable(BuildContext context) {
    return DailyOrdersPaymentsTable(
      transactions: _paymentsTxView(),
      ordersRaw: _ordersRaw,
      serviceCustomMode: widget.serviceCustomMode,
    );
  }

  Widget _buildMainBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDailyData,
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      );
    }
    if (widget.ordersOnly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.embedInParent) _compactSummaryStrip(context),
          if (widget.embedInParent) _ordersOnlyEmbedFilterStrip(context),
          Expanded(child: _ordersTable(context)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedInParent) _compactSummaryStrip(context),
        Expanded(
          child: TabBarView(
            children: [
              _ordersTable(context),
              _paymentsTable(context),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(csDailyOrdersListRevisionProvider, (previous, next) {
      if (previous != null && previous != next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadDailyData();
        });
      }
    });

    final dedupedOrders = dedupeOrdersById(_ordersRaw);
    final orderCount = dedupedOrders.length;
    final openCount = dedupedOrders
        .where((o) => isOpenOrderStatus(o['status']?.toString()))
        .length;

    return DailyOrdersPaymentsShell(
      serviceCustomMode: widget.serviceCustomMode,
      embedInParent: widget.embedInParent,
      ordersOnly: widget.ordersOnly,
      isLoading: _isLoading,
      error: _error,
      selectedDate: _selectedDate,
      orderCount: orderCount,
      svcCustomCount: dedupedOrders.where(isServiceCustomOrder).length,
      payTx: _paymentsTxView().length,
      openOrderCount: openCount,
      body: _buildMainBody(context),
      onRefresh: _loadDailyData,
      onPrintReport: _printReport,
      onSelectDate: _selectDate,
    );
  }
}
