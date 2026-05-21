import 'package:vanessa3/utils/stock_request_transfer.dart';

/// Transfer antar toko: kedua cabang bertipe `toko`, bukan permintaan stok warehouse.
bool transferIsInterTokoTransfer(
  Map<String, dynamic> transfer, {
  required Set<String> tokoBranchIds,
}) {
  if (transferNotesIsStockRequest(transfer['notes']?.toString())) {
    return false;
  }
  final from = transfer['from_branch_id']?.toString().trim() ?? '';
  final to = transfer['to_branch_id']?.toString().trim() ?? '';
  if (from.isEmpty || to.isEmpty) return false;
  return tokoBranchIds.contains(from) && tokoBranchIds.contains(to);
}

List<Map<String, dynamic>> filterTransfersInterToko(
  Iterable<dynamic> raw,
  Set<String> tokoBranchIds,
) {
  final out = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final m = Map<String, dynamic>.from(e);
    if (transferIsInterTokoTransfer(m, tokoBranchIds: tokoBranchIds)) {
      out.add(m);
    }
  }
  return out;
}

bool transferIsPeerBranchTypeTransfer(
  Map<String, dynamic> transfer, {
  required Set<String> scopedBranchIds,
}) {
  if (transferNotesIsStockRequest(transfer['notes']?.toString())) {
    return false;
  }
  final from = transfer['from_branch_id']?.toString().trim() ?? '';
  final to = transfer['to_branch_id']?.toString().trim() ?? '';
  if (from.isEmpty || to.isEmpty) return false;
  return scopedBranchIds.contains(from) && scopedBranchIds.contains(to);
}

bool transferMatchesBranchTypeScope(
  Map<String, dynamic> transfer, {
  required String scope,
  required Set<String> scopedBranchIds,
}) {
  if (scope == 'toko') {
    return transferIsInterTokoTransfer(transfer, tokoBranchIds: scopedBranchIds);
  }
  return transferIsPeerBranchTypeTransfer(
    transfer,
    scopedBranchIds: scopedBranchIds,
  );
}

List<Map<String, dynamic>> filterTransfersForBranchTypeScope(
  Iterable<dynamic> raw,
  String scope,
  Set<String> scopedBranchIds,
) {
  final out = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final m = Map<String, dynamic>.from(e);
    if (transferMatchesBranchTypeScope(
      m,
      scope: scope,
      scopedBranchIds: scopedBranchIds,
    )) {
      out.add(m);
    }
  }
  return out;
}
