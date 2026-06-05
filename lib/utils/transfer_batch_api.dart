import 'dart:convert';

import 'package:vanessa3/core/network/api_client.dart';

/// Hasil update status beberapa baris transfer (satu dokumen).
class TransferBatchUpdateResult {
  TransferBatchUpdateResult({
    required this.okIds,
    required this.failed,
  });

  final List<int> okIds;
  final List<({int id, String message})> failed;

  bool get allOk => failed.isEmpty;
  int get okCount => okIds.length;
}

Future<TransferBatchUpdateResult> updateTransferStatuses({
  required Iterable<int> transferIds,
  required String status,
  required int approvedBy,
}) async {
  final okIds = <int>[];
  final failed = <({int id, String message})>[];
  for (final id in transferIds) {
    try {
      final resp = await ApiClient.put(
        '/transfers/$id',
        body: jsonEncode({
          'status': status,
          'approved_by': approvedBy,
        }),
      );
      if (resp.statusCode == 200) {
        okIds.add(id);
        continue;
      }
      var msg = 'HTTP ${resp.statusCode}';
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) {
          msg = (decoded['error'] ?? decoded['detail'] ?? msg).toString();
        }
      } catch (_) {
        if (resp.body.isNotEmpty) msg = resp.body;
      }
      failed.add((id: id, message: msg));
    } catch (e) {
      failed.add((id: id, message: e.toString()));
    }
  }

  return TransferBatchUpdateResult(okIds: okIds, failed: failed);
}
