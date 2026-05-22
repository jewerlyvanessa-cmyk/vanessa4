import 'package:flutter/material.dart';

import 'package:vanessa3/modules/manajer/pages/manager_daily_payment_summary_page.dart';

/// Penjualan global — agregasi pembayaran per cabang.
class OwnerSalesGlobalPage extends StatelessWidget {
  const OwnerSalesGlobalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ManagerDailyPaymentSummaryPage(
      appBarTitle: 'Penjualan Global',
      summarySubtitlePrefix: 'Pembayaran per toko',
      summaryLeadingIcon: Icons.payments,
      showPaymentMethodNominals: true,
      branchTypeScope: 'toko',
      globalScope: true,
    );
  }
}
