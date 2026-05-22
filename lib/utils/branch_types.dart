/// Selaras dengan `branches.branch_type` di backend (`branches_schema.js`).
const List<String> kBranchTypeKeys = [
  'toko',
  'warehouse',
  'workshop',
  'pusat',
];

const Map<String, String> kBranchTypeLabels = {
  'toko': 'Toko (etalase)',
  'warehouse': 'Warehouse',
  'workshop': 'Workshop',
  'pusat': 'Pusat (HQ)',
};

String normalizeBranchTypeKey(String? raw) {
  final s = (raw ?? 'toko').toString().trim().toLowerCase();
  return kBranchTypeKeys.contains(s) ? s : 'toko';
}

String branchTypeLabel(String? raw) =>
    kBranchTypeLabels[normalizeBranchTypeKey(raw)] ?? 'Toko (etalase)';

/// Cabang etalase (`branch_type` = `toko`).
bool branchTypeIsToko(String? raw) => normalizeBranchTypeKey(raw) == 'toko';

/// Cabang bengkel (`branch_type` = `workshop`).
bool branchTypeIsWorkshop(String? raw) =>
    normalizeBranchTypeKey(raw) == 'workshop';

/// Cabang tipe warehouse (`branch_type` = `warehouse`) — sumber kirim untuk permintaan stok toko → warehouse.
bool branchTypeIsWarehouse(String? raw) =>
    normalizeBranchTypeKey(raw) == 'warehouse';

/// Cabang etalase atau gudang — dipakai laporan/stok global manajer & owner.
bool branchTypeIsTokoOrWarehouse(String? raw) =>
    branchTypeIsToko(raw) || branchTypeIsWarehouse(raw);

bool branchMatchesTypeScope(String? branchType, String scope) {
  switch (scope.trim().toLowerCase()) {
    case 'toko':
      return branchTypeIsToko(branchType);
    case 'workshop':
      return branchTypeIsWorkshop(branchType);
    case 'warehouse':
      return branchTypeIsWarehouse(branchType);
    default:
      return true;
  }
}

/// Filter daftar cabang dari GET /branches untuk dropdown tujuan transfer.
List<Map<String, dynamic>> filterBranchesForTypeScope(
  Iterable<dynamic> raw,
  String scope,
) {
  final out = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final m = Map<String, dynamic>.from(e);
    if (branchMatchesTypeScope(m['branch_type']?.toString(), scope)) {
      out.add(m);
    }
  }
  return out;
}

Set<String> branchIdsForTypeScope(Iterable<Map<String, dynamic>> branches) =>
    branches
        .map((b) => b['branch_id']?.toString().trim())
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet();

/// Cabang yang dipakai sebagai sumber kirim stok (admin toko → warehouse).
bool branchTypeCanSupplyStockForTransfer(String? raw) =>
    branchTypeIsWarehouse(raw);

/// Judul halaman kirim/terima sesuai scope cabang.
String goodsTransferPageTitle(
  String scope, {
  String? destinationScope,
}) {
  if (normalizeBranchTypeKey(scope) == 'warehouse' &&
      destinationScope != null &&
      normalizeBranchTypeKey(destinationScope) == 'workshop') {
    return 'Kirim Barang ke Workshop';
  }
  switch (normalizeBranchTypeKey(scope)) {
    case 'warehouse':
      return 'Kirim / Terima Antar Warehouse';
    case 'workshop':
      return 'Kirim / Terima Antar Workshop';
    case 'toko':
    default:
      return 'Kirim / Terima Antar Toko';
  }
}
