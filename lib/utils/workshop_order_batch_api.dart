import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/utils/network_config.dart';

class WorkshopOrderBatchResult {
  WorkshopOrderBatchResult({
    required this.okIds,
    required this.failed,
  });

  final List<int> okIds;
  final List<({int id, String message})> failed;

  bool get allOk => failed.isEmpty;
  int get okCount => okIds.length;
}

Future<WorkshopOrderBatchResult> putWorkshopOrderStatuses({
  required Iterable<int> orderIds,
  required String status,
  required int branchId,
}) async {
  final okIds = <int>[];
  final failed = <({int id, String message})>[];
  final baseUrl = NetworkConfig.baseUrl;

  for (final id in orderIds) {
    try {
      final resp = await http.put(
        Uri.parse('$baseUrl/workshop-orders/$id/status'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({'status': status, 'branch_id': branchId}),
      );
      if (resp.statusCode == 200) {
        okIds.add(id);
        continue;
      }
      var msg = 'HTTP ${resp.statusCode}';
      try {
        final d = jsonDecode(resp.body);
        if (d is Map) msg = (d['error'] ?? msg).toString();
      } catch (_) {
        if (resp.body.isNotEmpty) msg = resp.body;
      }
      failed.add((id: id, message: msg));
    } catch (e) {
      failed.add((id: id, message: e.toString()));
    }
  }

  return WorkshopOrderBatchResult(okIds: okIds, failed: failed);
}

Future<WorkshopOrderBatchResult> confirmWorkshopStoreReceiptBatch({
  required Iterable<int> orderIds,
  required String branchId,
}) async {
  final okIds = <int>[];
  final failed = <({int id, String message})>[];

  for (final id in orderIds) {
    try {
      await ApiService.confirmWorkshopStoreReceipt(
        orderId: id,
        branchId: branchId,
      );
      okIds.add(id);
    } catch (e) {
      failed.add((id: id, message: e.toString()));
    }
  }

  return WorkshopOrderBatchResult(okIds: okIds, failed: failed);
}
