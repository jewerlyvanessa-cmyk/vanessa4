import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math;
import 'dart:typed_data';

import '../features/auth/domain/auth_repository.dart';

// Conditional imports for platform-specific packages
import 'package:image_picker/image_picker.dart'
    if (dart.library.html) '../utils/image_picker_stub.dart';
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
import '../pages/switch_branch_role_page.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/responsive_layout.dart';
import '../providers/websocket_provider.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

class AppRoutes {
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
  static const String manajerEmployees = '/manager/employees';
  static const String warehouseStock = '/warehouse/stock';
  static const String warehouseGoodsTransfer = '/warehouse/goods_transfer';
  static const String warehouseStockMutation = '/warehouse/stock_mutation';
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
  static const String adminTokoEmployees = '/admin_toko/employees';
  static const String adminWorkshopEmployees = '/admin_workshop/employees';
  static const String adminWorkshopGoodsTransfer = '/admin_workshop/goods_transfer';
  static const String kasirPaymentQueue = '/kasir/payment_queue';
  static const String kasirDailyPayments = '/kasir/daily_payments';
  static const String kasirKeuangan = '/kasir/keuangan';
  static const String kasirReports = '/kasir/reports';
  static const String kasirPayment = '/kasir/payment';
  static const String manajerSystemSettings = '/manager/system_settings';
  static const String stockist = '/stockist';
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
    ownerGlobalStock: (context) => const GlobalStockPage(),
    ownerGlobalOrders: (context) => const OwnerGlobalOrdersPage(),
    manajerCompletedOrdersToday: (context) => const CompletedOrdersTodayPage(),
    manajerBranchPerformance: (context) => const BranchPerformancePage(),
    manajerSalesToday: (context) => const SalesReportTodayPage(),
    manajerBuybackReport: (context) => const BuybackReportTodayPage(),
    manajerGlobalStock: (context) => const GlobalStockPage(),
    manajerStockCabang: (context) => const StockCabangPage(),
    manajerStockReport: (context) => const StockReportPage(),
    manajerEmployees: (context) => const ManagerUsersPage(),
    warehouseStock: (context) => const StockPage(),
    warehouseGoodsTransfer: (context) =>
        const GoodsTransferPage(branchTypeScope: 'warehouse'),
    warehouseStockMutation: (context) => const StockMutationPage(),
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
    adminTokoStock: (context) => const StockPage(),
    adminTokoGoodsTransfer: (context) =>
        const GoodsTransferPage(branchTypeScope: 'toko'),
    adminTokoStockRequest: (context) => const RequestStockWarehousePage(),
    adminTokoStockMutation: (context) => const StockMutationPage(),
    adminTokoEmployees: (context) => const EmployeeManagementPage(),
    adminWorkshopEmployees: (context) => const EmployeeManagementPage(),
    adminWorkshopGoodsTransfer: (context) =>
        const GoodsTransferPage(branchTypeScope: 'workshop'),
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

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void login() async {
    if (formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final username = usernameController.text;
      final password = passwordController.text;

      try {
        final result = await const AuthRepository().login(username, password);

        if (result['success'] == true) {
          // Handle navigation based on user's primary role and branch
          final roles = List<String>.from(result['roles'] ?? []);
          final branches = List<Map<String, dynamic>>.from(
            result['branches'] ?? [],
          );

          // Use primary role and branch from login response
          final primaryRoleRaw = (result['role'] ?? '').toString();
          final primaryRole = primaryRoleRaw.trim().toLowerCase();
          final primaryBranch = result['branch'] ?? '';

          final userStateNotifier = ref.read(userStateProvider.notifier);
          userStateNotifier.setUserData(
            userId: int.tryParse(result['user_id'].toString()),
            username: result['username'] ?? '',
            branch: primaryBranch,
            role: primaryRole,
            authToken: result['token'] ?? '',
            roles: roles,
            branches: branches,
          );

          // Initialize WebSocket connection after successful login
          ref.read(webSocketProvider.notifier).initializeAfterLogin();

          // Navigate directly to main module based on primary role
          String route = '';
          switch (primaryRole) {
            case 'cs':
              route = AppRoutes.cs;
              break;
            case 'kasir':
              route = AppRoutes.kasir;
              break;
            case 'superadmin':
              route = AppRoutes.superadmin;
              break;
            case 'admin_toko':
              route = AppRoutes.adminToko;
              break;
            case 'admin_workshop':
              route = AppRoutes.adminWorkshop;
              break;
            case 'admin_warehouse':
              route = AppRoutes.adminWarehouse;
              break;
            case 'manajer':
              route = AppRoutes.manajer;
              break;
            case 'owner':
              route = AppRoutes.owner;
              break;
            case 'tukang':
              route = AppRoutes.tukang;
              break;
            case 'stockist':
              route = AppRoutes.stockist;
              break;
            default:
              route = AppRoutes.dashboard;
          }
          debugPrint('Navigating to route: $route for role: $primaryRoleRaw');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Use `mounted` (State) guard first; accessing `context` when unmounted throws.
            if (!mounted) return;
            Navigator.pushReplacementNamed(context, route);
          });
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result['error'] ?? 'Login gagal')),
            );
          });
        }
      } catch (e) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Terjadi error saat login')));
        });
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final formMaxW = screenW > 600 ? 400.0 : screenW.clamp(280.0, 600.0);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: ResponsiveLayout.scrollableCenteredPage(
        context: context,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: formMaxW),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                  // Logo di atas username
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: Center(
                      child: Image.asset('assets/logo.png', height: 100),
                    ),
                  ),
                  TextFormField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Username tidak boleh kosong'
                        : null,
                    textInputAction: TextInputAction.next,
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    obscureText: true,
                    validator: (value) => value == null || value.isEmpty
                        ? 'Password tidak boleh kosong'
                        : null,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => login(),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : login,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text('Login', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'Versi 1.0.0',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Tambahkan integrasi WebSocket untuk pembaruan realtime
class WebSocketService {
  final WebSocketChannel channel;

  WebSocketService(String url)
    : channel = WebSocketChannel.connect(Uri.parse(url));

  void listen(void Function(dynamic) onMessage) {
    channel.stream.listen(onMessage);
  }

  void sendMessage(String message) {
    channel.sink.add(message);
  }

  void dispose() {
    channel.sink.close();
  }
}

final branchRoleProvider =
    StateNotifierProvider<BranchRoleNotifier, BranchRoleState>((ref) {
      return BranchRoleNotifier();
    });

class BranchRoleNotifier extends StateNotifier<BranchRoleState> {
  BranchRoleNotifier() : super(BranchRoleState());

  void setBranch(String branch) {
    state = state.copyWith(branch: branch);
  }

  void setRole(String role) {
    state = state.copyWith(role: role);
  }
}

class BranchRoleState {
  final String branch;
  final String role;

  BranchRoleState({this.branch = '', this.role = ''});

  BranchRoleState copyWith({String? branch, String? role}) {
    return BranchRoleState(
      branch: branch ?? this.branch,
      role: role ?? this.role,
    );
  }
}

// Tambahkan fitur untuk switch branch/role di dashboard
class SwitchBranchRoleWidget extends ConsumerWidget {
  const SwitchBranchRoleWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchRole = ref.watch(branchRoleProvider);
    final branchNotifier = ref.read(branchRoleProvider.notifier);

    return Column(
      children: [
        DropdownButton<String>(
          value: branchRole.branch,
          items: ['Branch1', 'Branch2', 'Branch3'].map((branch) {
            return DropdownMenuItem(value: branch, child: Text(branch));
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              branchNotifier.setBranch(value);
            }
          },
        ),
        DropdownButton<String>(
          value: branchRole.role,
          items: ['Role1', 'Role2', 'Role3'].map((role) {
            return DropdownMenuItem(value: role, child: Text(role));
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              branchNotifier.setRole(value);
            }
          },
        ),
        ElevatedButton(
          onPressed: () {
            // Perform action with selected branch and role
          },
          child: const Text('Switch'),
        ),
      ],
    );
  }
}

