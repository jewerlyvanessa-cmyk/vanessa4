/// Nilai tagihan order untuk Order Today / laporan — **bukan** subtotal baris item.
///
/// Prioritas: `orders.total` (total order setelah diskon & pembulatan item),
/// fallback `orders.jumlah` (pembulatan naik ke kelipatan 5.000).
/// Tidak memakai `item_total` / subtotal per baris.
num orderBillAmountFromRow(Map<String, dynamic> row) {
  num parse(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw;
    return num.tryParse(raw.toString()) ?? 0;
  }

  final total = parse(row['total']);
  if (total > 0) return total;

  final jumlah = parse(row['jumlah']);
  if (jumlah > 0) return jumlah;

  return 0;
}
