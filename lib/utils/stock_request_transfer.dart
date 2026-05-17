/// Marker in transfer `notes` for store-initiated requests (warehouse → toko).
const stockRequestTransferNotesTag = '[PERMINTAAN_STOK]';

/// Permintaan per kategori & jenis (bukan SKU); backend melewati mutasi stok otomatis saat selesai.
const stockRequestByCategoryTag = '[BY_KATEGORI_JENIS]';

bool transferNotesIsStockRequest(String? notes) {
  return (notes ?? '').contains(stockRequestTransferNotesTag);
}

String buildStockRequestTransferNotes(String? userNotes) {
  final u = userNotes?.trim() ?? '';
  if (u.isEmpty) return stockRequestTransferNotesTag;
  return '$stockRequestTransferNotesTag $u';
}

/// Catatan untuk permintaan stok berdasarkan kategori + jenis (satu baris permintaan).
String buildStockRequestNotesByCategory({
  required String kategori,
  required String jenis,
  String? userNotes,
}) {
  final k = kategori.trim();
  final j = jenis.trim();
  final buf = StringBuffer()
    ..writeln(stockRequestTransferNotesTag)
    ..writeln(stockRequestByCategoryTag)
    ..writeln('kategori: $k')
    ..writeln('jenis: $j');
  final u = userNotes?.trim() ?? '';
  if (u.isNotEmpty) {
    buf.writeln();
    buf.writeln(u);
  }
  return buf.toString().trimRight();
}

/// Tampilan `item_name` di daftar transfer (bukan SKU).
String stockRequestItemNameFromCategoryJenis({
  required String kategori,
  required String jenis,
}) {
  final k = kategori.trim();
  final j = jenis.trim();
  if (k.isEmpty && j.isEmpty) return 'Permintaan stok';
  if (k.isEmpty) return j;
  if (j.isEmpty) return k;
  return '$k — $j';
}
