import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/core/network/api_exceptions.dart';
import 'dart:convert';
import 'dart:math' as math;
import '../../../utils/logger.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

final customersProvider =
    StateNotifierProvider<CustomersNotifier, CustomersState>(
      (ref) => CustomersNotifier(),
    );

class CustomersState {
  final List<Map<String, dynamic>> customers;
  final bool isLoading;
  final String? error;
  /// Cabang terakhir yang dipakai saat `fetchCustomers(branchId: …)` (untuk refresh CRUD).
  final String? filterBranchId;
  /// Sudah pernah selesai fetch minimal sekali (cegah loop saat daftar kosong).
  final bool hasLoaded;

  const CustomersState({
    required this.customers,
    this.isLoading = false,
    this.error,
    this.filterBranchId,
    this.hasLoaded = false,
  });

  CustomersState copyWith({
    List<Map<String, dynamic>>? customers,
    bool? isLoading,
    String? error,
    String? filterBranchId,
    bool clearFilterBranchId = false,
    bool? hasLoaded,
    bool clearError = false,
  }) {
    return CustomersState(
      customers: customers ?? this.customers,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      filterBranchId: clearFilterBranchId
          ? null
          : (filterBranchId ?? this.filterBranchId),
      hasLoaded: hasLoaded ?? this.hasLoaded,
    );
  }
}

class CustomersNotifier extends StateNotifier<CustomersState> {
  CustomersNotifier() : super(const CustomersState(customers: []));

  Future<void> fetchCustomers({String? branchId, bool silent = false}) async {
    final branchChanged =
        branchId != null &&
        branchId.toString().trim().isNotEmpty &&
        branchId.toString() != (state.filterBranchId ?? '');
    final showFullScreenLoading =
        !silent && (!state.hasLoaded || branchChanged);

    state = state.copyWith(
      isLoading: showFullScreenLoading,
      clearError: true,
      filterBranchId: branchId,
      clearFilterBranchId: branchId == null,
      hasLoaded: branchChanged ? false : state.hasLoaded,
    );

    final query = branchId != null && branchId.toString().trim().isNotEmpty
        ? {'branch_id': branchId.toString()}
        : null;
    Logger.logInfo('DEBUG: Fetching customers from /api/customers');
    try {
      final response = await ApiClient.get('/api/customers', query: query);
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
            hasLoaded: true,
          );
          Logger.logInfo(
            'DEBUG: Successfully loaded ${responseData.length} customers',
          );
        } else {
          state = state.copyWith(
            isLoading: false,
            hasLoaded: true,
            error: 'Format data pelanggan tidak valid',
          );
          Logger.logInfo('DEBUG: Invalid data format');
        }
      } else {
        state = state.copyWith(
          isLoading: false,
          hasLoaded: true,
          error: 'Failed to load customers: ${response.statusCode}',
        );
        Logger.logInfo(
          'DEBUG: Failed to load customers: ${response.statusCode}',
        );
      }
    } catch (error) {
      if (error is UnauthorizedException || error is ForbiddenException) {
        state = state.copyWith(
          isLoading: false,
          hasLoaded: true,
          error: error.toString(),
        );
        return;
      }
      Logger.logInfo('DEBUG: Error fetching customers: $error');
      state = state.copyWith(
        customers: [],
        isLoading: false,
        hasLoaded: true,
        error: 'Network error occurred: $error',
      );
    }
  }

  Future<bool> addCustomer({
    required String name,
    String? phone,
    String? email,
    String? address,
    String? branchId,
  }) async {
    try {
      final phoneTrim = phone?.trim() ?? '';
      final body = <String, dynamic>{
        'name': name.trim(),
        'phone': phoneTrim.isEmpty ? null : phoneTrim,
        'address': (address == null || address.trim().isEmpty)
            ? null
            : address.trim(),
      };
      final emailTrim = email?.trim();
      if (emailTrim != null && emailTrim.isNotEmpty) {
        body['email'] = emailTrim;
      }
      final branch = branchId?.trim();
      if (branch != null && branch.isNotEmpty) {
        body['branch_id'] = branch;
      }

      final response = await ApiClient.post(
        '/api/customers',
        body: json.encode(body),
      );
      if (response.statusCode == 201) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          await fetchCustomers(branchId: state.filterBranchId, silent: true);
          return true;
        }
        state = state.copyWith(
          error: responseData['message']?.toString() ?? 'Gagal menambah pelanggan',
        );
        return false;
      }
      Map<String, dynamic>? responseData;
      try {
        responseData = json.decode(response.body) as Map<String, dynamic>?;
      } catch (_) {}
      state = state.copyWith(
        error:
            responseData?['message']?.toString() ??
            'Gagal menambah pelanggan (${response.statusCode})',
      );
      return false;
    } catch (error) {
      state = state.copyWith(error: 'Kesalahan jaringan: $error');
      return false;
    }
  }

  Future<bool> editCustomer(
    String id,
    String name,
    String email,
    String phone,
    String address,
  ) async {
    try {
      final response = await ApiClient.patch(
        '/api/customers/$id',
        body: json.encode({
          'name': name,
          'email': email.trim().isEmpty ? null : email.trim(),
          'phone': phone.trim().isEmpty ? null : phone.trim(),
          'address': address.trim().isEmpty ? null : address.trim(),
        }),
      );
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          await fetchCustomers(branchId: state.filterBranchId, silent: true);
          return true;
        } else {
          state = state.copyWith(
            error: responseData['message'] ?? 'Failed to update customer',
          );
          return false;
        }
      } else {
        final responseData = json.decode(response.body);
        state = state.copyWith(
          error: responseData['message'] ?? 'Failed to update customer',
        );
        return false;
      }
    } catch (error) {
      state = state.copyWith(error: 'Network error occurred');
      return false;
    }
  }

  Future<void> deleteCustomer(String id) async {
    try {
      final response = await ApiClient.delete('/api/customers/$id');
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          await fetchCustomers(branchId: state.filterBranchId, silent: true);
        } else {
          state = state.copyWith(
            error: responseData['message'] ?? 'Failed to delete customer',
          );
        }
      } else {
        final responseData = json.decode(response.body);
        state = state.copyWith(
          error: responseData['message'] ?? 'Failed to delete customer',
        );
      }
    } catch (error) {
      state = state.copyWith(error: 'Network error occurred');
    }
  }
}

