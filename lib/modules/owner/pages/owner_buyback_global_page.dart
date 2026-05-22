import 'package:flutter/material.dart';

import 'package:vanessa3/modules/manajer/pages/manager_daily_payment_summary_page.dart';

/// Buyback global — agregasi buyback per cabang.
class OwnerBuybackGlobalPage extends StatelessWidget {
  const OwnerBuybackGlobalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ManagerDailyPaymentSummaryPage(
      appBarTitle: 'Buyback Global',
      summarySubtitlePrefix: 'Transaksi buyback per toko',
      summaryLeadingIcon: Icons.currency_exchange,
      orderTypeFilter: 'buyback',
      showPaymentMethodNominals: true,
      branchTypeScope: 'toko',
      globalScope: true,
    );
  }
}
