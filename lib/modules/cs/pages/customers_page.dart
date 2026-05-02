import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../utils/network_config.dart';
import '../../../utils/logger.dart';
import 'package:vanessa3/main.dart'; // Import global userStateProvider
import 'package:vanessa3/providers/websocket_provider.dart';

final customersProvider =
    StateNotifierProvider<CustomersNotifier, CustomersState>(
      (ref) => CustomersNotifier(),
    );

class CustomersState {
  final List<Map<String, dynamic>> customers;
  final bool isLoading;
  final String? error;

  const CustomersState({
    required this.customers,
    this.isLoading = false,
    this.error,
  });

  CustomersState copyWith({
    List<Map<String, dynamic>>? customers,
    bool? isLoading,
    String? error,
  }) {
    return CustomersState(
      customers: customers ?? this.customers,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class CustomersNotifier extends StateNotifier<CustomersState> {
  CustomersNotifier() : super(const CustomersState(customers: []));

  Future<void> fetchCustomers({String? branchId}) async {
    state = state.copyWith(isLoading: true, error: null);

    final uri = Uri.parse('${NetworkConfig.baseUrl}/api/customers').replace(
      queryParameters: branchId != null ? {'branch_id': branchId} : null,
    );
    Logger.logInfo('DEBUG: Fetching customers from: $uri');
    try {
      final response = await http.get(
        uri,
        headers: NetworkConfig.defaultHeaders,
      );
      Logger.logInfo('DEBUG: Response status: ${response.statusCode}');
      Logger.logInfo('DEBUG: Response body length: ${response.body.length}');
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        Logger.logInfo('DEBUG: Response data type: ${responseData.runtimeType}');
        // API returns data directly as array, not wrapped in success/data structure
        if (responseData is List) {
          state = state.copyWith(
            customers: List<Map<String, dynamic>>.from(responseData),
            isLoading: false,
          );
          Logger.logInfo(
            'DEBUG: Successfully loaded ${responseData.length} customers',
          );
        } else {
          state = state.copyWith(
            isLoading: false,
            error: 'Format data pelanggan tidak valid',
          );
          Logger.logInfo('DEBUG: Invalid data format');
        }
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to load customers: ${response.statusCode}',
        );
        Logger.logInfo(
          'DEBUG: Failed to load customers: ${response.statusCode}',
        );
      }
    } catch (error) {
      Logger.logInfo('DEBUG: Error fetching customers: $error');
      state = state.copyWith(
        customers: [],
        isLoading: false,
        error: 'Network error occurred: $error',
      );
    }
  }

  Future<void> addCustomer(
    String name,
    String email,
    String phone,
    String address,
  ) async {
    state = state.copyWith(isLoading: true, error: null);

    final url = Uri.parse('${NetworkConfig.baseUrl}/api/customers');
    try {
      final response = await http.post(
        url,
        headers: NetworkConfig.defaultHeaders,
        body: json.encode({
          'name': name,
          'email': email,
          'phone': phone,
          'address': address,
        }),
      );
      if (response.statusCode == 201) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          await fetchCustomers(); // This will set loading to false
        } else {
          state = state.copyWith(
            isLoading: false,
            error: responseData['message'] ?? 'Failed to add customer',
          );
        }
      } else {
        final responseData = json.decode(response.body);
        state = state.copyWith(
          isLoading: false,
          error: responseData['message'] ?? 'Failed to add customer',
        );
      }
    } catch (error) {
      state = state.copyWith(isLoading: false, error: 'Network error occurred');
    }
  }

  Future<bool> editCustomer(
    String id,
    String name,
    String email,
    String phone,
    String address,
  ) async {
    state = state.copyWith(isLoading: true, error: null);

    final url = Uri.parse('${NetworkConfig.baseUrl}/api/customers/$id');
    try {
      final response = await http.patch(
        url,
        headers: NetworkConfig.defaultHeaders,
        body: json.encode({
          'name': name,
          'email': email,
          'phone': phone,
          'address': address,
        }),
      );
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          await fetchCustomers(); // This will set loading to false
          return true;
        } else {
          state = state.copyWith(
            isLoading: false,
            error: responseData['message'] ?? 'Failed to update customer',
          );
          return false;
        }
      } else {
        final responseData = json.decode(response.body);
        state = state.copyWith(
          isLoading: false,
          error: responseData['message'] ?? 'Failed to update customer',
        );
        return false;
      }
    } catch (error) {
      state = state.copyWith(isLoading: false, error: 'Network error occurred');
      return false;
    }
  }

  Future<void> deleteCustomer(String id) async {
    state = state.copyWith(isLoading: true, error: null);

    final url = Uri.parse('${NetworkConfig.baseUrl}/api/customers/$id');
    try {
      final response = await http.delete(url);
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          await fetchCustomers(); // This will set loading to false
        } else {
          state = state.copyWith(
            isLoading: false,
            error: responseData['message'] ?? 'Failed to delete customer',
          );
        }
      } else {
        final responseData = json.decode(response.body);
        state = state.copyWith(
          isLoading: false,
          error: responseData['message'] ?? 'Failed to delete customer',
        );
      }
    } catch (error) {
      state = state.copyWith(isLoading: false, error: 'Network error occurred');
    }
  }
}

