import 'package:flutter/material.dart';

import 'package:vanessa3/features/auth/presentation/login_page.dart';
import '../modules/cs/pages/main_page.dart';
import '../modules/cs/pages/jual_page.dart';
import '../modules/cs/pages/buyback_page.dart';
import '../modules/cs/pages/service_page.dart';
import '../modules/cs/pages/ambil_page.dart';
import '../modules/cs/pages/custom_page.dart';
import '../modules/cs/pages/customers_page.dart';
import '../modules/kasir/pages/main_page.dart';
import '../modules/superadmin/pages/main_page.dart';
import '../modules/admin_toko/pages/main_page.dart';
import '../modules/admin_toko/pages/daily_orders_payments_page.dart';
import '../modules/admin_workshop/pages/main_page.dart';
import '../modules/admin_warehouse/pages/main_page.dart';
import '../modules/admin_warehouse/pages/supplier_receipt_page.dart';
import '../modules/admin_warehouse/pages/warehouse_service_dispatch_page.dart';
import '../modules/admin_warehouse/pages/warehouse_workshop_material_page.dart';
import '../modules/common/pages/suppliers_management_page.dart';
import '../modules/tukang/pages/main_page.dart';
import '../modules/manajer/pages/main_page.dart';
import '../modules/manajer/pages/completed_orders_today_page.dart';
import '../modules/manajer/pages/branch_performance_page.dart';
import '../modules/manajer/pages/sales_report_today_page.dart';
import '../modules/manajer/pages/buyback_report_today_page.dart';
import '../modules/manajer/pages/global_stock_page.dart';
import '../modules/manajer/pages/stock_report_page.dart';
import '../modules/manajer/pages/simple_protected_page.dart';
import '../modules/manajer/pages/users_page.dart';
import '../modules/owner/pages/main_page.dart';
import '../modules/owner/pages/owner_sales_global_page.dart';
import '../modules/owner/pages/owner_buyback_global_page.dart';
import '../modules/owner/pages/owner_global_orders_page.dart';
import '../modules/admin_toko/pages/goods_transfer_page.dart';
import '../modules/admin_toko/pages/request_stock_warehouse_page.dart';
import '../modules/admin_toko/pages/service_awaiting_store_receipt_page.dart';
import '../modules/admin_toko/pages/stock_mutation_page.dart';
import '../modules/admin_toko/pages/stock_page.dart';
import '../modules/common/pages/stock_opname_page.dart';
import '../utils/stock_list_route_args.dart';
import '../modules/admin_toko/pages/employee_management_page.dart';
import '../modules/kasir/pages/payment_queue_page.dart';
import '../modules/kasir/pages/daily_payments_page.dart';
import '../modules/kasir/pages/keuangan_toko_page.dart';
import '../modules/kasir/pages/kasir_reports_page.dart';
import '../modules/kasir/pages/payment_page.dart' as kasir_payment;
import '../modules/stockist/pages/dari_toko_page.dart';
import '../modules/stockist/pages/kirim_ke_toko_page.dart';
import '../modules/stockist/pages/permintaan_stok_toko_page.dart';
import '../modules/stockist/pages/reports_page.dart';
import '../modules/stockist/pages/stock_cabang_page.dart';
import '../modules/stockist/pages/main_page.dart';
import '../modules/stockist/pages/stock_warehouse_page.dart';
import '../pages/switch_branch_role_page.dart';

class AppRoutes {
  static Widget _stockPageFromRoute(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    return StockPage(
      initialStatusFilter: StockListRouteArgs.statusFilter(args),
    );
  }

  static Widget _stockCabangPageFromRoute(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    return StockCabangPage(
      initialStatusFilter: StockListRouteArgs.statusFilter(args),
      initialBranchId: StockListRouteArgs.branchId(args),
    );
  }

  static Widget _stockistStockPageFromRoute(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    return StockWarehousePage(
      initialStatusFilter: StockListRouteArgs.statusFilter(args),
    );
  }

  static Widget _globalStockPageFromRoute(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    return GlobalStockPage(
      initialStatusFilter: StockListRouteArgs.statusFilter(args),
    );
  }

