import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vanessa3/utils/network_config.dart';

/// Satu baris dari paste massal: `kode,nama,berat,qty,kadar`.
class WarehouseBulkLine {
  const WarehouseBulkLine({
    required this.displayLine,
    required this.kode,
    required this.nama,
    required this.berat,
    required this.qty,
    required this.purity,
  });

  final int displayLine;
  final String kode;
  final String nama;
  final double berat;
  final int qty;
  final String purity;
}

/// Hasil parse satu baris teks untuk pratinjau (tanpa throw).
class WarehouseBulkPreviewRow {
  const WarehouseBulkPreviewRow({
    required this.sourceLineNumber,
    required this.rawSnippet,
    this.line,
    this.parseError,
    this.duplicateWarning,
  });

  final int sourceLineNumber;
  final String rawSnippet;
  final WarehouseBulkLine? line;
  final String? parseError;
  final String? duplicateWarning;

  bool get isValid =>
      parseError == null &&
      duplicateWarning == null &&
      line != null;
}

String _snippet(String raw, [int max = 96]) {
  final t = raw.trim();
  if (t.length <= max) return t;
  return '${t.substring(0, max - 3)}...';
}

/// Pisah satu baris bulk menjadi kolom: tab (TSV), titik koma, atau koma.
List<String> splitWarehouseBulkLineParts(String line) {
  final t = line.trim();
  if (t.isEmpty) return const [];
  if (t.contains('\t')) {
    final p = t.split('\t').map((s) => s.trim()).toList();
    if (p.length < 5) return p;
    if (p.length == 5) return p;
    // Lebih dari 5 segmen (mis. tab di nama): gabung tengah jadi nama.
    return [
      p[0],
      p.sublist(1, p.length - 3).join(' '),
      p[p.length - 3],
      p[p.length - 2],
      p[p.length - 1],
    ];
  }
  if (t.contains(';')) {
    final p = t.split(';').map((s) => s.trim()).toList();
    if (p.length < 5) return p;
    if (p.length == 5) return p;
    // Lebih dari 5 segmen: gabung kolom tengah jadi nama (nama boleh berisi ;).
    return [
      p[0],
      p.sublist(1, p.length - 3).join('; '),
      p[p.length - 3],
      p[p.length - 2],
      p[p.length - 1],
    ];
  }
  final p = t.split(',').map((s) => s.trim()).toList();
  if (p.length < 5) return p;
  if (p.length == 5) return p;
  return [
    p[0],
    p.sublist(1, p.length - 3).join(', '),
    p[p.length - 3],
    p[p.length - 2],
    p[p.length - 1],
  ];
}

/// Satu baris dari tabel editor → teks bulk (tab). Aman untuk nama berisi koma.
String warehouseBulkEncodeTableRow(
  String kode,
  String nama,
  String berat,
  String qty,
  String kadar,
) {
  String norm(String s) =>
      s.replaceAll('\t', ' ').replaceAll('\n', ' ').replaceAll('\r', '');
  return [
    norm(kode),
    norm(nama),
    norm(berat),
    norm(qty),
    norm(kadar),
  ].join('\t');
}

/// Parse satu baris data. `line` dan `error` keduanya null jika baris kosong / komentar.
({WarehouseBulkLine? line, String? error}) warehouseParseSingleBulkLine(
  String rawLine,
  int displayLine,
) {
  final line = rawLine.trim();
  if (line.isEmpty || line.startsWith('#')) {
    return (line: null, error: null);
  }
  final parts = splitWarehouseBulkLineParts(line);
  if (parts.length < 5) {
    return (
      line: null,
      error:
          'Kurang kolom (perlu 5: kode, nama, berat, qty, kadar). '
          'Nama berisi koma? Gunakan titik koma atau tempel dari tabel.',
    );
  }
  final kode = parts[0];
  final nama = parts[1];
  final berat = double.tryParse(parts[2].replaceAll(',', '.'));
  final qty = int.tryParse(parts[3]);
  final purity = parts[4].trim();
  if (kode.isEmpty) {
    return (line: null, error: 'Kode kosong');
  }
  if (nama.isEmpty) {
    return (line: null, error: 'Nama kosong');
  }
  if (berat == null || berat <= 0) {
    return (line: null, error: 'Berat tidak valid');
  }
  if (qty == null || qty <= 0) {
    return (line: null, error: 'Qty tidak valid');
  }
  if (purity.isEmpty) {
    return (line: null, error: 'Kadar kosong');
  }
  return (
    line: WarehouseBulkLine(
      displayLine: displayLine,
      kode: kode,
      nama: nama,
      berat: berat,
      qty: qty,
      purity: purity,
    ),
    error: null,
  );
}