class CustomersPage extends ConsumerWidget {
  const CustomersPage({super.key});

  bool _canSeeGlobalTransactions(String roleRaw) {
    final role = roleRaw.trim().toLowerCase();
    return role == 'manajer' ||
        role == 'admin_toko' ||
        role == 'superadmin';
  }

  bool _canEditCustomer(String roleRaw) {
    final r = roleRaw.trim().toLowerCase();
    return r == 'cs' ||
        r == 'kasir' ||
        r == 'admin_toko' ||
        r == 'manajer' ||
        r == 'superadmin';
  }

  /// Hapus pelanggan: peran manajemen cabang / superadmin.
  bool _canDeleteCustomer(String roleRaw) {
    final r = roleRaw.trim().toLowerCase();
    return r == 'admin_toko' || r == 'manajer' || r == 'superadmin';
  }

  String _cellStr(dynamic v) {
    final s = v?.toString().trim();
    if (s == null || s.isEmpty) return '—';
    return s;
  }

  TextStyle _mobileRowTextStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium;
    return (base ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
  }

  TextStyle _desktopRowTextStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium;
    return (base ?? const TextStyle()).copyWith(height: 1.25);
  }

  List<PopupMenuEntry<String>> _customerMenuEntries(
    BuildContext context,
    String role,
  ) {
    final items = <PopupMenuEntry<String>>[];
    if (_canSeeGlobalTransactions(role)) {
      items.add(
        const PopupMenuItem(
          value: 'transactions',
          child: Text('Riwayat transaksi'),
        ),
      );
    }
    if (_canEditCustomer(role)) {
      items.add(const PopupMenuItem(value: 'edit', child: Text('Edit')));
    }
    if (_canDeleteCustomer(role)) {
      if (items.isNotEmpty) {
        items.add(const PopupMenuDivider());
      }
      items.add(
        PopupMenuItem(
          value: 'delete',
          child: Text(
            'Hapus',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    return items;
  }

  Widget _summaryMetricCard(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required String label,
    required String value,
    bool compact = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final iconSize = compact ? 20.0 : 24.0;
    final iconInset = compact ? 8.0 : 10.0;
    final gap = compact ? 8.0 : 12.0;
    final radius = compact ? 14.0 : 16.0;
    final iconBoxRadius = compact ? 10.0 : 12.0;

    return Material(
      elevation: 0,
      color: cs.surfaceContainerLow.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(radius),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 10 : 12,
        ),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  accent.withValues(alpha: 0.22),
                  cs.surfaceContainerHigh,
                ),
                borderRadius: BorderRadius.circular(iconBoxRadius),
              ),
              child: Padding(
                padding: EdgeInsets.all(iconInset),
                child: Icon(icon, size: iconSize, color: accent),
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          fontSize: compact ? 11 : null,
                          height: 1.15,
                        ),
                  ),
                  SizedBox(height: compact ? 2 : 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: compact
                          ? Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.35,
                              )
                          : Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchCustomerTransactions({
    required String customerId,
    String? branchId,
  }) async {
    final query = (branchId == null || branchId.toString().trim().isEmpty)
        ? null
        : {'branch_id': branchId.toString()};

    final response = await ApiClient.get(
      '/api/customers/$customerId/transactions',
      query: query,
    );
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

  num _sumTransactionAmounts(List<Map<String, dynamic>> rows) {
    return rows.fold<num>(0, (sum, r) {
      final v = r['jumlah'] ?? r['total'];
      if (v == null) return sum;
      if (v is num) return sum + v;
      return sum + (num.tryParse(v.toString()) ?? 0);
    });
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
          content: Text(
            'Riwayat transaksi hanya untuk Superadmin, Manajer & Admin Toko',
          ),
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
                        final totalNilai = _sumTransactionAmounts(rows);
                        final cs = Theme.of(context).colorScheme;
                        final tt = Theme.of(context).textTheme;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total nilai transaksi: Rp ${_fmtRp(totalNilai)}',
                              style: tt.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: cs.primary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: rows.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'Belum ada transaksi untuk pelanggan ini',
                                      ),
                                    )
                                  : LayoutBuilder(
                                      builder: (context, c) {
                                        final minW =
                                            math.max(c.maxWidth, 400.0);
                                        final dataRows = <DataRow>[];
                                        for (var i = 0;
                                            i < rows.length;
                                            i++) {
                                          final r = rows[i];
                                          final orderType = (r['order_type'] ??
                                                  '')
                                              .toString()
                                              .trim();
                                          final jenis = orderType.isEmpty
                                              ? '—'
                                              : orderType;
                                          final amount =
                                              r['jumlah'] ?? r['total'] ?? 0;

                                          dataRows.add(
                                            DataRow(
                                              color:
                                                  WidgetStateProperty.resolveWith(
                                                      (s) {
                                                if (s.contains(
                                                  WidgetState.hovered,
                                                )) {
                                                  return cs.primary
                                                      .withValues(alpha: 0.06);
                                                }
                                                return i.isOdd
                                                    ? cs.surfaceContainerHighest
                                                        .withValues(
                                                        alpha: 0.45,
                                                      )
                                                    : null;
                                              }),
                                              cells: [
                                                DataCell(
                                                  Text(
                                                    _fmtDateTime(
                                                      r['created_at'],
                                                    ),
                                                    style: tt.bodyMedium,
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    jenis,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: tt.bodyMedium,
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    'Rp ${_fmtRp(amount)}',
                                                    style: tt.titleSmall
                                                        ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: cs.primary,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }
                                        return Material(
                                          elevation: 0,
                                          color: cs.surfaceContainerLow
                                              .withValues(alpha: 0.65),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            side: BorderSide(
                                              color: cs.outlineVariant
                                                  .withValues(alpha: 0.45),
                                            ),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: Scrollbar(
                                            child: SingleChildScrollView(
                                              scrollDirection:
                                                  Axis.horizontal,
                                              child: ConstrainedBox(
                                                constraints: BoxConstraints(
                                                  minWidth: minW,
                                                ),
                                                child: SingleChildScrollView(
                                                  child: DataTable(
                                                    headingRowColor:
                                                        WidgetStateProperty.all(
                                                      cs.surfaceContainerHigh,
                                                    ),
                                                    dataRowMinHeight: 40,
                                                    dataRowMaxHeight: 56,
                                                    columnSpacing: 12,
                                                    horizontalMargin: 10,
                                                    showCheckboxColumn: false,
                                                    dividerThickness: 0.5,
                                                    columns: [
                                                      DataColumn(
                                                        label:
                                                            dataTableColumnLabel(
                                                          'Tanggal',
                                                        ),
                                                      ),
                                                      DataColumn(
                                                        label:
                                                            dataTableColumnLabel(
                                                          'Jenis',
                                                        ),
                                                      ),
                                                      DataColumn(
                                                        label:
                                                            dataTableColumnLabel(
                                                          'Total',
                                                          numeric: true,
                                                        ),
                                                      ),
                                                    ],
                                                    rows: dataRows,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
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
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final emailRegex = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,}$');
    if (!emailRegex.hasMatch(trimmed)) {
      return 'Format email tidak valid';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final phoneRegex = RegExp(r'^[\+]?[0-9]{10,15}$');
    if (!phoneRegex.hasMatch(trimmed)) {
      return 'Nomor telepon tidak valid (10-15 digit)';
    }
    return null;
  }

  String? _validateAddress(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length < 5) {
      return 'Alamat minimal 5 karakter jika diisi';
    }
    return null;
  }

  void _handleCustomerAction(
    BuildContext context,
    Map<String, dynamic> customer,
    String action,
    WidgetRef ref,
  ) {
    switch (action) {
      case 'transactions':
        _showCustomerTransactions(context, ref, customer);
        break;
      case 'edit':
        _showEditCustomerDialog(context, customer, ref);
        break;
      case 'delete':
        _showDeleteConfirmation(context, customer, ref);
        break;
    }
  }

  Widget _buildCustomersDataTable(
    BuildContext context,
    WidgetRef ref,
    CustomersState customersState,
    String role,
  ) {
    final cs = Theme.of(context).colorScheme;
    final withEmail = customersState.customers
        .where(
          (c) =>
              c['email'] != null && c['email'].toString().trim().isNotEmpty,
        )
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 600;
        /// Lebar konten tabel desktop (tidak dipaksa melebar mengikuti layar penuh).
        const desktopTableWidth = 840.0;
        final panelW = constraints.maxWidth;
        final BoxConstraints tableBoxConstraints;
        if (narrow) {
          tableBoxConstraints = BoxConstraints.tightFor(width: panelW);
        } else if (panelW >= desktopTableWidth) {
          tableBoxConstraints =
              BoxConstraints.tightFor(width: desktopTableWidth);
        } else {
          // Layar desktop sempit: geser horizontal, lebar konten tetap.
          tableBoxConstraints =
              const BoxConstraints(minWidth: desktopTableWidth);
        }
        final mobileStyle = _mobileRowTextStyle(context);
        final desktopStyle = _desktopRowTextStyle(context);

        final columns = narrow
            ? <DataColumn>[
                DataColumn(label: dataTableColumnLabel('Nama')),
                DataColumn(label: dataTableColumnLabel('Alamat')),
                DataColumn(label: dataTableColumnLabel('Telepon')),
                const DataColumn(label: SizedBox(width: 44)),
              ]
            : <DataColumn>[
                DataColumn(label: dataTableColumnLabel('Nama')),
                DataColumn(label: dataTableColumnLabel('Email')),
                DataColumn(label: dataTableColumnLabel('Telepon')),
                DataColumn(label: dataTableColumnLabel('Alamat')),
                const DataColumn(label: SizedBox(width: 48)),
              ];

        final menuEntries = _customerMenuEntries(context, role);
        final rows = <DataRow>[];
        for (var i = 0; i < customersState.customers.length; i++) {
          final customer = customersState.customers[i];
          final name = _cellStr(customer['name']);
          final email = _cellStr(customer['email']);
          final phone = _cellStr(customer['phone']);
          final address = _cellStr(customer['address']);

          final actionCell = menuEntries.isEmpty
              ? DataCell(
                  Text(
                    '—',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                )
              : DataCell(
                  Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<String>(
                      tooltip: 'Tindakan',
                      icon: const Icon(Icons.more_vert),
                      onSelected: (action) => _handleCustomerAction(
                        context,
                        customer,
                        action,
                        ref,
                      ),
                      itemBuilder: (context) => menuEntries,
                    ),
                  ),
                );

          final cells = narrow
              ? <DataCell>[
                  DataCell(
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mobileStyle.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataCell(
                    Text(
                      address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: mobileStyle,
                    ),
                  ),
                  DataCell(
                    Text(
                      phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mobileStyle,
                    ),
                  ),
                  actionCell,
                ]
              : <DataCell>[
                  DataCell(
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: desktopStyle.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataCell(
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: desktopStyle.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: desktopStyle,
                    ),
                  ),
                  DataCell(
                    Text(
                      address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: desktopStyle.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.2,
                      ),
                    ),
                  ),
                  actionCell,
                ];

          rows.add(
            DataRow(
              color: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.hovered)) {
                  return cs.primary.withValues(alpha: 0.06);
                }
                return i.isOdd
                    ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
                    : null;
              }),
              cells: cells,
            ),
          );
        }

        final pad = narrow ? 12.0 : 16.0;
        final cardGap = narrow ? 8.0 : 12.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _summaryMetricCard(
                        context,
                        compact: narrow,
                        icon: Icons.people_rounded,
                        accent: cs.primary,
                        label: 'Total pelanggan',
                        value: '${customersState.customers.length}',
                      ),
                    ),
                    SizedBox(width: cardGap),
                    Expanded(
                      child: _summaryMetricCard(
                        context,
                        compact: narrow,
                        icon: Icons.mark_email_read_rounded,
                        accent: Colors.green.shade700,
                        label: 'Dengan email',
                        value: '$withEmail',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 8),
              child: Text(
                'Daftar pelanggan (${customersState.customers.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, 4),
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
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: ConstrainedBox(
                            constraints: tableBoxConstraints,
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(
                                cs.surfaceContainerHigh,
                              ),
dataRowMinHeight: narrow ? 40 : 44,
                              dataRowMaxHeight: narrow ? 62 : 60,
                              columnSpacing: narrow ? 8 : 12,
                              horizontalMargin: narrow ? 8 : 10,
                              showCheckboxColumn: false,
                              dividerThickness: 0.5,
                              columns: columns,
                              rows: rows,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAddCustomerDialog(BuildContext pageContext, WidgetRef ref) {
    final customersNotifier = ref.read(customersProvider.notifier);
    final branchId = ref.read(userStateProvider).branch;
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();

    showDialog<void>(
      context: pageContext,
      builder: (dialogContext) {
        final formKey = GlobalKey<FormState>();
        var saving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                        decoration: const InputDecoration(
                          labelText: 'Nama *',
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: _validateName,
                        enabled: !saving,
                      ),
                      TextFormField(
                        controller: phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Nomor Telepon (opsional)',
                        ),
                        validator: _validatePhone,
                        keyboardType: TextInputType.phone,
                        enabled: !saving,
                      ),
                      TextFormField(
                        controller: emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email (opsional)',
                        ),
                        validator: _validateEmail,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !saving,
                      ),
                      TextFormField(
                        controller: addressController,
                        decoration: const InputDecoration(
                          labelText: 'Alamat (opsional)',
                        ),
                        validator: _validateAddress,
                        maxLines: 3,
                        enabled: !saving,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }
                          setDialogState(() => saving = true);
                          final ok = await customersNotifier.addCustomer(
                            name: nameController.text,
                            phone: phoneController.text,
                            email: emailController.text,
                            address: addressController.text,
                            branchId: branchId,
                          );
                          if (!dialogContext.mounted) return;
                          if (ok) {
                            Navigator.of(dialogContext).pop();
                            if (!pageContext.mounted) return;
                            ScaffoldMessenger.of(pageContext).showSnackBar(
                              const SnackBar(
                                content: Text('Pelanggan berhasil ditambahkan'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else {
                            setDialogState(() => saving = false);
                            final err = ref.read(customersProvider).error;
                            ScaffoldMessenger.of(pageContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  err ?? 'Gagal menambah pelanggan',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
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
                    decoration: const InputDecoration(
                      labelText: 'Email (opsional)',
                    ),
                    validator: _validateEmail,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  TextFormField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Nomor Telepon (opsional)',
                    ),
                    validator: _validatePhone,
                    keyboardType: TextInputType.phone,
                  ),
                  TextFormField(
                    controller: addressController,
                    decoration: const InputDecoration(
                      labelText: 'Alamat (opsional)',
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
        if (update['type'] == 'customer_update') {
          customersNotifier.fetchCustomers(
            branchId: userState.branch,
            silent: true,
          );
        }
      });
    });

    // Muat awal sekali; jangan ulang hanya karena daftar kosong (menyebabkan kedip).
    if (!customersState.hasLoaded && !customersState.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!ref.read(customersProvider).hasLoaded) {
          customersNotifier.fetchCustomers(branchId: userState.branch);
        }
      });
    }

    if (customersState.isLoading && !customersState.hasLoaded) {
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
                onPressed: () => customersNotifier.fetchCustomers(
                  branchId: userState.branch,
                ),
                child: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }

    final canAdd = _canEditCustomer(userState.role);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pelanggan'),
        actions: [
          if (canAdd)
            IconButton(
              icon: const Icon(Icons.person_add_outlined),
              tooltip: 'Tambah pelanggan',
              onPressed: () => _showAddCustomerDialog(context, ref),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: customersState.isLoading
                ? null
                : () => customersNotifier.fetchCustomers(
                      branchId: userState.branch,
                      silent: true,
                    ),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: customersState.customers.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Belum ada data pelanggan',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (canAdd) ...[
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => _showAddCustomerDialog(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Tambah Pelanggan'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _buildCustomersDataTable(
                context,
                ref,
                customersState,
                userState.role,
              ),
            ),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () => _showAddCustomerDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Tambah'),
            )
          : null,
    );
  }
}