class CustomersPage extends ConsumerWidget {
  const CustomersPage({super.key});

  bool _canSeeGlobalTransactions(String roleRaw) {
    final role = roleRaw.trim().toLowerCase();
    return role == 'manajer' || role == 'admin_toko';
  }

  Future<List<Map<String, dynamic>>> _fetchCustomerTransactions({
    required String customerId,
    String? branchId,
  }) async {
    final uri = Uri.parse(
      '${NetworkConfig.baseUrl}/api/customers/$customerId/transactions',
    ).replace(
      queryParameters: (branchId == null || branchId.toString().trim().isEmpty)
          ? null
          : {'branch_id': branchId},
    );

    final response = await http.get(uri, headers: NetworkConfig.defaultHeaders);
    if (response.statusCode != 200) {
      throw Exception('Gagal memuat riwayat transaksi (${response.statusCode})');
    }
    final data = json.decode(response.body);
    if (data is! List) return <Map<String, dynamic>>[];
    return List<Map<String, dynamic>>.from(
      data.map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  String _fmtRp(dynamic v) {
    final n = double.tryParse(v?.toString() ?? '');
    if (n == null) return '0';
    final s = n.toStringAsFixed(0);
    return s.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

  String _fmtDateTime(dynamic v) {
    try {
      final dt = DateTime.tryParse(v?.toString() ?? '');
      if (dt == null) return '-';
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$y-$m-$d $hh:$mm';
    } catch (_) {
      return '-';
    }
  }

  void _showCustomerTransactions(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> customer,
  ) {
    final userState = ref.read(userStateProvider);
    if (!_canSeeGlobalTransactions(userState.role)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Riwayat transaksi hanya untuk Manajer & Admin Toko'),
        ),
      );
      return;
    }

    final customerId = (customer['customer_id'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer['name'] ?? 'Pelanggan',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '📞 ${customer['phone'] ?? 'N/A'}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Riwayat Transaksi (Global)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: () {
                          // Rebuild by popping and reopening (simple & reliable)
                          Navigator.of(context).pop();
                          _showCustomerTransactions(context, ref, customer);
                        },
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: _fetchCustomerTransactions(
                        customerId: customerId,
                        // Global lintas cabang: tanpa filter branch_id
                        branchId: null,
                      ),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snap.hasError) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  size: 56,
                                  color: Colors.red,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  snap.error.toString(),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          );
                        }

                        final rows = snap.data ?? const [];
                        if (rows.isEmpty) {
                          return const Center(
                            child: Text('Belum ada transaksi untuk pelanggan ini'),
                          );
                        }

