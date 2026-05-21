/// Pengelompokan baris `transfers` per sesi pembuatan (satu form kirim = satu batch).
library;

/// Satu sesi kirim (beberapa `transfer_id`, satu surat jalan).
class TransferCreationBatch {
  TransferCreationBatch({
    required this.lines,
    required this.groupKey,
  }) : assert(lines.isNotEmpty);

  final List<Map<String, dynamic>> lines;
  final String groupKey;

  List<String> get transferIds => lines
      .map((t) => t['transfer_id']?.toString() ?? '')
      .where((s) => s.isNotEmpty)
      .toList();

  String get idsLabel =>
      transferIds.isEmpty ? '-' : transferIds.map((id) => '#$id').join(', ');

  String get toBranchName =>
      (lines.first['to_branch_name'] ?? '-').toString();

  String get fromBranchName =>
      (lines.first['from_branch_name'] ?? '-').toString();

  String get fromBranchId =>
      (lines.first['from_branch_id'] ?? '').toString().trim();

  String get toBranchId => (lines.first['to_branch_id'] ?? '').toString().trim();

  String get courier => kurirFromTransfer(lines.first);

  String get notes => (lines.first['notes'] ?? '').toString().trim();

  String get batchStatus {
    final statuses =
        lines.map((t) => (t['status'] ?? '').toString().trim()).toSet();
    if (statuses.length == 1) return statuses.first;
    if (statuses.contains('pending')) return 'pending';
    if (statuses.contains('rejected')) return 'mixed';
    return statuses.first;
  }

  DateTime? get createdAt {
    DateTime? latest;
    for (final t in lines) {
      final d = parseTransferCreatedAt(t['created_at']);
      if (d == null) continue;
      if (latest == null || d.isAfter(latest)) latest = d;
    }
    return latest;
  }

  int get lineCount => lines.length;

  int get totalQty {
    var sum = 0;
    for (final t in lines) {
      final q = t['quantity'] ?? t['qty'];
      if (q is int) {
        sum += q;
      } else {
        sum += int.tryParse(q?.toString() ?? '') ?? 0;
      }
    }
    return sum;
  }

  /// Baris item untuk tabel / detail (nama + qty per transfer).
  List<({String itemName, String qty})> get itemRows {
    return [
      for (final t in lines)
        (
          itemName: (t['item_name'] ?? t['nama_item'] ?? '-').toString(),
          qty: (t['quantity'] ?? t['qty'] ?? '-').toString(),
        ),
    ];
  }

  List<Map<String, dynamic>> get pendingLines => lines
      .where((t) => (t['status'] ?? '').toString().trim() == 'pending')
      .toList();

  int get pendingCount => pendingLines.length;

  bool isIncomingForBranch(String branchId) =>
      toBranchId == branchId.trim();

  bool isOutgoingForBranch(String branchId) =>
      fromBranchId == branchId.trim();
}

int? transferIdFromLine(Map<String, dynamic> line) {
  final raw = line['transfer_id'];
  if (raw is int) return raw;
  return int.tryParse(raw?.toString() ?? '');
}

String transferLineStatus(Map<String, dynamic> line) =>
    (line['status'] ?? '').toString().trim().toLowerCase();

String kurirFromTransfer(Map<String, dynamic> t) {
  for (final k in <String>['courier', 'kurir']) {
    final v = t[k];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isNotEmpty) return s;
  }
  final notes = t['notes']?.toString() ?? '';
  final m = RegExp(r'^\s*Kurir:\s*([^\n\r]+)', multiLine: true)
      .firstMatch(notes);
  if (m != null) return m.group(1)?.trim() ?? '-';
  return '-';
}

DateTime? parseTransferCreatedAt(dynamic raw) {
  if (raw == null) return null;
  try {
    return DateTime.parse(raw.toString()).toLocal();
  } catch (_) {
    return null;
  }
}

String _creationBatchKey(Map<String, dynamic> t) {
  final created = parseTransferCreatedAt(t['created_at']);
  final minuteBucket = created == null
      ? ''
      : '${created.year.toString().padLeft(4, '0')}-'
          '${created.month.toString().padLeft(2, '0')}-'
          '${created.day.toString().padLeft(2, '0')} '
          '${created.hour.toString().padLeft(2, '0')}:'
          '${created.minute.toString().padLeft(2, '0')}';
  return [
    (t['from_branch_id'] ?? '').toString(),
    (t['to_branch_id'] ?? '').toString(),
    kurirFromTransfer(t),
    (t['notes'] ?? '').toString().trim(),
    (t['created_by'] ?? '').toString(),
    minuteBucket,
  ].join('\u241f');
}

/// Gabungkan transfer yang dibuat bersamaan (satu submit form multi-item).
List<TransferCreationBatch> groupTransfersByCreationBatch(
  Iterable<dynamic> raw,
) {
  final maps = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is Map) maps.add(Map<String, dynamic>.from(e));
  }

  final byKey = <String, List<Map<String, dynamic>>>{};
  for (final t in maps) {
    final key = _creationBatchKey(t);
    byKey.putIfAbsent(key, () => []).add(t);
  }

  final batches = <TransferCreationBatch>[];
  for (final entry in byKey.entries) {
    final lines = List<Map<String, dynamic>>.from(entry.value)
      ..sort((a, b) {
        final ia = int.tryParse(a['transfer_id']?.toString() ?? '') ?? 0;
        final ib = int.tryParse(b['transfer_id']?.toString() ?? '') ?? 0;
        return ia.compareTo(ib);
      });
    batches.add(TransferCreationBatch(lines: lines, groupKey: entry.key));
  }

  batches.sort((a, b) {
    final ta = a.createdAt;
    final tb = b.createdAt;
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return tb.compareTo(ta);
  });

  return batches;
}
