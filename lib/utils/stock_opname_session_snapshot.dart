/// Snapshot sesi opname untuk cetak / ringkasan setelah simpan.
class StockOpnameSessionSnapshot {
  const StockOpnameSessionSnapshot({
    required this.branchId,
    required this.branchLabel,
    required this.selectedStatus,
    required this.scopeItems,
    required this.verifiedIds,
    required this.missingIds,
    required this.sessionNotes,
    required this.savedVerifiedCount,
    required this.savedMissingCount,
    required this.pendingAtSave,
  });

  final String branchId;
  final String branchLabel;
  final String selectedStatus;
  final List<Map<String, dynamic>> scopeItems;
  final Set<String> verifiedIds;
  final Set<String> missingIds;
  final String sessionNotes;
  final int savedVerifiedCount;
  final int savedMissingCount;
  final int pendingAtSave;

  int get scopeTotal => scopeItems.length;
}