                        return ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final r = rows[i];
                            final orderId = (r['order_id'] ?? 'N/A').toString();
                            final orderType = (r['order_type'] ?? '').toString();
                            final orderStatus =
                                (r['order_status'] ?? '').toString();
                            final paymentStatus =
                                (r['payment_status'] ?? '').toString();
                            final method =
                                (r['payment_method'] ?? '').toString();
                            final amount = r['jumlah'] ?? r['total'] ?? 0;

                            final paidLabel = paymentStatus.isEmpty
                                ? 'Belum bayar'
                                : paymentStatus;

                            return Card(
                              child: ListTile(
                                title: Text(
                                  'Order #$orderId'
                                  '${orderType.isNotEmpty ? ' • $orderType' : ''}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text('Tanggal: ${_fmtDateTime(r['created_at'])}'),
                                    Text('Status order: ${orderStatus.isEmpty ? '-' : orderStatus}'),
                                    Text(
                                      'Pembayaran: $paidLabel'
                                      '${method.isNotEmpty ? ' • $method' : ''}',
                                    ),
                                    if ((r['payment_date'] ?? '').toString().isNotEmpty)
                                      Text(
                                        'Tgl bayar: ${_fmtDateTime(r['payment_date'])}',
                                      ),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Rp ${_fmtRp(amount)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Total',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Nama tidak boleh kosong';
    }
    if (value.trim().length < 2) {
      return 'Nama minimal 2 karakter';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email tidak boleh kosong';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Format email tidak valid';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Nomor telepon tidak boleh kosong';
    }
    final phoneRegex = RegExp(r'^[\+]?[0-9]{10,15}$');
    if (!phoneRegex.hasMatch(value.trim())) {
      return 'Nomor telepon tidak valid (10-15 digit)';
    }
    return null;
  }

  String? _validateAddress(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Alamat tidak boleh kosong';
    }
    if (value.trim().length < 10) {
      return 'Alamat minimal 10 karakter';
    }
    return null;
  }

  Widget _buildSummaryCard(
    String title,
    int count,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _handleCustomerAction(
    BuildContext context,
    Map<String, dynamic> customer,
    String action,
    WidgetRef ref,
  ) {
    switch (action) {
      case 'edit':
        _showEditCustomerDialog(context, customer, ref);
        break;
      case 'delete':
        _showDeleteConfirmation(context, customer, ref);
        break;
    }
  }

  void _showEditCustomerDialog(
    BuildContext context,
    Map<String, dynamic> customer,
    WidgetRef ref,
  ) {
    final customersNotifier = ref.read(customersProvider.notifier);
    final nameController = TextEditingController(text: customer['name'] ?? '');
    final emailController = TextEditingController(
      text: customer['email'] ?? '',
    );
    final phoneController = TextEditingController(
      text: customer['phone'] ?? '',
    );
    final addressController = TextEditingController(
      text: customer['address'] ?? '',
    );

    showDialog(
      context: context,
      builder: (context) {
        final formKey = GlobalKey<FormState>();
        return AlertDialog(
          title: const Text('Edit Pelanggan'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Nama'),
                    validator: _validateName,
                  ),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: _validateEmail,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  TextFormField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Nomor Telepon',
                    ),
                    validator: _validatePhone,
                    keyboardType: TextInputType.phone,
                  ),
                  TextFormField(
                    controller: addressController,
                    decoration: const InputDecoration(labelText: 'Alamat'),
                    validator: _validateAddress,
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  final id = customer['customer_id']?.toString() ?? '';
                  final success = await customersNotifier.editCustomer(
                    id,
                    nameController.text.trim(),
                    emailController.text.trim(),
                    phoneController.text.trim(),
                    addressController.text.trim(),
                  );
                  if (success) {
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Gagal menyimpan perubahan customer!'),
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(
    BuildContext context,
    Map<String, dynamic> customer,
    WidgetRef ref,
  ) {
    final customersNotifier = ref.read(customersProvider.notifier);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Pelanggan'),
        content: Text(
          'Apakah Anda yakin ingin menghapus pelanggan "${customer['name']}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await customersNotifier.deleteCustomer(
                customer['customer_id']?.toString() ?? '',
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersState = ref.watch(customersProvider);
    final customersNotifier = ref.read(customersProvider.notifier);
    final userState = ref.watch(userStateProvider);

    // Listen to real-time customer updates
    ref.listen(realTimeOrderUpdatesProvider, (previous, next) {
      next.whenData((update) {
        if (update['type'] == 'customer_update' ||
            update['type'] == 'order_update') {
          // Refresh customer data when customer-related updates occur
          customersNotifier.fetchCustomers(branchId: userState.branch);
        }
      });
    });

    // Fetch customers jika belum ada data dan tidak loading
    if (!customersState.isLoading &&
        customersState.customers.isEmpty &&
        customersState.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        customersNotifier.fetchCustomers(branchId: userState.branch);
      });
    }

    if (customersState.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pelanggan')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (customersState.error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pelanggan')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: ${customersState.error}'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => customersNotifier.fetchCustomers(),
                child: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pelanggan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => customersNotifier.fetchCustomers(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: customersState.customers.isEmpty
          ? const Center(child: Text('Belum ada data pelanggan'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary Cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          'Total Pelanggan',
                          customersState.customers.length,
                          Icons.people,
                          Colors.blue,
                        ),
                      ),
                      Expanded(
                        child: _buildSummaryCard(
                          'Dengan Email',
                          customersState.customers
                              .where(
                                (c) =>
                                    c['email'] != null &&
                                    c['email'].toString().isNotEmpty,
                              )
                              .length,
                          Icons.email,
                          Colors.green,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Customers List
                  Text(
                    'Daftar Pelanggan (${customersState.customers.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),

                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: customersState.customers.length,
                    itemBuilder: (context, index) {
                      final customer = customersState.customers[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          onTap: _canSeeGlobalTransactions(
                            (ref.read(userStateProvider).role),
                          )
                              ? () => _showCustomerTransactions(
                                    context,
                                    ref,
                                    customer,
                                  )
                              : null,
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue,
                            child: Text(
                              customer['name']?.substring(0, 1).toUpperCase() ??
                                  '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(customer['name'] ?? 'N/A'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Telepon: ${customer['phone'] ?? 'N/A'}'),
                              Text('Email: ${customer['email'] ?? 'N/A'}'),
                              Text('Alamat: ${customer['address'] ?? 'N/A'}'),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) => _handleCustomerAction(
                              context,
                              customer,
                              action,
                              ref,
                            ),
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Hapus'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final nameController = TextEditingController();
          final emailController = TextEditingController();
          final phoneController = TextEditingController();
          final addressController = TextEditingController();

          showDialog(
            context: context,
            builder: (context) {
              final formKey = GlobalKey<FormState>();
              return AlertDialog(
                title: const Text('Tambah Pelanggan'),
                content: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(labelText: 'Nama'),
                          validator: _validateName,
                        ),
                        TextFormField(
                          controller: emailController,
                          decoration: const InputDecoration(labelText: 'Email'),
                          validator: _validateEmail,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        TextFormField(
                          controller: phoneController,
                          decoration: const InputDecoration(
                            labelText: 'Nomor Telepon',
                          ),
                          validator: _validatePhone,
                          keyboardType: TextInputType.phone,
                        ),
                        TextFormField(
                          controller: addressController,
                          decoration: const InputDecoration(
                            labelText: 'Alamat',
                          ),
                          validator: _validateAddress,
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Batal'),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (formKey.currentState?.validate() ?? false) {
                        await customersNotifier.addCustomer(
                          nameController.text.trim(),
                          emailController.text.trim(),
                          phoneController.text.trim(),
                          addressController.text.trim(),
                        );
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      }
                    },
                    child: const Text('Tambah'),
                  ),
                ],
              );
            },
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
