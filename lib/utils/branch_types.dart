/// Selaras dengan `branches.branch_type` di backend (`branches_schema.js`).
const List<String> kBranchTypeKeys = [
  'toko',
  'warehouse',
  'workshop',
  'pusat',
];

const Map<String, String> kBranchTypeLabels = {
  'toko': 'Toko (etalase)',
  'warehouse': 'Gudang',
  'workshop': 'Workshop / bengkel',
  'pusat': 'Pusat (HQ)',
};

String normalizeBranchTypeKey(String? raw) {
  final s = (raw ?? 'toko').toString().trim().toLowerCase();
  return kBranchTypeKeys.contains(s) ? s : 'toko';
}

String branchTypeLabel(String? raw) =>
    kBranchTypeLabels[normalizeBranchTypeKey(raw)] ?? 'Toko (etalase)';

/// Cabang yang dipakai sebagai sumber kirim stok (admin toko → gudang).
bool branchTypeCanSupplyStockForTransfer(String? raw) {
  final t = normalizeBranchTypeKey(raw);
  return t == 'warehouse' || t == 'pusat';
}
