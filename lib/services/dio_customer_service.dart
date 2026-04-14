import 'package:dio/dio.dart';

class DioCustomerService {
  final Dio _dio;

  DioCustomerService(String baseUrl)
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ));

  Future<Map<String, dynamic>?> addCustomer(String name, String phone, String address) async {
    try {
      final response = await _dio.post(
        '/api/customers',
        data: {'name': name, 'phone': phone, 'address': address},
      );
      return response.statusCode == 201 ? response.data['data'] : null;
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Failed to add customer');
    }
  }

  Future<List<Map<String, dynamic>>> loadCustomers() async {
    try {
      final response = await _dio.get('/api/customers');
      return List<Map<String, dynamic>>.from(response.data);
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Failed to load customers');
    }
  }

  Future<List<Map<String, dynamic>>> loadCustomersWithPagination(int page, int limit) async {
    try {
      final response = await _dio.get('/api/customers', queryParameters: {
        'page': page,
        'limit': limit,
      });
      return List<Map<String, dynamic>>.from(response.data);
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Failed to load customers with pagination');
    }
  }
}