// Tambahkan fitur reporting dengan grafik menggunakan fl_chart
class ReportingPage extends StatelessWidget {
  const ReportingPage({super.key, required this.data});

  final List<double> data;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Reporting')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: LineChart(
          LineChartData(
            gridData: FlGridData(show: true),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: true),
              ),
            ),
            borderData: FlBorderData(show: true),
            lineBarsData: [
              LineChartBarData(
                spots: data
                    .asMap()
                    .entries
                    .map((e) => FlSpot(e.key.toDouble(), e.value))
                    .toList(),
                isCurved: true,
                gradient: LinearGradient(colors: [Colors.blue]),
                barWidth: 4,
                belowBarData: BarAreaData(show: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OrderPage extends StatelessWidget {
  const OrderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order Page')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/jual');
              },
              child: const Text('Sell Order'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/buyback');
              },
              child: const Text('Buyback Order'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/service');
              },
              child: const Text('Service Order'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/custom');
              },
              child: const Text('Custom Order'),
            ),
          ],
        ),
      ),
    );
  }
}

class ScanQRUploadPhotoPage extends StatefulWidget {
  const ScanQRUploadPhotoPage({super.key});

  @override
  State<ScanQRUploadPhotoPage> createState() => _ScanQRUploadPhotoPageState();
}

