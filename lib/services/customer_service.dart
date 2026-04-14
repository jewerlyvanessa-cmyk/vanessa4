import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/network_config.dart';

class CustomerService {
  final String baseUrl;

  CustomerService(this.baseUrl);

  Future<Map<String, dynamic>?> addCustomer(String name, String phone, String address) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/customers'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({'name': name, 'phone': phone, 'address': address}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        return jsonDecode(response.body)['data'];
      } else {
        throw Exception('Failed to add customer');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> loadCustomers() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/customers'),
        headers: NetworkConfig.defaultHeaders,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        // API returns data directly as array, not wrapped in data key
        if (responseData is List) {
          return List<Map<String, dynamic>>.from(responseData);
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        throw Exception('Failed to load customers');
      }
    } catch (e) {
      rethrow;
    }
  }
}
