import 'package:flutter/material.dart';
import 'package:vanessa3/modules/cs/widgets/faktur_footer_actions.dart';
import 'package:vanessa3/modules/cs/widgets/faktur_header_section.dart';
import 'package:vanessa3/modules/cs/widgets/faktur_items_section.dart';
import 'package:vanessa3/modules/cs/widgets/faktur_order_info_section.dart';
import 'package:vanessa3/modules/cs/widgets/faktur_service_section.dart';
import 'package:vanessa3/modules/cs/widgets/faktur_summary_section.dart';

class FakturContentLayout extends StatelessWidget {
  const FakturContentLayout({
    super.key,
    required this.orderData,
    required this.items,
    required this.fakturHeading,
    required this.orderTypeLabel,
    required this.isServiceOrCustom,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.orderNumber,
    required this.qrPayload,
    required this.svcFakturFields,
    required this.sisaAfterDpLabel,
    required this.branchTitleFuture,
    required this.serviceCustomDpFuture,
    required this.dense,
  });

  final Map<String, dynamic> orderData;
  final List<dynamic> items;
  final String fakturHeading;
  final String orderTypeLabel;
  final bool isServiceOrCustom;
  final dynamic customerName;
  final dynamic customerPhone;
  final dynamic customerAddress;
  final String orderNumber;
  final String qrPayload;
  final Map<String, String> svcFakturFields;
  final String sisaAfterDpLabel;
  final Future<String> branchTitleFuture;
  final Future<double> serviceCustomDpFuture;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final gap = dense ? 10.0 : 24.0;
    final sectionGap = dense ? 6.0 : 8.0;

    final header = FakturHeaderSection(
      fakturHeading: fakturHeading,
      branchTitleFuture: branchTitleFuture,
      dense: dense,
    );
    final orderInfo = FakturOrderInfoSection(
      orderData: orderData,
      orderTypeLabel: orderTypeLabel,
      customerName: customerName,
      customerPhone: customerPhone,
      customerAddress: customerAddress,
      orderNumber: orderNumber,
      qrPayload: qrPayload,
      dense: dense,
    );
    final itemsSection = FakturItemsSection(items: items, dense: dense);
    final serviceSection = isServiceOrCustom
        ? FakturServiceSection(fields: svcFakturFields, dense: dense)
        : null;
    final summary = FakturSummarySection(
      orderData: orderData,
      isServiceOrCustom: isServiceOrCustom,
      sisaAfterDpLabel: sisaAfterDpLabel,
      serviceCustomDpFuture: serviceCustomDpFuture,
      dense: dense,
    );
    final footer = FakturFooterActions(dense: dense);

    if (!dense) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          SizedBox(height: gap),
          orderInfo,
          SizedBox(height: gap),
          itemsSection,
          if (serviceSection != null) ...[
            SizedBox(height: gap),
            serviceSection,
          ],
          SizedBox(height: gap),
          summary,
          SizedBox(height: gap),
          footer,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  orderInfo,
                  if (serviceSection != null) ...[
                    SizedBox(height: sectionGap),
                    serviceSection,
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  itemsSection,
                  SizedBox(height: sectionGap),
                  summary,
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        footer,
      ],
    );
  }
}
