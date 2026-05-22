import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vanessa3/utils/faktur/faktur_constants.dart';
import 'package:vanessa3/utils/faktur/faktur_metadata.dart';
import 'package:vanessa3/utils/network_config.dart';

const String kFakturPaymentSummaryKey = '_faktur_payment_summary';
const String kFakturBranchesKey = '_faktur_branches';
const String kFakturItemConditionsKey = '_faktur_item_conditions';
const String kFakturContextLoadedKey = '_faktur_context_loaded';

/// Ringkasan pembayaran untuk faktur ambil.
Future<Map<String, double>?> fetchPaymentSummaryForPickupFaktur(
  String orderId,
) async {
  final id = orderId.trim();
  if (id.isEmpty) return null;
  try {
    final uri = Uri.parse(
      '${NetworkConfig.baseUrl}/orders/payment-summary?order_id=${Uri.encodeQueryComponent(id)}',
    );
    final resp = await http
        .get(uri, headers: NetworkConfig.defaultHeaders)
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) return null;
    return _paymentSummaryFromJson(decoded);
  } catch (_) {
    return null;
  }
}

Map<String, double>? _paymentSummaryFromJson(Map decoded) {
  final m = Map<String, dynamic>.from(decoded);
  double p(String k) => double.tryParse(m[k]?.toString() ?? '') ?? 0;
  return {
    'total': p('total'),
    'paid': p('paid_amount'),
    'remaining': p('remaining_amount'),
    'dp': p('dp_amount'),
  };
}

/// Satu round-trip: payment summary + logo cabang + item conditions.
Future<bool> enrichOrderDataForFakturPrint(
  Map<String, dynamic> orderData, {
  FakturPrintKind kind = FakturPrintKind.orderTransaction,
}) async {
  final oid = orderData['order_id']?.toString().trim() ?? '';
  if (oid.isEmpty) return false;
  if (orderData[kFakturContextLoadedKey] == true) return true;

  final pickupBranchId = () {
    if (kind != FakturPrintKind.pickup) return '';
    for (final key in ['pickup_branch_id', 'pickupBranchId']) {
      final s = orderData[key]?.toString().trim() ?? '';
      if (s.isNotEmpty) return s;
    }
    final meta = fakturMetadataMap(orderData);
    return meta['pickup_branch_id']?.toString().trim() ?? '';
  }();

  try {
    final qp = <String, String>{'order_id': oid};
    if (pickupBranchId.isNotEmpty) {
      qp['pickup_branch_id'] = pickupBranchId;
    }
    final uri = Uri.parse('${NetworkConfig.baseUrl}/orders/faktur-context')
        .replace(queryParameters: qp);
    final resp = await http
        .get(uri, headers: NetworkConfig.defaultHeaders)
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return false;
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) return false;
    final root = Map<String, dynamic>.from(decoded);

    final ps = root['payment_summary'];
    if (ps is Map) {
      final snap = _paymentSummaryFromJson(ps);
      if (snap != null) {
        orderData[kFakturPaymentSummaryKey] = snap;
      }
    }

    final branches = root['branches'];
    if (branches is List) {
      orderData[kFakturBranchesKey] = branches;
      _mergeBranchLogosIntoOrder(orderData, branches);
    }

    final conds = root['item_conditions'];
    if (conds is List) {
      orderData[kFakturItemConditionsKey] = conds;
    }

    orderData[kFakturContextLoadedKey] = true;
    return true;
  } catch (_) {
    return false;
  }
}

void _mergeBranchLogosIntoOrder(
  Map<String, dynamic> orderData,
  List<dynamic> branches,
) {
  String? logoForId(String id) {
    for (final raw in branches) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      if (m['branch_id']?.toString() == id) {
        final url = m['logo_url']?.toString().trim() ?? '';
        if (url.isNotEmpty) return url;
      }
    }
    return null;
  }

  final orderBranchId = orderData['branch_id']?.toString().trim() ?? '';
  if (orderBranchId.isNotEmpty) {
    final url = logoForId(orderBranchId);
    if (url != null) {
      orderData['logo_url'] ??= url;
      orderData['branch_logo_url'] ??= url;
    }
  }

  final pickupId = orderData['pickup_branch_id']?.toString().trim() ?? '';
  if (pickupId.isNotEmpty) {
    final url = logoForId(pickupId);
    if (url != null) {
      orderData['pickup_branch_logo_url'] = url;
    }
  }
}

Map<String, double>? fakturPaymentSummaryFromOrderData(
  Map<String, dynamic> orderData,
) {
  final raw = orderData[kFakturPaymentSummaryKey];
  if (raw is! Map) return null;
  return Map<String, double>.from(
    raw.map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
  );
}

/// DP untuk service/custom dari server atau payload.
Future<double> resolveFakturDpAmount(Map<String, dynamic> orderData) async {
  final type = (orderData['order_type'] ?? '').toString().trim().toLowerCase();
  if (type != 'service' && type != 'custom') return 0;

  final snap = fakturPaymentSummaryFromOrderData(orderData);
  if (snap != null && (snap['dp'] ?? 0) > 0) {
    return snap['dp']!;
  }

  double fromPayload() => fakturDpFromPayloadSync(orderData);

  try {
    final oid = orderData['order_id']?.toString().trim();
    if (oid != null && oid.isNotEmpty) {
      final uri = Uri.parse('${NetworkConfig.baseUrl}/payments').replace(
        queryParameters: {'order_id': oid, 'limit': '50'},
      );
      final resp = await http
          .get(uri, headers: NetworkConfig.defaultHeaders)
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is List) {
          double sum = 0;
          for (final raw in decoded) {
            if (raw is! Map) continue;
            final m = Map<String, dynamic>.from(raw);
            final st = (m['status'] ?? '').toString().toLowerCase();
            if (st == 'cancelled' || st == 'failed') continue;
            final kind = (m['payment_kind'] ?? '').toString().toLowerCase();
            final notes = (m['notes'] ?? '').toString().toLowerCase();
            final isDp = kind == 'dp' ||
                notes.contains('uang muka') ||
                notes.contains('muka (service)') ||
                notes.contains('muka (custom)');
            if (!isDp) continue;
            final amt = double.tryParse(m['amount']?.toString() ?? '') ?? 0;
            if (amt > 0) sum += amt;
          }
          if (sum > 0) return sum;
        }
      }
    }
  } catch (_) {}

  return fromPayload();
}

/// Siapkan data order untuk faktur ambil (tanpa membuka dialog cetak).
Future<Map<String, dynamic>> preparePickupFakturOrderData(
  Map<String, dynamic> orderData,
) async {
  final data = Map<String, dynamic>.from(orderData);
  data['pickup_faktur_date'] = DateTime.now().toUtc().toIso8601String();
  await enrichOrderDataForFakturPrint(data, kind: FakturPrintKind.pickup);
  final snap = fakturPaymentSummaryFromOrderData(data) ??
      await fetchPaymentSummaryForPickupFaktur(
        data['order_id']?.toString() ?? '',
      );
  if (snap != null) {
    data['paid_amount'] = snap['paid'];
    data['remaining_amount'] = snap['remaining'];
  }
  return data;
}
