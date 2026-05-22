import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/core/state/user_state.dart';
import 'package:vanessa3/utils/business_calendar.dart';

/// Hasil muat order + pembayaran harian (satu cabang + tanggal).
class DailyOrdersPaymentsBundle {
  const DailyOrdersPaymentsBundle({
    required this.orders,
    required this.payments,
  });

  final List<dynamic> orders;
  final Map<String, dynamic> payments;
}

/// HTTP untuk halaman Order & Pembayaran Harian — seluruhnya lewat [ApiClient].
class DailyOrdersPaymentsRepository {
  DailyOrdersPaymentsRepository._();

  /// Satu cabang + tanggal — dipakai Order Today (multi-cabang paralel).
  static Future<List<dynamic>> fetchOrdersDailyList({
    required String branchId,
    required String dateYmd,
    String? scopedUserId,
  }) async {
    final query = <String, String>{
      'branch_id': branchId,
      'date': dateYmd,
    };
    if (scopedUserId != null && scopedUserId.isNotEmpty) {
      query['user_id'] = scopedUserId;
    }
    var response = await ApiClient.get('/api/orders/daily', query: query);
    if (response.statusCode == 404) {
      response = await ApiClient.get('/orders/daily', query: query);
    }
    if (response.statusCode != 200) {
      throw DailyOrdersPaymentsLoadException(
        message: 'Gagal memuat order harian (${response.statusCode})',
        ordersStatus: response.statusCode,
        ordersBody: response.body,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw DailyOrdersPaymentsLoadException(
        message:
            'orders/daily: respons bukan array (${decoded.runtimeType})',
        ordersStatus: response.statusCode,
        ordersBody: response.body,
      );
    }
    return decoded;
  }

  static Future<DailyOrdersPaymentsBundle> fetchDaily({
    required UserState user,
    required DateTime selectedDate,
    required bool ordersOnly,
  }) async {
    final dateStr = selectedDate == BusinessCalendar.todayWibDateOnly()
        ? BusinessCalendar.todayYmd()
        : _ymd(selectedDate);

    final ordersQuery = <String, String>{
      'branch_id': user.branch,
      'date': dateStr,
    };
    if (user.role.trim().toLowerCase() == 'cs' && user.userId != null) {
      ordersQuery['user_id'] = user.userId.toString();
    }

    Future<http.Response> fetchOrdersDaily() async {
      var r = await ApiClient.get(
        '/api/orders/daily',
        query: ordersQuery,
      );
      if (r.statusCode == 404) {
        r = await ApiClient.get('/orders/daily', query: ordersQuery);
      }
      return r;
    }

    final payQuery = <String, String>{
      'date': dateStr,
      'branch_id': user.branch,
    };
    if (user.role.trim().toLowerCase() == 'cs' && user.userId != null) {
      payQuery['user_id'] = user.userId.toString();
    }

    http.Response ordersResponse;
    http.Response? paymentsResponse;
    if (ordersOnly) {
      ordersResponse = await fetchOrdersDaily();
    } else {
      final results = await Future.wait<http.Response>([
        fetchOrdersDaily(),
        ApiClient.get('/payments/daily', query: payQuery),
      ]);
      ordersResponse = results[0];
      paymentsResponse = results[1];
    }

    final paymentsOk = ordersOnly || (paymentsResponse?.statusCode == 200);
    if (ordersResponse.statusCode != 200 || !paymentsOk) {
      throw DailyOrdersPaymentsLoadException(
        message: _messageFromResponses(ordersResponse, paymentsResponse),
        ordersStatus: ordersResponse.statusCode,
        paymentsStatus: paymentsResponse?.statusCode,
        ordersBody: ordersResponse.body,
        paymentsBody: paymentsResponse?.body,
      );
    }

    final ordersDecoded = jsonDecode(ordersResponse.body);
    final orders =
        ordersDecoded is List<dynamic> ? ordersDecoded : <dynamic>[];

    final payments = ordersOnly
        ? _emptyPaymentsPayload()
        : Map<String, dynamic>.from(
            jsonDecode(paymentsResponse!.body) as Map,
          );

    return DailyOrdersPaymentsBundle(orders: orders, payments: payments);
  }

  static Future<Map<String, dynamic>> fetchFullOrderForFaktur(
    Map<String, dynamic> order,
  ) async {
    final orderNumber = (order['order_number'] ?? order['nota_order'] ?? '')
        .toString()
        .trim();
    final orderIdStr = (order['order_id'] ?? '').toString().trim();

    Future<Map<String, dynamic>?> tryGet(Map<String, String> query) async {
      final resp = await ApiClient.get('/orders', query: query);
      if (resp.statusCode != 200) return null;
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    }

    if (orderNumber.isNotEmpty) {
      final byNota = await tryGet({'order_number': orderNumber});
      if (byNota != null) return byNota;
    }
    if (orderIdStr.isNotEmpty) {
      final byId = await tryGet({'order_id': orderIdStr});
      if (byId != null) return byId;
    }
    return Map<String, dynamic>.from(order);
  }

  static Future<http.Response> updateWorkshopOrderStatus({
    required int orderId,
    required int branchId,
    required String nextStatus,
  }) {
    return ApiClient.put(
      '/workshop-orders/$orderId/status',
      body: jsonEncode({'branch_id': branchId, 'status': nextStatus}),
    );
  }

  static String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static Map<String, dynamic> _emptyPaymentsPayload() => {
        'summary': {
          'total_amount': 0,
          'total_transactions': 0,
          'payment_methods': <String, dynamic>{},
          'by_method': <Map<String, dynamic>>[],
        },
        'transactions': <dynamic>[],
      };

  static String _messageFromResponses(
    http.Response ordersResponse,
    http.Response? paymentsResponse,
  ) {
    var msg = 'Gagal memuat data harian';
    if (ordersResponse.statusCode == 403 ||
        paymentsResponse?.statusCode == 403) {
      return 'Cabang tidak diizinkan. Ganti cabang lewat menu profil lalu coba lagi.';
    }
    if (ordersResponse.statusCode >= 500 ||
        (paymentsResponse?.statusCode ?? 0) >= 500) {
      msg =
          'Server error (${ordersResponse.statusCode}/${paymentsResponse?.statusCode ?? 0}). Pastikan API production sudah di-deploy ulang.';
      try {
        final errBody = ordersResponse.statusCode >= 500
            ? ordersResponse.body
            : paymentsResponse?.body ?? '';
        final err = jsonDecode(errBody) as Map;
        final d = (err['error'] ?? err['detail'] ?? '').toString().trim();
        if (d.isNotEmpty) return d;
      } catch (_) {}
      return msg;
    }
    if (ordersResponse.statusCode == 400) {
      try {
        final err = jsonDecode(ordersResponse.body) as Map;
        final d = (err['error'] ?? err['detail'] ?? '').toString().trim();
        if (d.isNotEmpty) return d;
      } catch (_) {}
    }
    return msg;
  }
}

class DailyOrdersPaymentsLoadException implements Exception {
  DailyOrdersPaymentsLoadException({
    required this.message,
    this.ordersStatus,
    this.paymentsStatus,
    this.ordersBody,
    this.paymentsBody,
  });

  final String message;
  final int? ordersStatus;
  final int? paymentsStatus;
  final String? ordersBody;
  final String? paymentsBody;

  @override
  String toString() => message;
}
