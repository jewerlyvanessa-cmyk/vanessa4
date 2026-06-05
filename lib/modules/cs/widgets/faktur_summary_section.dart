import 'package:flutter/material.dart';
import 'package:vanessa3/modules/cs/logic/faktur_page_utils.dart';
import 'package:vanessa3/utils/faktur_print.dart' show fakturDpFromPayloadSync;

class FakturSummarySection extends StatelessWidget {
  const FakturSummarySection({
    super.key,
    required this.orderData,
    required this.isServiceOrCustom,
    required this.sisaAfterDpLabel,
    required this.serviceCustomDpFuture,
    required this.dense,
  });

  final Map<String, dynamic> orderData;
  final bool isServiceOrCustom;
  final String sisaAfterDpLabel;
  final Future<double> serviceCustomDpFuture;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      color: Colors.blue[50],
      child: Padding(
        padding: EdgeInsets.all(dense ? 10 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ringkasan Order',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            SizedBox(height: dense ? 4 : 8),
            if (orderData['diskon'] != null && orderData['diskon'] != '0.00')
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Diskon:', style: TextStyle(fontSize: dense ? 13 : null)),
                  Text(
                    (() {
                      final d = double.tryParse(
                        orderData['diskon'].toString(),
                      );
                      if (d == null) return '${orderData['diskon']}%';
                      final s = (d % 1 == 0)
                          ? d.toStringAsFixed(0)
                          : d.toStringAsFixed(2);
                      return '$s%';
                    })(),
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: dense ? 13 : null,
                    ),
                  ),
                ],
              ),
            if (isServiceOrCustom)
              FutureBuilder<double>(
                future: serviceCustomDpFuture,
                builder: (context, snap) {
                  final dp = snap.hasData
                      ? snap.data!
                      : fakturDpFromPayloadSync(orderData);
                  if (dp <= 0) return const SizedBox.shrink();
                  final total = FakturPageUtils.totalOrderRounded(orderData);
                  final sisa = total > dp ? total - dp : 0.0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: dense ? 4 : 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Uang Muka (DP):',
                            style: TextStyle(fontSize: dense ? 13 : null),
                          ),
                          Text(
                            'Rp ${FakturPageUtils.fmtMoney(dp)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: dense ? 13 : null,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: dense ? 2 : 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$sisaAfterDpLabel:',
                            style: TextStyle(fontSize: dense ? 13 : null),
                          ),
                          Text(
                            'Rp ${FakturPageUtils.fmtMoney(sisa)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.orange[900],
                              fontSize: dense ? 13 : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            SizedBox(height: dense ? 4 : 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Order:',
                  style: TextStyle(
                    fontSize: dense ? 15 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  (orderData['jumlah'] ?? orderData['total']) != null
                      ? 'Rp ${FakturPageUtils.fmtMoney(orderData['jumlah'] ?? FakturPageUtils.totalOrderRounded(orderData))}'
                      : 'Rp 0',
                  style: TextStyle(
                    fontSize: dense ? 15 : 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