  static const String cs = '/cs';
  static const String superadmin = '/superadmin';
  static const String login = '/login';
  static const String dashboard = '/dashboard';
  static const String kasir = '/kasir';
  static const String tukang = '/tukang';
  static const String adminToko = '/admin_toko';
  static const String adminWorkshop = '/admin_workshop';
  static const String adminWarehouse = '/admin_warehouse';
  static const String manajer = '/manager';
  static const String owner = '/owner';
  static const String ownerSalesGlobal = '/owner/sales';
  static const String ownerBuybackGlobal = '/owner/buyback';
  static const String ownerGlobalStock = '/owner/stock';
  static const String ownerGlobalOrders = '/owner/orders';
  static const String customers = '/customers';
  static const String manajerCompletedOrdersToday =
      '/manager/completed_orders_today';
  static const String manajerBranchPerformance = '/manager/branch_performance';
  static const String manajerSalesToday = '/manager/sales_today';
  static const String manajerBuybackReport = '/manager/buyback_report';
  static const String manajerGlobalStock = '/manager/global_stock';
  static const String manajerStockCabang = '/manager/stock_cabang';
  static const String manajerStockReport = '/manager/stock_report';
  static const String manajerStockOpname = '/manager/stock_opname';
  static const String adminWorkshopStockOpname = '/admin_workshop/stock_opname';
  static const String manajerEmployees = '/manager/employees';
  static const String warehouseStock = '/warehouse/stock';
  static const String warehouseGoodsTransfer = '/warehouse/goods_transfer';
  static const String warehouseStockMutation = '/warehouse/stock_mutation';
  static const String warehouseStockOpname = '/warehouse/stock_opname';
  static const String warehouseStockRequests = '/warehouse/stock_requests';
  static const String warehouseFromStore = '/warehouse/from_store';
  static const String warehouseToStore = '/warehouse/to_store';
  static const String warehouseEmployees = '/warehouse/employees';
  static const String warehouseStockInputReport = '/warehouse/stock_input_report';
  static const String warehouseSupplierReceipt = '/warehouse/supplier_receipt';
  static const String warehouseSuppliers = '/warehouse/suppliers';
  static const String manajerSuppliers = '/manager/suppliers';
  static const String warehouseWorkshopService = '/warehouse/workshop/service';
  static const String warehouseWorkshopGoods = '/warehouse/workshop/goods';
  static const String warehouseWorkshopMaterial = '/warehouse/workshop/material';
  static const String adminTokoOrders = '/admin_toko/orders';
  static const String adminTokoServiceCustom = '/admin_toko/service_custom';
  static const String adminTokoWorkshopReceipt = '/admin_toko/workshop_receipt';
  static const String adminTokoStock = '/admin_toko/stock';
  static const String adminTokoGoodsTransfer = '/admin_toko/goods_transfer';
  static const String adminTokoStockRequest = '/admin_toko/stock_request';
  static const String adminTokoStockMutation = '/admin_toko/stock_mutation';
  static const String adminTokoStockOpname = '/admin_toko/stock_opname';
  static const String adminTokoEmployees = '/admin_toko/employees';
  static const String adminWorkshopEmployees = '/admin_workshop/employees';
  static const String adminWorkshopGoodsTransfer = '/admin_workshop/goods_transfer';
  static const String adminWorkshopKeuangan = '/admin_workshop/keuangan';
  static const String adminWarehouseKeuangan = '/admin_warehouse/keuangan';
  static const String kasirPaymentQueue = '/kasir/payment_queue';
  static const String kasirDailyPayments = '/kasir/daily_payments';
  static const String kasirKeuangan = '/kasir/keuangan';
  static const String kasirReports = '/kasir/reports';
  static const String kasirPayment = '/kasir/payment';
  static const String manajerKeuangan = '/manager/keuangan';
  static const String manajerSystemSettings = '/manager/system_settings';
  static const String stockist = '/stockist';
  static const String stockistStock = '/stockist/stock';
  static const String stockistStockOpname = '/stockist/stock_opname';
  static const String switchBranchRole = '/switch_branch_role';
  static Map<String, WidgetBuilder> get routes => {
    login: (context) => const LoginPage(),
    dashboard: (context) => const DailyOrdersPaymentsPage(),
    cs: (context) => const CSMainPage(),
    kasir: (context) => const KasirMainPage(),
    superadmin: (context) => const SuperadminMainPage(),
    adminToko: (context) => const AdminTokoMainPage(),
    adminWorkshop: (context) => const AdminWorkshopMainPage(),
    adminWarehouse: (context) => const AdminWarehouseMainPage(),
    tukang: (context) => const TukangMainPage(),
    manajer: (context) => const ManajerMainPage(),
    owner: (context) => const OwnerMainPage(),
    ownerSalesGlobal: (context) => const OwnerSalesGlobalPage(),
    ownerBuybackGlobal: (context) => const OwnerBuybackGlobalPage(),
    ownerGlobalStock: _globalStockPageFromRoute,
    ownerGlobalOrders: (context) => const OwnerGlobalOrdersPage(),
    manajerCompletedOrdersToday: (context) => const CompletedOrdersTodayPage(),
    manajerBranchPerformance: (context) => const BranchPerformancePage(),
    manajerSalesToday: (context) => const SalesReportTodayPage(),
    manajerBuybackReport: (context) => const BuybackReportTodayPage(),
    manajerGlobalStock: _globalStockPageFromRoute,
    manajerStockCabang: _stockCabangPageFromRoute,
    manajerStockReport: (context) => const StockReportPage(),
    manajerEmployees: (context) => const ManagerUsersPage(),
    manajerKeuangan: (context) => const KeuanganTokoPage(
          scope: StoreOperationalPageScope.manajer,
          title: 'Pencatatan Keuangan',
        ),
    warehouseStock: _stockPageFromRoute,
    warehouseGoodsTransfer: (context) =>
        const GoodsTransferPage(branchTypeScope: 'warehouse'),
    warehouseStockMutation: (context) => const StockMutationPage(),
    warehouseStockOpname: (context) => const StockOpnamePage(
          title: 'Stok Opname Gudang',
          missingStockRouteName: AppRoutes.warehouseStock,
        ),
    warehouseStockRequests: (context) => const PermintaanStokTokoPage(),
    warehouseFromStore: (context) => const DariTokoPage(),
    warehouseToStore: (context) => const KirimKeTokoPage(),
    warehouseEmployees: (context) => const EmployeeManagementPage(),
    warehouseStockInputReport: (context) => const StockistReportsPage(
          mode: StockInputReportMode.activeBranch,
        ),
    warehouseSupplierReceipt: (context) => const SupplierReceiptPage(),
    warehouseSuppliers: (context) => const SuppliersManagementPage(),
    manajerSuppliers: (context) => const SuppliersManagementPage(),
    warehouseWorkshopService: (context) =>
        const WarehouseServiceDispatchPage(),
    warehouseWorkshopGoods: (context) => const GoodsTransferPage(
          branchTypeScope: 'warehouse',
          destinationBranchTypeScope: 'workshop',
        ),
    warehouseWorkshopMaterial: (context) =>
        const WarehouseWorkshopMaterialPage(),
    adminTokoOrders: (context) => const DailyOrdersPaymentsPage(),
    adminTokoServiceCustom: (context) => const DailyOrdersPaymentsPage(
      serviceCustomMode: true,
    ),
    adminTokoWorkshopReceipt: (context) =>
        const ServiceAwaitingStoreReceiptPage(),
    adminTokoStock: _stockPageFromRoute,
    adminTokoGoodsTransfer: (context) =>
        const GoodsTransferPage(branchTypeScope: 'toko'),
    adminTokoStockRequest: (context) => const RequestStockWarehousePage(),
    adminTokoStockMutation: (context) => const StockMutationPage(),
    adminTokoStockOpname: (context) => const StockOpnamePage(
          title: 'Stok Opname Toko',
          missingStockRouteName: AppRoutes.adminTokoStock,
        ),
    manajerStockOpname: (context) => const StockOpnamePage(
          title: 'Stok Opname',
          allowBranchPicker: true,
          missingStockRouteName: AppRoutes.manajerStockCabang,
        ),
    adminWorkshopStockOpname: (context) => const StockOpnamePage(
          title: 'Stok Opname Material',
          stockTypeFilter: 'non_inventory',
        ),
    adminTokoEmployees: (context) => const EmployeeManagementPage(),
    adminWorkshopEmployees: (context) => const EmployeeManagementPage(),
    adminWorkshopGoodsTransfer: (context) =>
        const GoodsTransferPage(branchTypeScope: 'workshop'),
    adminWorkshopKeuangan: (context) => const KeuanganTokoPage(
          title: 'Pencatatan Keuangan',
        ),
    adminWarehouseKeuangan: (context) => const KeuanganTokoPage(
          title: 'Pencatatan Keuangan',
        ),
    kasirPaymentQueue: (context) => const PaymentQueuePage(),
    kasirDailyPayments: (context) => const DailyPaymentsPage(),
    kasirKeuangan: (context) => const KeuanganTokoPage(),
    kasirReports: (context) => const KasirReportsPage(),
    manajerSystemSettings: (context) => const SimpleProtectedPage(
      title: 'Pengaturan Sistem',
      description:
          'Halaman ini siap digunakan.\n\nJika Anda ingin fitur pengaturan sistem untuk manajer, beritahu pengaturan apa saja yang perlu ditambahkan (mis. target bulanan, batas diskon, dsb).',
    ),
    stockist: (context) => const StockistMainPage(),
    stockistStock: _stockistStockPageFromRoute,
    stockistStockOpname: (context) => const StockOpnamePage(
          title: 'Stok Opname',
          missingStockRouteName: AppRoutes.stockistStock,
        ),
    switchBranchRole: (context) => const SwitchBranchRolePage(),
    customers: (context) => const CustomersPage(),
    '/jual': (context) => const JualPage(),
    '/buyback': (context) => const BuybackPage(),
    '/service': (context) => const ServicePage(),
    '/custom': (context) => const CustomPage(),
    '/ambil': (context) => const AmbilPage(),
  };

  /// Rute yang membutuhkan [RouteSettings.arguments].
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case kasirPayment:
        final args = settings.arguments;
        if (args is! Map<String, dynamic>) {
          return _missingArgsRoute(settings);
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => kasir_payment.PaymentPage(order: args),
        );
      default:
        return null;
    }
  }

  static MaterialPageRoute<void> _missingArgsRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Navigasi gagal')),
        body: const Center(
          child: Text('Argumen halaman tidak valid.'),
        ),
      ),
    );
  }
}
