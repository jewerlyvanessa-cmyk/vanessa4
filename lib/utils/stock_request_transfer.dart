/// Marker in transfer `notes` for store-initiated requests (gudang → toko).
const stockRequestTransferNotesTag = '[PERMINTAAN_STOK]';

bool transferNotesIsStockRequest(String? notes) {
  return (notes ?? '').contains(stockRequestTransferNotesTag);
}

String buildStockRequestTransferNotes(String? userNotes) {
  final u = userNotes?.trim() ?? '';
  if (u.isEmpty) return stockRequestTransferNotesTag;
  return '$stockRequestTransferNotesTag $u';
}
