/// Argumen navigasi ke halaman daftar stok (filter status / cabang).
class StockListRouteArgs {
  static const String statusFilterKey = 'status_filter';
  static const String branchIdKey = 'branch_id';

  static Map<String, String> missingStock({
    String? branchId,
  }) {
    final m = <String, String>{statusFilterKey: 'missing'};
    final b = branchId?.trim();
    if (b != null && b.isNotEmpty) m[branchIdKey] = b;
    return m;
  }

  static String? statusFilter(Object? arguments) {
    if (arguments is! Map) return null;
    final v = arguments[statusFilterKey];
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  static String? branchId(Object? arguments) {
    if (arguments is! Map) return null;
    final v = arguments[branchIdKey];
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }
}