class _ScanQRUploadPhotoPageState extends State<ScanQRUploadPhotoPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _image;

  Future<void> _pickImage() async {
    final pickedImage = await _picker.pickImage(source: ImageSource.gallery);
    setState(() {
      _image = pickedImage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR / Upload Photo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _pickImage,
              child: const Text('Upload Photo'),
            ),
            if (_image != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: FutureBuilder<Uint8List>(
                  future: _image!.readAsBytes(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox(
                        height: 120,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return Image.memory(snapshot.data!);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ManualInputItemPage extends StatefulWidget {
  const ManualInputItemPage({super.key});

  @override
  State<ManualInputItemPage> createState() => _ManualInputItemPageState();
}

class _ManualInputItemPageState extends State<ManualInputItemPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _materialController = TextEditingController();
  final TextEditingController _purityController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manual Input Item')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Item Name'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter the item name';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _weightController,
                decoration: const InputDecoration(labelText: 'Weight'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter the weight';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _materialController,
                decoration: const InputDecoration(labelText: 'Material'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter the material';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _purityController,
                decoration: const InputDecoration(labelText: 'Purity'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter the purity';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _methodController = TextEditingController();

  void _processPayment() {
    if (_formKey.currentState!.validate()) {
      // Simulate payment processing
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment processed successfully!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment System')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter the amount';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _methodController,
                decoration: const InputDecoration(labelText: 'Payment Method'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter the payment method';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _processPayment,
                child: const Text('Process Payment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WorkshopPage extends StatefulWidget {
  const WorkshopPage({super.key});

  @override
  State<WorkshopPage> createState() => _WorkshopPageState();
}

class _WorkshopPageState extends State<WorkshopPage> {
  final List<Map<String, String>> _workOrders = [
    {'id': '1', 'type': 'Service', 'status': 'In Progress'},
    {'id': '2', 'type': 'Custom', 'status': 'Pending'},
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = <DataRow>[];
    for (var i = 0; i < _workOrders.length; i++) {
      final order = _workOrders[i];
      rows.add(
        DataRow(
          color: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.hovered)) {
              return cs.primary.withValues(alpha: 0.06);
            }
            return i.isOdd
                ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
                : null;
          }),
          cells: [
            DataCell(Text(order['id'] ?? '—')),
            DataCell(Text(order['type'] ?? '—')),
            DataCell(Text(order['status'] ?? '—')),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Workshop Orders')),
      body: LayoutBuilder(
        builder: (context, c) {
          final minW = math.max(c.maxWidth, 480.0);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Material(
              elevation: 0,
              color: cs.surfaceContainerLow.withValues(alpha: 0.65),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: minW),
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        cs.surfaceContainerHigh,
                      ),
                      showCheckboxColumn: false,
                      columns: [
                        DataColumn(label: dataTableColumnLabel('Order ID')),
                        DataColumn(label: dataTableColumnLabel('Type')),
                        DataColumn(label: dataTableColumnLabel('Status')),
                      ],
                      rows: rows,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