/// Pratinjau semua baris: baris bermasalah tetap tampil dengan pesan error (tidak throw).
List<WarehouseBulkPreviewRow> previewWarehouseBulkPaste(String raw) {
  final lines = raw.split(RegExp(r'\r?\n'));
  final draft = <WarehouseBulkPreviewRow>[];
  var lineNo = 0;
  for (final rawLine in lines) {
    lineNo++;
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    final r = warehouseParseSingleBulkLine(trimmed, lineNo);
    if (r.error != null) {
      draft.add(
        WarehouseBulkPreviewRow(
          sourceLineNumber: lineNo,
          rawSnippet: _snippet(trimmed),
          parseError: r.error,
        ),
      );
    } else if (r.line != null) {
      draft.add(
        WarehouseBulkPreviewRow(
          sourceLineNumber: lineNo,
          rawSnippet: _snippet(trimmed),
          line: r.line,
        ),
      );
    }
  }

  final kodeCount = <String, int>{};
  for (final row in draft) {
    if (row.line == null) continue;
    final k = row.line!.kode.trim().toLowerCase();
    kodeCount[k] = (kodeCount[k] ?? 0) + 1;
  }

  return draft.map((row) {
    if (row.line == null) return row;
    final k = row.line!.kode.trim().toLowerCase();
    if ((kodeCount[k] ?? 0) > 1) {
      return WarehouseBulkPreviewRow(
        sourceLineNumber: row.sourceLineNumber,
        rawSnippet: row.rawSnippet,
        line: row.line,
        duplicateWarning: 'Kode duplikat dalam data ini',
      );
    }
    return row;
  }).toList();
}

List<WarehouseBulkLine> parseWarehouseBulkLines(String raw) {
  final preview = previewWarehouseBulkPaste(raw);
  final invalid = preview.where((r) => !r.isValid).toList();
  if (invalid.isNotEmpty) {
    throw FormatException(
      '${invalid.length} baris tidak valid — gunakan pratinjau untuk detail.',
    );
  }
  if (preview.isEmpty) {
    throw const FormatException('Tidak ada baris data (kosong atau hanya komentar #).');
  }
  return preview.map((r) => r.line!).toList();
}

Future<({Map<String, dynamic>? created, String? error})> warehousePostStockItem({
  required String branchId,
  required String name,
  required String kodeBarang,
  required double weight,
  required int quantity,
  required String material,
  required String purity,
  required String kategori,
  required String jenis,
  required String tipe,
}) async {
  try {
    final baseUrl = NetworkConfig.baseUrl;

    final payload = <String, dynamic>{
      'name': name,
      'item_code': kodeBarang,
      'kode_produk': kodeBarang,
      'weight': weight,
      'quantity': quantity,
      'status': 'ready',
      'branch_id': branchId,
      'source': 'manual_stockist',
      'kategori': kategori,
      'jenis': jenis,
      'tipe': tipe,
      'material': material,
      if (purity.isNotEmpty) 'purity': purity,
    };

    final resp = await http.post(
      Uri.parse('$baseUrl/items'),
      headers: NetworkConfig.defaultHeaders,
      body: jsonEncode(payload),
    );

    if (resp.statusCode == 201 || resp.statusCode == 200) {
      Map<String, dynamic>? created;
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) {
          created = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
      return (created: created, error: null);
    }

    String backendMsg = resp.body;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map && decoded['error'] != null) {
        backendMsg = decoded['error'].toString();
      } else if (decoded is Map && decoded['detail'] != null) {
        backendMsg = decoded['detail'].toString();
      }
    } catch (_) {}
    return (
      created: null,
      error: '(${resp.statusCode}) $backendMsg',
    );
  } catch (e) {
    return (created: null, error: e.toString());
  }
}

/// Satu baris barang dalam penerimaan supplier (multi-item).
class SupplierReceiptLine {
  const SupplierReceiptLine({
    required this.name,
    required this.kodeBarang,
    required this.weight,
    required this.quantity,
    required this.material,
    required this.purity,
    required this.kategori,
    required this.jenis,
    required this.tipe,
  });

  final String name;
  final String kodeBarang;
  final double weight;
  final int quantity;
  final String material;
  final String purity;
  final String kategori;
  final String jenis;
  final String tipe;

  String get summary =>
      '$name · $kodeBarang · ${weight}g · qty $quantity · $material $purity';
}

