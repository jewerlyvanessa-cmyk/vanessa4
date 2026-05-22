import 'package:flutter/material.dart';

import 'manager_daily_payment_summary_page.dart';

/// Ringkasan pembayaran harian semua cabang (semua jenis order).
class SalesReportTodayPage extends StatelessWidget {
  const SalesReportTodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ManagerDailyPaymentSummaryPage(
      appBarTitle: 'Laporan Penjualan',
      summarySubtitlePrefix: 'Pembayaran per toko',
      summaryLeadingIcon: Icons.payments,
      showPaymentMethodNominals: true,
      branchTypeScope: 'toko',
      globalScope: true,
    );
  }
}
