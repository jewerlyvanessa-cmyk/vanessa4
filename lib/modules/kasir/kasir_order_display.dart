Map<String, dynamic> _stringKeyMap(dynamic o) {
  if (o is Map<String, dynamic>) return o;
  if (o is Map) return Map<String, dynamic>.from(o);
  return {};
}

/// Field aliases untuk `/orders/pending-payment` dan layar terkait (item / berat).
void normalizeKasirOrderMap(Map<String, dynamic> m) {
  final namaEmpty = !m.containsKey('nama_item') ||
      (m['nama_item']?.toString().trim().isEmpty ?? true);
  if (namaEmpty) {
    final alt = (m['item_name'] ?? m['name'])?.toString().trim();
    if (alt != null && alt.isNotEmpty) {
      m['nama_item'] = alt;
    }
  }
  final beratEmpty = !m.containsKey('berat') ||
      (m['berat']?.toString().trim().isEmpty ?? true);
  if (beratEmpty && m['weight'] != null) {
    m['berat'] = m['weight'];
  }
  if (!m.containsKey('qty') || (m['qty']?.toString().isEmpty ?? true)) {
    m['qty'] = m['quantity'];
  }
  if (!m.containsKey('customer_phone') ||
      (m['customer_phone']?.toString().isEmpty ?? true)) {
    m['customer_phone'] = m['phone'];
  }
  if (!m.containsKey('customer_address') ||
      (m['customer_address']?.toString().isEmpty ?? true)) {
    m['customer_address'] = m['address'];
  }
}

String kasirOrderItemTitle(dynamic o) {
  final map = _stringKeyMap(o);
  for (final k in ['nama_item', 'item_name', 'name']) {
    final v = map[k]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return 'N/A';
}

String kasirOrderWeightGramsLabel(dynamic o) {
  final map = _stringKeyMap(o);
  final raw = map['berat'] ?? map['weight'];
  if (raw == null) return 'N/A';
  final n = raw is num
      ? raw.toDouble()
      : double.tryParse(raw.toString().trim());
  if (n == null || n.isNaN || n.isInfinite) return 'N/A';
  if (n == 0) return '0';
  if ((n - n.round()).abs() < 1e-9) return n.round().toString();
  return n.toString();
}
