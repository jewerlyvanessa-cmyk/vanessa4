import 'package:flutter/material.dart';

import 'manager_daily_payment_summary_page.dart';

/// Ringkasan pembayaran untuk order **buyback** saja per cabang (hari ini).
class BuybackReportTodayPage extends StatelessWidget {
  const BuybackReportTodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ManagerDailyPaymentSummaryPage(
      appBarTitle: 'Laporan Buyback',
      summarySubtitlePrefix:
          'Transaksi buyback (pembayaran selesai) per toko',
      summaryLeadingIcon: Icons.currency_exchange,
      orderTypeFilter: 'buyback',
      showPaymentMethodNominals: true,
      branchTypeScope: 'toko',
      globalScope: true,
    );
  }
}
