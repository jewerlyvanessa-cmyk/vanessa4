import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vanessa3/utils/network_config.dart';

abstract final class FakturPageUtils {
  FakturPageUtils._();

  static String normalizeOrderType(dynamic raw) {
    return (raw ?? '').toString().trim().toLowerCase();
  }

  static String orderTypeDisplayLabel(dynamic raw) {
    final type = normalizeOrderType(raw);
    switch (type) {
      case 'jual':
        return 'Jual';
      case 'buyback':
        return 'Buyback';
      case 'service':
        return 'Service';
      case 'custom':
        return 'Custom';
      case 'ambil':
      case 'pickup':
      case 'picked_up':
        return 'Ambil';
      default:
        if (type.isEmpty) return '-';
        return type
            .split(RegExp(r'[_\s-]+'))
            .where((e) => e.isNotEmpty)
            .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
    }
  }

  static String fakturHeading(dynamic raw) {
    final type = normalizeOrderType(raw);
    switch (type) {
      case 'jual':
        return 'FAKTUR PENJUALAN';
      case 'buyback':
        return 'FAKTUR BUYBACK';
      case 'service':
        return 'FAKTUR SERVIS';
      case 'custom':
        return 'FAKTUR CUSTOM';
      case 'ambil':
      case 'pickup':
      case 'picked_up':
        return 'FAKTUR PENGAMBILAN';
      default:
        if (type.isEmpty) return 'FAKTUR ORDER';
        return 'FAKTUR ${orderTypeDisplayLabel(type).toUpperCase()}';
    }
  }

  static String branchTitleFromOrderData(Map<String, dynamic> orderData) {
    final raw = orderData['branch_name'] ??
        orderData['nama_cabang'] ??
        orderData['branchName'] ??
        orderData['branch_name_text'];
    final s = raw?.toString().trim();
    if (s != null && s.isNotEmpty) return s;
    return '';
  }

  static String branchIdFromOrderData(Map<String, dynamic> orderData) {
    final raw =
        orderData['branch_id'] ?? orderData['branchId'] ?? orderData['branch'];
    return raw?.toString().trim() ?? '';
  }

  static Future<String> resolveBranchTitle(Map<String, dynamic> orderData) async {
    final fromData = branchTitleFromOrderData(orderData);
    if (fromData.isNotEmpty) return fromData;

    final branchId = branchIdFromOrderData(orderData);
    if (branchId.isEmpty) return 'VANESSA GOLD & DIAMOND';

    try {
      final url = '${NetworkConfig.baseUrl}/branches/$branchId';
      final resp = await http
          .get(Uri.parse(url), headers: NetworkConfig.defaultHeaders)
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return 'VANESSA GOLD & DIAMOND';
      final body = resp.body.trim();
      if (body.isEmpty) return 'VANESSA GOLD & DIAMOND';
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['name'] != null) {
        final name = decoded['name'].toString().trim();
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}

    return 'VANESSA GOLD & DIAMOND';
  }

  static String fmtMoney(dynamic v) {
    final n = double.tryParse(v?.toString() ?? '');
    if (n == null) return v?.toString() ?? '0';
    return n
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
  }

  static double totalOrderRounded(Map<String, dynamic> od) {
    final rawJumlah = od['jumlah'];
    final rawTotal = od['total'];
    final j = double.tryParse(rawJumlah?.toString() ?? '');
    if (j != null) return (j / 5000).ceil() * 5000;
    final t = double.tryParse(rawTotal?.toString() ?? '') ?? 0;
    return (t / 5000).ceil() * 5000;
  }

  static String? photoUrl(dynamic raw) {
    final s = raw?.toString().trim();
    if (s == null || s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    if (s.startsWith('/')) return '${NetworkConfig.baseUrl}$s';
    return '${NetworkConfig.baseUrl}/uploads/$s';
  }
}
