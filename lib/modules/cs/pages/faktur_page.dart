import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vanessa3/modules/cs/logic/faktur_page_utils.dart';
import 'package:vanessa3/modules/cs/widgets/faktur_content_layout.dart';
import 'package:vanessa3/utils/faktur/faktur_payment_api.dart'
    show enrichOrderDataForFakturPrint;
import 'package:vanessa3/utils/faktur_print.dart'
    show
        printFakturOrder,
        printPickupServiceCustomFaktur,
        resolveFakturDpAmount,
        fakturServiceCustomFieldRows;
import 'package:vanessa3/utils/responsive_layout.dart';

class FakturPage extends StatefulWidget {
  final Map<String, dynamic> orderData;
  const FakturPage({super.key, required this.orderData});

  @override
  State<FakturPage> createState() => _FakturPageState();
}

class _FakturPageState extends State<FakturPage> {
  late Map<String, dynamic> _orderData;
  late final Future<String> _branchTitleFuture;
  late Future<double> _serviceCustomDpFuture;

  @override
  void initState() {
    super.initState();
    _orderData = Map<String, dynamic>.from(widget.orderData);
    _branchTitleFuture = FakturPageUtils.resolveBranchTitle(widget.orderData);
    _serviceCustomDpFuture = resolveFakturDpAmount(_orderData);
    unawaited(_preloadFakturPrintContext());
  }

  /// Muat ringkasan bayar + logo cabang di background agar tombol cetak lebih cepat.
  Future<void> _preloadFakturPrintContext() async {
    await enrichOrderDataForFakturPrint(_orderData);
    if (!mounted) return;
    setState(() {
      _serviceCustomDpFuture = resolveFakturDpAmount(_orderData);
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderData = _orderData;
    if (orderData.isEmpty || !orderData.containsKey('order_id')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Faktur Order')),
        body: const Center(
          child: Text('Data faktur tidak valid atau tidak tersedia.'),
        ),
      );
    }

    final List<dynamic> items = orderData['items'] ?? [];
    final customerName =
        orderData['customer_name'] ??
        orderData['name'] ??
        orderData['customer'];
    final customerPhone =
        orderData['customer_phone'] ?? orderData['phone'] ?? orderData['no_hp'];
    final customerAddress =
        orderData['customer_address'] ??
        orderData['address'] ??
        orderData['alamat'];
    final orderNumber = (orderData['order_number'] ?? '').toString().trim();
    final qrPayload = orderNumber.isNotEmpty
        ? orderNumber
        : (orderData['order_id'] ?? '').toString().trim();
    final orderType = orderData['order_type'];
    final fakturHeading = FakturPageUtils.fakturHeading(orderType);
    final orderTypeLabel = FakturPageUtils.orderTypeDisplayLabel(orderType);
    final normalizedType = FakturPageUtils.normalizeOrderType(orderType);
    final isServiceOrCustom =
        normalizedType == 'service' || normalizedType == 'custom';
    final svcFakturFields = isServiceOrCustom
        ? fakturServiceCustomFieldRows(orderData)
        : const <String, String>{};
    final sisaAfterDpLabel =
        svcFakturFields['sisa_setelah_dp_row_label'] ?? 'Sisa estimasi';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Faktur Order'),
        actions: [
          if (isServiceOrCustom)
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: 'Cetak faktur pengambilan (AMBIL)',
              onPressed: () => printPickupServiceCustomFaktur(context, _orderData),
            ),
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Cetak faktur order (referensi)',
            onPressed: () => printFakturOrder(context, _orderData),
          ),
        ],
      ),
      body: _buildFakturBody(
        context,
        orderData: orderData,
        items: items,
        fakturHeading: fakturHeading,
        orderTypeLabel: orderTypeLabel,
        isServiceOrCustom: isServiceOrCustom,
        customerName: customerName,
        customerPhone: customerPhone,
        customerAddress: customerAddress,
        orderNumber: orderNumber,
        qrPayload: qrPayload,
        svcFakturFields: svcFakturFields,
        sisaAfterDpLabel: sisaAfterDpLabel,
      ),
    );
  }

  Widget _buildFakturBody(
    BuildContext context, {
    required Map<String, dynamic> orderData,
    required List<dynamic> items,
    required String fakturHeading,
    required String orderTypeLabel,
    required bool isServiceOrCustom,
    required dynamic customerName,
    required dynamic customerPhone,
    required dynamic customerAddress,
    required String orderNumber,
    required String qrPayload,
    required Map<String, String> svcFakturFields,
    required String sisaAfterDpLabel,
  }) {
    final dense = !ResponsiveLayout.isMediumOrBelow(context);
    final content = FakturContentLayout(
      orderData: orderData,
      items: items,
      fakturHeading: fakturHeading,
      orderTypeLabel: orderTypeLabel,
      isServiceOrCustom: isServiceOrCustom,
      customerName: customerName,
      customerPhone: customerPhone,
      customerAddress: customerAddress,
      orderNumber: orderNumber,
      qrPayload: qrPayload,
      svcFakturFields: svcFakturFields,
      sisaAfterDpLabel: sisaAfterDpLabel,
      branchTitleFuture: _branchTitleFuture,
      serviceCustomDpFuture: _serviceCustomDpFuture,
      dense: dense,
    );

    if (ResponsiveLayout.isMediumOrBelow(context)) {
      return ResponsiveLayout.scrollablePage(
        context: context,
        child: content,
      );
    }

    final pad = ResponsiveLayout.pagePadding(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(pad.left, 8, pad.right, 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Align(
              alignment: Alignment.topCenter,
              child: content,
            ),
          ),
        );
      },
    );
  }
}
