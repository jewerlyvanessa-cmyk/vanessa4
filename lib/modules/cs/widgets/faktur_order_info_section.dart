import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class FakturOrderInfoSection extends StatelessWidget {
  const FakturOrderInfoSection({
    super.key,
    required this.orderData,
    required this.orderTypeLabel,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.orderNumber,
    required this.qrPayload,
    required this.dense,
  });

  final Map<String, dynamic> orderData;
  final String orderTypeLabel;
  final dynamic customerName;
  final dynamic customerPhone;
  final dynamic customerAddress;
  final String orderNumber;
  final String qrPayload;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final createdAt = orderData['created_at'] != null
        ? DateTime.parse(orderData['created_at'])
            .toLocal()
            .toString()
            .split('.')[0]
        : '-';

    Widget infoLine(String text) => Text(
          text,
          style: TextStyle(fontSize: dense ? 13 : null),
        );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        infoLine('Order ID: ${orderData['order_id'] ?? '-'}'),
        infoLine('Order Number: ${orderData['order_number'] ?? '-'}'),
        infoLine('Tipe Order: $orderTypeLabel'),
        infoLine('Status: ${orderData['status'] ?? '-'}'),
        infoLine('Tanggal: $createdAt'),
        infoLine('Customer: ${customerName ?? '-'}'),
        infoLine('No. HP: ${customerPhone ?? '-'}'),
        infoLine('Alamat: ${customerAddress ?? '-'}'),
      ],
    );

    final qrSize = dense ? 88.0 : 160.0;
    final qrWidget = qrPayload.isNotEmpty
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: qrPayload,
                version: QrVersions.auto,
                size: qrSize,
                gapless: false,
              ),
              SizedBox(height: dense ? 2 : 6),
              Text(
                orderNumber.isNotEmpty ? orderNumber : qrPayload,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: dense ? 12 : null,
                ),
              ),
            ],
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Informasi Order',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        SizedBox(height: dense ? 4 : 8),
        Card(
          elevation: 2,
          child: Padding(
            padding: EdgeInsets.all(dense ? 10 : 16),
            child: dense && qrWidget != null
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: details),
                      const SizedBox(width: 8),
                      qrWidget,
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      details,
                      if (qrWidget != null) ...[
                        SizedBox(height: dense ? 8 : 12),
                        Center(child: qrWidget),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
