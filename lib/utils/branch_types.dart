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

/// Cabang tipe warehouse (`branch_type` = `warehouse`) — sumber kirim untuk permintaan stok toko → warehouse.
bool branchTypeIsWarehouse(String? raw) =>
    normalizeBranchTypeKey(raw) == 'warehouse';

/// Cabang yang dipakai sebagai sumber kirim stok (admin toko → warehouse).
bool branchTypeCanSupplyStockForTransfer(String? raw) =>
    branchTypeIsWarehouse(raw);
