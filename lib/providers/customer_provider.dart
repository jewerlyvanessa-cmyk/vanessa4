import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/services/dio_customer_service.dart';
import 'package:vanessa3/utils/cache_manager.dart';
import 'package:vanessa3/utils/logger.dart';

class CustomerState {
  final List<Map<String, dynamic>> customers;
  final String? selectedCustomerId;

  CustomerState({
    this.customers = const [],
    this.selectedCustomerId,
  });

  CustomerState copyWith({
    List<Map<String, dynamic>>? customers,
    String? selectedCustomerId,
  }) {
    return CustomerState(
      customers: customers ?? this.customers,
      selectedCustomerId: selectedCustomerId ?? this.selectedCustomerId,
    );
  }
}

class CustomerNotifier extends StateNotifier<CustomerState> {
  final DioCustomerService _customerService;
  final CacheManager _cacheManager = CacheManager();

  CustomerNotifier(String baseUrl)
      : _customerService = DioCustomerService(baseUrl),
        super(CustomerState());

  Future<void> loadCustomers() async {
    Logger.logInfo('Loading customers...');
    if (_cacheManager.contains('customers')) {
      Logger.logInfo('Loading customers from cache.');
      state = state.copyWith(
        customers: List<Map<String, dynamic>>.from(_cacheManager.get('customers')),
      );
      return;
    }

    try {
      final customers = await _customerService.loadCustomers();
      _cacheManager.set('customers', customers);
      state = state.copyWith(customers: customers);
      Logger.logInfo('Customers loaded successfully.');
    } catch (e, stackTrace) {
      Logger.logError('Failed to load customers.', e, stackTrace);
      rethrow;
    }
  }

  Future<void> addCustomer(String name, String phone, String address) async {
    Logger.logInfo('Adding customer: $name');
    try {
      final newCustomer = await _customerService.addCustomer(name, phone, address);
      if (newCustomer != null) {
        final updatedCustomers = [...state.customers, newCustomer];
        _cacheManager.set('customers', updatedCustomers);
        state = state.copyWith(
          customers: updatedCustomers,
          selectedCustomerId: newCustomer['customer_id'],
        );
        Logger.logInfo('Customer added successfully: $name');
      }
    } catch (e, stackTrace) {
      Logger.logError('Failed to add customer: $name', e, stackTrace);
      rethrow;
    }
  }

  void selectCustomer(String customerId) {
    state = state.copyWith(selectedCustomerId: customerId);
  }

  Future<List<Map<String, dynamic>>> loadCustomersWithPagination(int page, int limit) async {
    Logger.logInfo('Loading customers for page $page with limit $limit');
    try {
      return await _customerService.loadCustomersWithPagination(page, limit);
    } catch (e, stackTrace) {
      Logger.logError('Failed to load customers with pagination', e, stackTrace);
      rethrow;
    }
  }
}
