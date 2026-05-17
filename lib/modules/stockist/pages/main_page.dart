import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vanessa3/shared_widgets/user_branch_role_header.dart';
import 'package:vanessa3/shared_widgets/module_menu_grid.dart';
import 'package:vanessa3/shared_widgets/module_dashboard_app_bar.dart';
import 'package:vanessa3/shared_widgets/role_menu_body.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

import 'stock_warehouse_page.dart';
import 'stock_bulk_input_page.dart';
import 'stock_standard_input_page.dart';
import 'stock_reprint_qr_page.dart';
import 'reports_page.dart';

class StockistMainPage extends ConsumerWidget {
  const StockistMainPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const ModuleDashboardAppBar(title: 'Stockist'),
      body: RoleMenuBody(
        child: ResponsiveLayout.roleMenuListView(
        context: context,
        children: [
          Padding(
            padding: ResponsiveLayout.roleMenuHeaderPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [UserBranchRoleHeader()],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ModuleMenuGrid(
              minCrossAxisCount: 4,
              entries: [
                ModuleMenuEntry(
                  icon: Icons.playlist_add,
                  label: 'INPUT STOK (MASSAL)',
                  iconColor: Colors.deepPurple,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => const StockBulkInputPage(),
                    ),
                  ),
                ),
                ModuleMenuEntry(
                  icon: Icons.post_add,
                  label: 'INPUT STOK (STANDAR)',
                  iconColor: Colors.deepOrange,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => const StockStandardInputPage(),
                    ),
                  ),
                ),
                ModuleMenuEntry(
                  icon: Icons.inventory_2,
                  label: 'STOK',
                  iconColor: Colors.blue,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const StockWarehousePage(),
                    ),
                  ),
                ),
                ModuleMenuEntry(
                  icon: Icons.qr_code_2,
                  label: 'CETAK ULANG LABEL',
                  iconColor: Colors.brown,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => const StockReprintQrPage(),
                    ),
                  ),
                ),
                ModuleMenuEntry(
                  icon: DashboardMenuIcons.laporan,
                  label: 'LAPORAN INPUT STOK',
                  iconColor: Colors.indigo,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const StockistReportsPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        ),
      ),
    );
  }
}