/// Penerimaan barang beli dari supplier (admin warehouse).
Future<({Map<String, dynamic>? created, String? error})> warehousePostSupplierReceipt({
  required String branchId,
  required String supplierName,
  required String name,
  required String kodeBarang,
  required double weight,
  required int quantity,
  required String material,
  required String purity,
  required String kategori,
  required String jenis,
  required String tipe,
  String? invoiceNumber,
  String? receiptNotes,
  String? receiptBatchId,
}) async {
  try {
    final baseUrl = NetworkConfig.baseUrl;
    final metadata = <String, dynamic>{
      'supplier': supplierName.trim(),
      'received_at': DateTime.now().toIso8601String(),
      if (invoiceNumber != null && invoiceNumber.trim().isNotEmpty)
        'invoice_number': invoiceNumber.trim(),
      if (receiptNotes != null && receiptNotes.trim().isNotEmpty)
        'receipt_notes': receiptNotes.trim(),
      if (receiptBatchId != null && receiptBatchId.trim().isNotEmpty)
        'receipt_batch_id': receiptBatchId.trim(),
    };

    final payload = <String, dynamic>{
      'name': name,
      'item_code': kodeBarang,
      'kode_produk': kodeBarang,
      'weight': weight,
      'quantity': quantity,
      'status': 'ready',
      'branch_id': branchId,
      'source': 'supplier_receipt',
      'metadata': metadata,
      'kategori': kategori,
      'jenis': jenis,
      'tipe': tipe,
      'material': material,
      if (purity.isNotEmpty) 'purity': purity,
    };

    final resp = await http.post(
      Uri.parse('$baseUrl/items'),
      headers: NetworkConfig.defaultHeaders,
      body: jsonEncode(payload),
    );

    if (resp.statusCode == 201 || resp.statusCode == 200) {
      Map<String, dynamic>? created;
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) {
          created = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
      return (created: created, error: null);
    }

    String backendMsg = resp.body;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map && decoded['error'] != null) {
        backendMsg = decoded['error'].toString();
      } else if (decoded is Map && decoded['detail'] != null) {
        backendMsg = decoded['detail'].toString();
      }
    } catch (_) {}
    return (
      created: null,
      error: '(${resp.statusCode}) $backendMsg',
    );
  } catch (e) {
    return (created: null, error: e.toString());
  }
}

/// Simpan banyak barang dalam satu penerimaan supplier (metadata batch sama).
Future<
    ({
      List<Map<String, dynamic>> created,
      List<({int index, String message})> failures,
    })> warehousePostSupplierReceiptBatch({
  required String branchId,
  required String supplierName,
  required List<SupplierReceiptLine> lines,
  String? invoiceNumber,
  String? receiptNotes,
}) async {
  if (lines.isEmpty) {
    return (
      created: <Map<String, dynamic>>[],
      failures: <({int index, String message})>[],
    );
  }
  final batchId = DateTime.now().millisecondsSinceEpoch.toString();
  final created = <Map<String, dynamic>>[];
  final List<({int index, String message})> failures = [];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final res = await warehousePostSupplierReceipt(
      branchId: branchId,
      supplierName: supplierName,
      name: line.name,
      kodeBarang: line.kodeBarang,
      weight: line.weight,
      quantity: line.quantity,
      material: line.material,
      purity: line.purity,
      kategori: line.kategori,
      jenis: line.jenis,
      tipe: line.tipe,
      invoiceNumber: invoiceNumber,
      receiptNotes: receiptNotes,
      receiptBatchId: batchId,
    );
    if (res.created != null) {
      created.add(res.created!);
    } else {
      failures.add((
        index: i,
        message: res.error ?? 'Gagal menyimpan ${line.kodeBarang}',
      ));
    }
  }

  return (created: created, failures: failures);
}

/// Riwayat penerimaan supplier terbaru di cabang.
Future<({List<Map<String, dynamic>> items, String? error})>
    fetchSupplierReceiptHistory({
  required String branchId,
  int limit = 20,
}) async {
  try {
    final baseUrl = NetworkConfig.baseUrl;
    final uri = Uri.parse(
      '$baseUrl/items?branch_id=$branchId&source=supplier_receipt&limit=$limit',
    );
    final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
    if (resp.statusCode != 200) {
      return (
        items: <Map<String, dynamic>>[],
        error: '(${resp.statusCode}) ${resp.body}',
      );
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! List) {
      return (
        items: <Map<String, dynamic>>[],
        error: 'Format respons tidak valid',
      );
    }
    final items = decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return (items: items, error: null);
  } catch (e) {
    return (items: <Map<String, dynamic>>[], error: e.toString());
  }
}
