import 'package:vanessa3/shared_widgets/stock_status_filter_summary_header.dart';

/// Normalisasi hasil scan QR/barcode atau input manual untuk pencarian stok.
String normalizeStockSearchQuery(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;

  // Payload URL: ambil segmen terakhir atau query item_code / code.
  if (s.contains('://') || s.startsWith('http')) {
    try {
      final uri = Uri.parse(s);
      final fromQuery = uri.queryParameters['item_code'] ??
          uri.queryParameters['code'] ??
          uri.queryParameters['kode'];
      if (fromQuery != null && fromQuery.trim().isNotEmpty) {
        return fromQuery.trim();
      }
      final segs = uri.pathSegments.where((e) => e.trim().isNotEmpty).toList();
      if (segs.isNotEmpty) return segs.last.trim();
    } catch (_) {
      // pakai string asli
    }
  }

  // Beberapa QR berformat "ITEM:KB001" atau "kode=KB001".
  final lower = s.toLowerCase();
  for (final prefix in ['item:', 'kode:', 'code:', 'item_code:']) {
    if (lower.startsWith(prefix)) {
      return s.substring(prefix.length).trim();
    }
  }
  final eq = RegExp(r'^(?:item_code|kode|code)\s*=\s*(.+)$', caseSensitive: false);
  final m = eq.firstMatch(s);
  if (m != null) return m.group(1)!.trim();

  return s;
}

bool _fieldContains(dynamic value, String q) {
  final s = value?.toString().trim().toLowerCase() ?? '';
  return s.isNotEmpty && s.contains(q);
}

/// Pencarian lokal di daftar stok: kode, nama, jenis, kategori, material, kadar, status, id.
bool stockInventoryItemMatchesQuery(dynamic item, String rawQuery) {
  if (item is! Map) return false;
  final q = normalizeStockSearchQuery(rawQuery).toLowerCase();
  if (q.isEmpty) return true;

  final map = Map<String, dynamic>.from(item);
  final code =
      (map['item_code'] ?? map['kode_produk'] ?? '').toString().toLowerCase();
  if (code == q || code.contains(q)) return true;

  if (_fieldContains(map['name'], q)) return true;
  if (_fieldContains(map['jenis'], q)) return true;
  if (_fieldContains(map['kategori'], q)) return true;
  if (_fieldContains(map['tipe'], q)) return true;
  if (_fieldContains(map['material'], q)) return true;
  if (_fieldContains(map['purity'], q)) return true;
  if (_fieldContains(map['branch_name'], q)) return true;
  if (_fieldContains(map['branch_id'], q)) return true;
  if (_fieldContains(map['item_id'], q)) return true;

  final status = (map['status'] ?? '').toString();
  if (status.toLowerCase().contains(q)) return true;
  if (stockItemStatusLabel(status).toLowerCase().contains(q)) return true;

  return false;
}
