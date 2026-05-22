export 'faktur/faktur_constants.dart';
export 'faktur/faktur_image_fetch.dart';
export 'faktur/faktur_metadata.dart';
export 'faktur/faktur_payment_api.dart';

import 'package:flutter/material.dart';
import 'package:vanessa3/utils/faktur/faktur_constants.dart';
import 'package:vanessa3/utils/faktur/faktur_payment_api.dart';
import 'package:vanessa3/utils/faktur/faktur_pdf_impl.dart';
import 'package:vanessa3/utils/print_progress.dart';

/// Cetak PDF AMBIL SERVICE / AMBIL CUSTOM.
Future<void> printPickupServiceCustomFaktur(
  BuildContext context,
  Map<String, dynamic> orderData,
) async {
  final data = await preparePickupFakturOrderData(orderData);
  if (!context.mounted) return;
  await printFakturOrder(context, data, kind: FakturPrintKind.pickup);
}

/// Builds invoice PDF and opens system print / share UI.
Future<void> printFakturOrder(
  BuildContext context,
  Map<String, dynamic> orderData, {
  FakturPrintKind kind = FakturPrintKind.orderTransaction,
}) async {
  await runWithPrintProgress(
    context,
    () async {
      final data = Map<String, dynamic>.from(orderData);
      await enrichOrderDataForFakturPrint(data, kind: kind);
      if (!context.mounted) return;
      await printFakturOrderImpl(context, data, kind: kind);
    },
    message: 'Menyiapkan faktur…',
  );
}
