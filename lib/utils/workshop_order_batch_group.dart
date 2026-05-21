/// Pengelompokan order service/custom per "dokumen" (satu sesi aksi, menit yang sama).
library;

/// Satu dokumen = beberapa order dalam satu batch UI (bukan tabel transfers).
class WorkshopOrderDocumentBatch {
  WorkshopOrderDocumentBatch({
    required this.lines,
    required this.groupKey,
    required this.flowLabel,
  }) : assert(lines.isNotEmpty);

  final List<Map<String, dynamic>> lines;
  final String groupKey;

  /// Label alur, mis. "Terima dari workshop".
  final String flowLabel;

  List<int> get orderIds => lines
      .map(orderIdFromLine)
      .whereType<int>()
      .toList();

  String get idsLabel =>
      orderIds.isEmpty ? '-' : orderIds.map((id) => '#$id').join(', ');

  DateTime? get documentTime {
    DateTime? latest;
    for (final o in lines) {
      final d = parseOrderDocumentTime(o);
      if (d == null) continue;
      if (latest == null || d.isAfter(latest)) latest = d;
    }
    return latest;
  }

  int get lineCount => lines.length;

  /// Baris ringkas untuk tabel dokumen.
  List<({String title, String subtitle})> get orderRows {
    return [
      for (final o in lines)
        (
          title: _orderTitle(o),
          subtitle: _orderSubtitle(o),
        ),
    ];
  }

  List<Map<String, dynamic>> linesWhereStatus(String status) => lines
      .where((o) => transferLineStatusLike(o) == status.trim().toLowerCase())
      .toList();

  List<Map<String, dynamic>> linesMatching(bool Function(Map<String, dynamic> o) test) =>
      lines.where(test).toList();
}

int? orderIdFromLine(Map<String, dynamic> line) {
  final raw = line['order_id'];
  if (raw is int) return raw;
  return int.tryParse(raw?.toString() ?? '');
}

String transferLineStatusLike(Map<String, dynamic> line) =>
    (line['status'] ?? '').toString().trim().toLowerCase();

DateTime? parseOrderDocumentTime(dynamic raw) {
  if (raw == null) return null;
  try {
    return DateTime.parse(raw.toString()).toLocal();
  } catch (_) {
    return null;
  }
}

String _orderTitle(Map<String, dynamic> o) {
  final oid = o['order_id']?.toString() ?? '-';
  final item = (o['item_name'] ?? o['nama_item'] ?? '—').toString();
  return '#$oid · $item';
}

String _orderSubtitle(Map<String, dynamic> o) {
  final cust = (o['customer_name'] ?? '—').toString();
  final type = (o['order_type'] ?? '').toString();
  final st = (o['status'] ?? '').toString();
  final parts = <String>[cust];
  if (type.isNotEmpty) parts.add(type);
  if (st.isNotEmpty) parts.add(st);
  return parts.join(' · ');
}

String _storeBranchKey(Map<String, dynamic> o) {
  final pickup = o['pickup_branch_id']?.toString().trim();
  if (pickup != null && pickup.isNotEmpty) return pickup;
  return (o['branch_id'] ?? '').toString();
}

String _documentBatchKey(
  Map<String, dynamic> o, {
  required String flow,
  String? counterpartyBranch,
}) {
  final t = parseOrderDocumentTime(o['updated_at'] ?? o['created_at']);
  final minuteBucket = t == null
      ? ''
      : '${t.year.toString().padLeft(4, '0')}-'
          '${t.month.toString().padLeft(2, '0')}-'
          '${t.day.toString().padLeft(2, '0')} '
          '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}';
  return [
    flow,
    counterpartyBranch ?? _storeBranchKey(o),
    minuteBucket,
  ].join('\u241f');
}

/// [flow] memisahkan pengelompokan antar layar (terima toko, setuju workshop, dll.).
List<WorkshopOrderDocumentBatch> groupWorkshopOrdersByDocument(
  Iterable<dynamic> raw, {
  required String flow,
  required String flowLabel,
  String Function(Map<String, dynamic> o)? counterpartyBranch,
}) {
  final maps = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is Map) maps.add(Map<String, dynamic>.from(e));
  }

  final byKey = <String, List<Map<String, dynamic>>>{};
  for (final o in maps) {
    final cp = counterpartyBranch?.call(o);
    final key = _documentBatchKey(o, flow: flow, counterpartyBranch: cp);
    byKey.putIfAbsent(key, () => []).add(o);
  }

  final batches = <WorkshopOrderDocumentBatch>[];
  for (final entry in byKey.entries) {
    final lines = List<Map<String, dynamic>>.from(entry.value)
      ..sort((a, b) {
        final ia = orderIdFromLine(a) ?? 0;
        final ib = orderIdFromLine(b) ?? 0;
        return ia.compareTo(ib);
      });
    batches.add(
      WorkshopOrderDocumentBatch(
        lines: lines,
        groupKey: entry.key,
        flowLabel: flowLabel,
      ),
    );
  }

  batches.sort((a, b) {
    final ta = a.documentTime;
    final tb = b.documentTime;
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return tb.compareTo(ta);
  });

  return batches;
}
