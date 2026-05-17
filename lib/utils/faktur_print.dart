import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/terbilang.dart';

final Map<String, Uint8List> _imageByteCache = <String, Uint8List>{};

bool _bytesLookLikeRasterImage(Uint8List b) {
  if (b.length < 6) return false;
  if (b[0] == 0xff && b[1] == 0xd8) return true;
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4e &&
      b[3] == 0x47 &&
      b[4] == 0x0d &&
      b[5] == 0x0a &&
      b[6] == 0x1a &&
      b[7] == 0x0a) {
    return true;
  }
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return true;
  }
  if (b.length >= 6) {
    final g = String.fromCharCodes(b.sublist(0, 6));
    if (g == 'GIF87a' || g == 'GIF89a') return true;
  }
  return false;
}

bool _bytesDecodableAsPdfImage(Uint8List b) {
  try {
    pw.MemoryImage(b);
    return true;
  } catch (_) {
    return false;
  }
}

/// Respons API error sering 200 dengan body JSON — jangan cache sebagai gambar.
bool _bytesLookLikeJsonObject(Uint8List b) {
  for (var i = 0; i < b.length && i < 64; i++) {
    final c = b[i];
    if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) continue;
    return c == 0x7b;
  }
  return false;
}

Map<String, dynamic> _fakturMetadataMap(Map<String, dynamic> orderData) {
  final raw = orderData['metadata'];
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String) {
    final s = raw.trim();
    if (s.isEmpty) return const {};
    try {
      final d = jsonDecode(s);
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
  }
  return const {};
}

/// Total biaya untuk faktur ambil: biaya aktual dari tukang (`order_cost_breakdown` → metadata & `orders.total`).
/// Tidak mengutamakan `orders.jumlah` bila sudah ada revisi biaya workshop (`cost_revision`).
double pickupTotalBiayaFromWorkshopInput(Map<String, dynamic> orderData) {
  final meta = _fakturMetadataMap(orderData);
  final rev = int.tryParse(meta['cost_revision']?.toString() ?? '');
  final otd =
      double.tryParse(meta['order_total_after_discount']?.toString() ?? '');
  if (rev != null && rev > 0) {
    if (otd != null && otd > 0) return otd;
    final t = double.tryParse(orderData['total']?.toString() ?? '');
    if (t != null && t > 0) return t;
  }
  final tot = double.tryParse(orderData['total']?.toString() ?? '') ?? 0;
  if (tot > 0) return (tot / 5000).ceil() * 5000;
  final jum = double.tryParse(orderData['jumlah']?.toString() ?? '');
  if (jum != null && jum > 0) return (jum / 5000).ceil() * 5000;
  return 0;
}

/// DP / uang muka dari payload + metadata (tanpa jaringan).
double fakturDpFromPayloadSync(Map<String, dynamic> orderData) {
  final type = (orderData['order_type'] ?? '').toString().trim().toLowerCase();
  if (type != 'service' && type != 'custom') return 0;
  final metadata = _fakturMetadataMap(orderData);
  for (final raw in [
    orderData['service_dp_amount'],
    orderData['dp_amount'],
    orderData['uang_muka'],
    metadata['service_dp_amount'],
  ]) {
    final n = double.tryParse(raw?.toString() ?? '');
    if (n != null && n > 0) return n;
  }
  return 0;
}

/// DP untuk service/custom: jumlah pembayaran bertipe DP di server, fallback [fakturDpFromPayloadSync].
Future<double> resolveFakturDpAmount(Map<String, dynamic> orderData) async {
  final type = (orderData['order_type'] ?? '').toString().trim().toLowerCase();
  if (type != 'service' && type != 'custom') return 0;

  double fromPayload() => fakturDpFromPayloadSync(orderData);

  try {
    final oid = orderData['order_id']?.toString().trim();
    if (oid != null && oid.isNotEmpty) {
      final uri = Uri.parse('${NetworkConfig.baseUrl}/payments').replace(
        queryParameters: {'order_id': oid, 'limit': '50'},
      );
      final resp = await http
          .get(uri, headers: NetworkConfig.defaultHeaders)
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is List) {
          double sum = 0;
          for (final raw in decoded) {
            if (raw is! Map) continue;
            final m = Map<String, dynamic>.from(raw);
            final st = (m['status'] ?? '').toString().toLowerCase();
            if (st == 'cancelled' || st == 'failed') continue;
            final kind = (m['payment_kind'] ?? '').toString().toLowerCase();
            final notes = (m['notes'] ?? '').toString().toLowerCase();
            final isDp =
                kind == 'dp' ||
                notes.contains('uang muka') ||
                notes.contains('muka (service)') ||
                notes.contains('muka (custom)');
            if (!isDp) continue;
            final amt = double.tryParse(m['amount']?.toString() ?? '') ?? 0;
            if (amt > 0) sum += amt;
          }
          if (sum > 0) return sum;
        }
      }
    }
  } catch (_) {}

  return fromPayload();
}

/// Faktur PDF: transaksi order awal vs bukti pengambilan (judul & footer berbeda).
enum FakturPrintKind {
  /// ORDER SERVICE / ORDER CUSTOM (saat order dibuat).
  orderTransaction,

  /// AMBIL SERVICE / AMBIL CUSTOM — faktur terpisah; faktur order tetap referensi.
  pickup,
}

/// Ringkasan pembayaran untuk faktur ambil (sisa = total − terbayar).
/// Cetak PDF AMBIL SERVICE / AMBIL CUSTOM (faktur terpisah dari ORDER SERVICE/CUSTOM).
Future<void> printPickupServiceCustomFaktur(
  BuildContext context,
  Map<String, dynamic> orderData,
) async {
  final data = Map<String, dynamic>.from(orderData);
  data['pickup_faktur_date'] = DateTime.now().toUtc().toIso8601String();
  final snap = await fetchPaymentSummaryForPickupFaktur(
    data['order_id']?.toString() ?? '',
  );
  if (snap != null) {
    data['paid_amount'] = snap['paid'];
    data['remaining_amount'] = snap['remaining'];
  }
  if (!context.mounted) return;
  await printFakturOrder(context, data, kind: FakturPrintKind.pickup);
}

Future<Map<String, double>?> fetchPaymentSummaryForPickupFaktur(
  String orderId,
) async {
  final id = orderId.trim();
  if (id.isEmpty) return null;
  try {
    final uri = Uri.parse(
      '${NetworkConfig.baseUrl}/orders/payment-summary?order_id=${Uri.encodeQueryComponent(id)}',
    );
    final resp = await http
        .get(uri, headers: NetworkConfig.defaultHeaders)
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) return null;
    final m = Map<String, dynamic>.from(decoded);
    double p(String k) => double.tryParse(m[k]?.toString() ?? '') ?? 0;
    return {
      'total': p('total'),
      'paid': p('paid_amount'),
      'remaining': p('remaining_amount'),
      'dp': p('dp_amount'),
    };
  } catch (_) {
    return null;
  }
}

/// Field servis/custom untuk faktur layar & PDF (sinkron dengan sumber data backend + metadata).
Map<String, String> fakturServiceCustomFieldRows(
  Map<String, dynamic> orderData, {
  Map<String, dynamic>? orderItemSource,
}) {
  final type = (orderData['order_type'] ?? '').toString().trim().toLowerCase();
  if (type != 'service' && type != 'custom') {
    return const {};
  }

  Map<String, dynamic> toMap(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty) return const {};
      try {
        final d = jsonDecode(s);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return const {};
  }

  final items = orderData['items'] as List<dynamic>? ?? [];
  Map<String, dynamic> primaryItem = {};
  if (items.isNotEmpty && items.first is Map) {
    primaryItem = Map<String, dynamic>.from(items.first as Map);
  }
  final src = orderItemSource ?? primaryItem;
  final metadata = _fakturMetadataMap(orderData);
  final orderConditionMap = toMap(orderData['kondisi_barang']);

  String norm(dynamic v) {
    if (v == null) return '';
    if (v is List) {
      return v
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .join(', ');
    }
    return v.toString().trim();
  }

  String pickFirstText(List<dynamic> candidates, {String fallback = '-'}) {
    for (final c in candidates) {
      final s = norm(c);
      if (s.isNotEmpty && s != '-' && s.toUpperCase() != 'NULL') return s;
    }
    return fallback;
  }

  String fmtDots(dynamic v) {
    final n = double.tryParse(v?.toString() ?? '');
    if (n == null) return '0';
    final s = n.toStringAsFixed(0);
    return s.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
  }

  String fmtMoneyOrDashEst(dynamic v) {
    final d = double.tryParse(v?.toString() ?? '');
    if (d == null || d <= 0) return '-';
    return 'Rp. ${fmtDots(d)}';
  }

  double? pickFirstPositiveNumber(List<dynamic> values) {
    for (final raw in values) {
      final n = double.tryParse((raw ?? '').toString());
      if (n != null && n > 0) return n;
    }
    return null;
  }

  String formatLongDate(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty || s == '-') return '-';
    try {
      final dt = DateTime.parse(s).toLocal();
      const monthNames = [
        'Januari',
        'Februari',
        'Maret',
        'April',
        'Mei',
        'Juni',
        'Juli',
        'Agustus',
        'September',
        'Oktober',
        'November',
        'Desember',
      ];
      return '${dt.day.toString().padLeft(2, '0')} ${monthNames[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return s;
    }
  }

  final jenisService = pickFirstText([
    src['tipe'],
    src['jenis_service'],
    src['item_tipe'],
    primaryItem['tipe'],
    orderData['jenis_service'],
    orderData['service_type'],
    metadata['jenis_service'],
    metadata['service_type'],
    orderConditionMap['jenis_service'],
    orderConditionMap['service_type'],
  ]);
  final kelengkapan = pickFirstText([
    orderData['kelengkapan'],
    orderData['barang_bawaan'],
    metadata['kelengkapan'],
    metadata['barang_bawaan'],
    orderConditionMap['kelengkapan'],
    orderConditionMap['barang_bawaan'],
  ]);
  final catatan = pickFirstText([
    orderData['keterangan'],
    orderData['spesifikasi'],
    orderData['estimate_notes'],
    orderData['catatan_service'],
    orderData['service_notes'],
    orderData['catatan'],
    metadata['keterangan'],
    metadata['spesifikasi'],
    metadata['catatan_service'],
    metadata['service_notes'],
    metadata['estimate_notes'],
    orderConditionMap['catatan_service'],
    orderConditionMap['catatan'],
  ]);
  final rev = int.tryParse(metadata['cost_revision']?.toString() ?? '');
  final hasFinalWorkshopCost =
      rev != null && rev > 0; // biaya aktual tersimpan dari workshop (bukan estimasi)

  final estNum = hasFinalWorkshopCost
      ? pickFirstPositiveNumber([
          orderData['total'],
          metadata['order_total_after_discount'],
          metadata['invoice_pre_discount_rounded'],
          metadata['actual_total_cost'],
        ])
      : pickFirstPositiveNumber([
          orderData['estimate_amount'],
          orderData['service_estimated_total'],
          orderData['custom_estimated_total'],
          orderData['estimasi_biaya'],
          orderData['estimate_cost'],
          metadata['estimate_amount'],
          metadata['service_estimated_total'],
          metadata['estimasi_biaya'],
          metadata['estimate_cost'],
          orderConditionMap['estimasi_biaya'],
          src['manual_total'],
          src['total'],
          src['subtotal'],
          orderData['total'],
          orderData['jumlah'],
        ]);
  final estimasiBiaya =
      estNum != null ? fmtMoneyOrDashEst(estNum) : '-';

  final estimasiSelesai = pickFirstText([
    formatLongDate(
      orderData['estimate_due_at'] ??
          orderData['estimated_finish_at'] ??
          orderData['estimated_completion_date'] ??
          metadata['estimate_due_at'] ??
          metadata['estimated_finish_at'],
    ),
    orderData['estimasi_selesai'],
    metadata['estimasi_selesai_text'],
    metadata['estimasi_selesai'],
    orderData['estimate_duration_text'],
    orderData['estimasi_waktu'],
    metadata['estimate_duration_text'],
    metadata['estimasi_waktu'],
  ]);

  return {
    'jenis_service': jenisService,
    'kelengkapan': kelengkapan,
    'catatan': catatan,
    'estimasi_biaya': estimasiBiaya,
    'estimasi_selesai': estimasiSelesai,
    'service_biaya_row_label':
        hasFinalWorkshopCost ? 'Total biaya (final)' : 'Estimasi biaya',
    'sisa_setelah_dp_row_label': hasFinalWorkshopCost
        ? 'Kurang bayar (setelah DP)'
        : 'Sisa estimasi',
  };
}

/// Builds a simple invoice PDF and opens the system print / share UI.
Future<void> printFakturOrder(
  BuildContext context,
  Map<String, dynamic> orderData, {
  FakturPrintKind kind = FakturPrintKind.orderTransaction,
}) async {
  try {
    final items = orderData['items'] as List<dynamic>? ?? [];
    final doc = pw.Document();

    String? photoUrl(dynamic raw) {
      final s0 = raw?.toString().trim();
      if (s0 == null || s0.isEmpty) return null;
      if (s0.startsWith('http://') || s0.startsWith('https://')) return s0;
      final s = s0.replaceAll('\\', '/');
      if (s.startsWith('/')) return '${NetworkConfig.baseUrl}$s';
      // DB sering simpan "uploads/namafile" tanpa slash depan — jangan jadi .../uploads/uploads/...
      if (RegExp(r'^uploads/', caseSensitive: false).hasMatch(s)) {
        return '${NetworkConfig.baseUrl}/$s';
      }
      return '${NetworkConfig.baseUrl}/uploads/$s';
    }

    bool isSameApiOrigin(String url) {
      try {
        final base = Uri.parse(NetworkConfig.baseUrl);
        final u = Uri.parse(url);
        return base.scheme == u.scheme &&
            base.host.toLowerCase() == u.host.toLowerCase() &&
            base.port == u.port;
      } catch (_) {
        return false;
      }
    }

    Future<Uint8List?> fetchBytes(
      String? url, {
      Duration timeout = const Duration(seconds: 3),
      bool imageBinary = false,
      bool validatePdfRaster = false,
    }) async {
      if (url == null) return null;
      final cached = _imageByteCache[url];
      if (cached != null) return cached;
      try {
        final Map<String, String>? headers = () {
          if (!isSameApiOrigin(url)) return null;
          final t = NetworkConfig.authToken;
          if (t == null || t.trim().isEmpty) return null;
          // Jangan kirim Accept/Content-Type JSON ke endpoint gambar — beberapa stack memperlakukan respons salah.
          if (imageBinary) {
            return {'Authorization': 'Bearer $t'};
          }
          return NetworkConfig.defaultHeaders;
        }();
        final resp = await http
            .get(Uri.parse(url), headers: headers)
            .timeout(timeout);
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          final body = resp.bodyBytes;
          if (imageBinary && _bytesLookLikeJsonObject(body)) {
            return null;
          }
          if (validatePdfRaster &&
              (!_bytesLookLikeRasterImage(body) || !_bytesDecodableAsPdfImage(body))) {
            return null;
          }
          // Keep cache lightweight and avoid unbounded growth.
          if (_imageByteCache.length > 40) {
            _imageByteCache.remove(_imageByteCache.keys.first);
          }
          _imageByteCache[url] = body;
          return body;
        }
      } catch (_) {}
      return null;
    }

    String? branchLogoUrlFromOrderData(Map<String, dynamic> data) {
      for (final raw in [
        data['logo_url'],
        data['branch_logo_url'],
        data['branchLogoUrl'],
      ]) {
        final url = photoUrl(raw);
        if (url != null) return url;
      }
      final branchRaw = data['branch'];
      if (branchRaw is Map) {
        final branch = Map<String, dynamic>.from(branchRaw);
        for (final raw in [
          branch['logo_url'],
          branch['branch_logo_url'],
          branch['logoUrl'],
        ]) {
          final url = photoUrl(raw);
          if (url != null) return url;
        }
      }
      return null;
    }

    String branchIdFromOrderData(Map<String, dynamic> data) {
      for (final key in ['branch_id', 'branchId']) {
        final raw = data[key];
        if (raw == null) continue;
        final s = raw.toString().trim();
        if (s.isNotEmpty && s != 'null') return s;
      }
      final branchRaw = data['branch'];
      if (branchRaw is Map) {
        final branch = Map<String, dynamic>.from(branchRaw);
        for (final key in ['branch_id', 'branchId', 'id']) {
          final raw = branch[key];
          if (raw == null) continue;
          final s = raw.toString().trim();
          if (s.isNotEmpty && s != 'null') return s;
        }
      }
      return '';
    }

    /// Cabang untuk logo: faktur ambil service/custom → cabang pengambilan bila ada.
    String branchIdForFakturLogo() {
      final t = (orderData['order_type'] ?? '').toString().toLowerCase();
      final usePickupBranch =
          kind == FakturPrintKind.pickup && (t == 'service' || t == 'custom');
      if (usePickupBranch) {
        for (final key in ['pickup_branch_id', 'pickupBranchId']) {
          final raw = orderData[key];
          if (raw == null) continue;
          final s = raw.toString().trim();
          if (s.isNotEmpty && s != 'null') return s;
        }
        final metaRaw = orderData['metadata'];
        if (metaRaw != null) {
          Map<String, dynamic>? m;
          if (metaRaw is Map) {
            m = Map<String, dynamic>.from(metaRaw);
          } else if (metaRaw is String && metaRaw.trim().isNotEmpty) {
            try {
              final d = jsonDecode(metaRaw);
              if (d is Map) m = Map<String, dynamic>.from(d);
            } catch (_) {}
          }
          if (m != null) {
            for (final key in ['pickup_branch_id', 'pickupBranchId']) {
              final raw = m[key];
              if (raw == null) continue;
              final s = raw.toString().trim();
              if (s.isNotEmpty && s != 'null') return s;
            }
          }
        }
      }
      return branchIdFromOrderData(orderData);
    }

    /// Urutan cabang untuk logo: cabang ambil (jika ada) lalu cabang order — jika cabang ambil tanpa file logo, tetap bisa pakai logo cabang order.
    List<String> orderedBranchIdsForLogo() {
      final ids = <String>[];
      final a = branchIdForFakturLogo();
      if (a.isNotEmpty) ids.add(a);
      final b = branchIdFromOrderData(orderData);
      if (b.isNotEmpty && b != a) ids.add(b);
      return ids;
    }

    Future<String?> fetchBranchLogoUrl() async {
      for (final branchId in orderedBranchIdsForLogo()) {
        for (final p in ['/branches/$branchId', '/api/branches/$branchId']) {
          try {
            final resp = await http
                .get(
                  Uri.parse('${NetworkConfig.baseUrl}$p'),
                  headers: NetworkConfig.defaultHeaders,
                )
                .timeout(const Duration(seconds: 3));
            if (resp.statusCode != 200) continue;
            final decoded = jsonDecode(resp.body);
            if (decoded is Map && decoded['logo_url'] != null) {
              final url = photoUrl(decoded['logo_url']);
              if (url != null && url.isNotEmpty) return url;
            }
          } catch (_) {}
        }
      }
      return null;
    }

    /// Sumber logo sama dengan layar Manajemen Cabang (`branches.logo_url` via GET /branches/:id).
    /// Jika `GET /orders?...` tidak menyisipkan logo (join gagal / payload lama), isi dari API cabang.
    Future<void> hydrateBranchLogoFromBranchesApiIfMissing() async {
      if (branchLogoUrlFromOrderData(orderData) != null) return;
      for (final bid in orderedBranchIdsForLogo()) {
        if (bid.isEmpty) continue;
        for (final p in ['/branches/$bid', '/api/branches/$bid']) {
          try {
            final resp = await http
                .get(
                  Uri.parse('${NetworkConfig.baseUrl}$p'),
                  headers: NetworkConfig.defaultHeaders,
                )
                .timeout(const Duration(seconds: 3));
            if (resp.statusCode != 200) continue;
            final decoded = jsonDecode(resp.body);
            if (decoded is! Map) continue;
            final s = decoded['logo_url']?.toString().trim();
            if (s == null || s.isEmpty) continue;
            orderData['logo_url'] = s;
            orderData['branch_logo_url'] = s;
            return;
          } catch (_) {}
        }
      }
    }

    Map<String, dynamic> toMap(dynamic raw) {
      if (raw is Map) return Map<String, dynamic>.from(raw);
      if (raw is String) {
        final s = raw.trim();
        if (s.isEmpty) return const <String, dynamic>{};
        try {
          final decoded = jsonDecode(s);
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } catch (_) {}
      }
      return const <String, dynamic>{};
    }

    Future<Map<String, dynamic>> fetchBuybackConditionFallback({
      required bool isBuyback,
      required Map<String, dynamic> item,
    }) async {
      if (!isBuyback) return const <String, dynamic>{};
      final fromItem = toMap(item['kondisi_barang']);
      if (fromItem.isNotEmpty) return fromItem;

      final orderId = (orderData['order_id'] ?? '').toString().trim();
      if (orderId.isEmpty) return const <String, dynamic>{};
      try {
        final resp = await http
            .get(
              Uri.parse(
                '${NetworkConfig.baseUrl}/item-conditions?order_id=$orderId',
              ),
              headers: NetworkConfig.defaultHeaders,
            )
            .timeout(const Duration(seconds: 3));
        if (resp.statusCode != 200) return const <String, dynamic>{};
        final decoded = jsonDecode(resp.body);
        if (decoded is! List || decoded.isEmpty) {
          return const <String, dynamic>{};
        }

        final itemId = (item['item_id'] ?? '').toString().trim();
        Map<String, dynamic>? chosen;
        for (final e in decoded) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          chosen ??= m;
          if (itemId.isNotEmpty && m['item_id']?.toString() == itemId) {
            chosen = m;
            break;
          }
        }
        if (chosen == null) return const <String, dynamic>{};

        final kerusakanRaw = chosen['kerusakan'];
        final kerusakanText = kerusakanRaw is List
            ? kerusakanRaw
                  .map((e) => e.toString())
                  .where((e) => e.isNotEmpty)
                  .join(', ')
            : (kerusakanRaw?.toString() ?? '');

        final resale = double.tryParse(
          (chosen['nilai_resale'] ?? '').toString(),
        );
        final beli = double.tryParse((chosen['harga_beli'] ?? '').toString());
        final derivedUntungRugi = (resale != null && beli != null)
            ? (resale >= beli ? 'UNTUNG' : 'RUGI')
            : null;

        return <String, dynamic>{
          'kondisi_fisik': chosen['kondisi_fisik'],
          'kerusakan': kerusakanText,
          'berat_akhir': chosen['berat_akhir'],
          'harga_beli': chosen['harga_beli'],
          'harga_per_gram': chosen['harga_per_gram'],
          'nilai_untung_rugi':
              chosen['nilai_untung_rugi'] ?? chosen['nilai_resale'],
          'potongan_kondisi': chosen['potongan_kondisi'],
          'untung_rugi': chosen['untung_rugi'] ?? derivedUntungRugi,
          'catatan_kondisi': chosen['catatan_kondisi'],
        };
      } catch (_) {
        return const <String, dynamic>{};
      }
    }

    Future<Map<String, dynamic>> fetchOrderItemFromOldNota({
      required bool isBuyback,
      required Map<String, dynamic> fallbackItem,
    }) async {
      if (!isBuyback) return fallbackItem;
      try {
        final metadata = toMap(orderData['metadata']);
        final fromOrderCondition = toMap(orderData['kondisi_barang']);
        final fromItemCondition = toMap(fallbackItem['kondisi_barang']);
        final conditionFallback = await fetchBuybackConditionFallback(
          isBuyback: isBuyback,
          item: fallbackItem,
        );
        final conditionNote = (conditionFallback['catatan_kondisi'] ?? '')
            .toString()
            .trim();
        final noteMatch = RegExp(
          r'nota_jual_ref\s*:\s*([A-Za-z0-9\-_/\.]+)',
          caseSensitive: false,
        ).firstMatch(conditionNote);
        final noteReference = noteMatch?.group(1)?.trim() ?? '';
        final candidates = <dynamic>[
          metadata['nota_lama'],
          metadata['nota_jual'],
          metadata['reference_order_number'],
          metadata['old_order_number'],
          conditionFallback['nota_jual'],
          if (noteReference.isNotEmpty) noteReference,
          fromItemCondition['nota_jual'],
          fromOrderCondition['nota_jual'],
          orderData['nota_lama'],
          orderData['nota_jual'],
          orderData['referensi_nota'],
          orderData['reference_order_number'],
        ];
        String notaLama = '';
        for (final c in candidates) {
          final s = (c ?? '').toString().trim();
          if (s.isNotEmpty && s != '-' && s.toUpperCase() != 'TIDAK_ADA') {
            notaLama = s;
            break;
          }
        }
        if (notaLama.isEmpty) return fallbackItem;

        final resp = await http
            .get(
              Uri.parse(
                '${NetworkConfig.baseUrl}/orders?order_number=$notaLama',
              ),
              headers: NetworkConfig.defaultHeaders,
            )
            .timeout(const Duration(seconds: 4));
        if (resp.statusCode != 200) return fallbackItem;
        final decoded = jsonDecode(resp.body);
        if (decoded is! Map) return fallbackItem;

        final oldItemsRaw = decoded['items'] ?? decoded['order_items'];
        if (oldItemsRaw is! List || oldItemsRaw.isEmpty) return fallbackItem;
        final oldItems = oldItemsRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (oldItems.isEmpty) return fallbackItem;

        final fallbackKode = (fallbackItem['kode_produk'] ?? '')
            .toString()
            .trim();
        final fallbackItemId = (fallbackItem['item_id'] ?? '')
            .toString()
            .trim();

        Map<String, dynamic>? picked;
        if (fallbackKode.isNotEmpty) {
          for (final m in oldItems) {
            final k = (m['kode_produk'] ?? m['item_kode'] ?? '')
                .toString()
                .trim();
            if (k.isNotEmpty && k == fallbackKode) {
              picked = m;
              break;
            }
          }
        }
        if (picked == null && fallbackItemId.isNotEmpty) {
          for (final m in oldItems) {
            final id = (m['item_id'] ?? '').toString().trim();
            if (id.isNotEmpty && id == fallbackItemId) {
              picked = m;
              break;
            }
          }
        }
        return picked ?? oldItems.first;
      } catch (_) {
        return fallbackItem;
      }
    }

    // Prefetch images once (best-effort) so PDF rendering stays synchronous.
    final itemMaps = items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final primaryItem = itemMaps.isNotEmpty
        ? itemMaps.first
        : <String, dynamic>{};
    final orderType = (orderData['order_type'] ?? '').toString().toLowerCase();
    final isBuyback = orderType == 'buyback';
    final isServiceOrder = orderType == 'service';
    final isCustomOrder = orderType == 'custom';
    final isServiceOrCustom = isServiceOrder || isCustomOrder;
    final isPickupFaktur =
        kind == FakturPrintKind.pickup && isServiceOrCustom;
    Map<String, double>? pickupPaymentSnapshot;
    if (isPickupFaktur) {
      pickupPaymentSnapshot = await fetchPaymentSummaryForPickupFaktur(
        orderData['order_id']?.toString() ?? '',
      );
    }
    final isSaleOrder = orderType == 'jual';
    final metadata = toMap(orderData['metadata']);
    final orderConditionMap = toMap(orderData['kondisi_barang']);
    final primaryItemConditionMap = toMap(primaryItem['kondisi_barang']);
    String extractOldNotaReference() {
      final candidates = <dynamic>[
        metadata['nota_lama'],
        metadata['nota_jual'],
        metadata['reference_order_number'],
        metadata['old_order_number'],
        primaryItemConditionMap['nota_jual'],
        orderConditionMap['nota_jual'],
        orderData['nota_lama'],
        orderData['nota_jual'],
        orderData['reference_order_number'],
        orderData['referensi_nota'],
      ];
      for (final c in candidates) {
        final s = (c ?? '').toString().trim();
        if (s.isNotEmpty && s != '-' && s.toUpperCase() != 'TIDAK_ADA') {
          return s;
        }
      }
      return '';
    }

    final oldNotaReference = extractOldNotaReference();
    // Hanya buyback: ambil baris dari nota jual lama (kondisi / harga buyback).
    // Service/custom jangan lewat sini — parameter `isBuyback` pernah salah `true` untuk
    // service sehingga item diganti ke order lama → Jenis Service / Harga/gram jadi kosong.
    final orderItemSource = await fetchOrderItemFromOldNota(
      isBuyback: isBuyback,
      fallbackItem: primaryItem,
    );
    String transactionLabelByOrderType(String type) {
      switch (type) {
        case 'jual':
          return 'TRANSAKSI PENJUALAN';
        case 'buyback':
          return 'TRANSAKSI BUYBACK';
        case 'service':
          return 'TRANSAKSI SERVIS';
        case 'custom':
          return 'TRANSAKSI CUSTOM';
        case 'ambil':
        case 'pickup':
        case 'picked_up':
          return 'TRANSAKSI PENGAMBILAN';
        default:
          if (type.trim().isEmpty) return 'TRANSAKSI ORDER';
          final normalized = type
              .trim()
              .split(RegExp(r'[_\s-]+'))
              .where((w) => w.isNotEmpty)
              .map(
                (w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
              )
              .join(' ');
          return 'TRANSAKSI ${normalized.toUpperCase()}';
      }
    }

    final transactionLabel = transactionLabelByOrderType(orderType);
    final primaryPhotoUrl = (() {
      for (final raw in [
        orderItemSource['photo_produk'],
        orderItemSource['photo_url'],
        orderItemSource['item_photo_produk'],
        orderItemSource['item_photo_url'],
        primaryItem['photo_produk'],
        primaryItem['photo_url'],
      ]) {
        final u = photoUrl(raw);
        if (u != null && u.isNotEmpty) return u;
      }
      return null;
    })();
    await hydrateBranchLogoFromBranchesApiIfMissing();
    final branchLogoUrlFast = branchLogoUrlFromOrderData(orderData);
    final fetchedBytes = await Future.wait<Uint8List?>([
      (() async {
        // 1) Proxy dulu: same-origin + JWT; server bisa stream file lokal atau tarik logo_url HTTPS lain (hindari CORS web ke domain lain).
        for (final bid in orderedBranchIdsForLogo()) {
          for (final logoPath in ['/branches/$bid/logo', '/api/branches/$bid/logo']) {
            final proxy = '${NetworkConfig.baseUrl}$logoPath';
            final viaProxy = await fetchBytes(
              proxy,
              timeout: const Duration(seconds: 25),
              imageBinary: true,
              // Sama seperti foto item: jangan pakai validatePdfRaster di sini.
              // Pre-check MemoryImage terlalu ketat — beberapa JPEG/WebP valid ditolak
              // sehingga logo hilang khususnya di faktur AMBIL (multi-cabang / proxy).
            );
            if (viaProxy != null) return viaProxy;
          }
        }
        final direct = await fetchBytes(
          branchLogoUrlFast,
          imageBinary: true,
        );
        if (direct != null) return direct;
        final fallbackUrl = await fetchBranchLogoUrl();
        return fetchBytes(
          fallbackUrl,
          imageBinary: true,
        );
      })(),
      fetchBytes(primaryPhotoUrl, imageBinary: true),
    ]);
    final branchLogoBytes = fetchedBytes[0];
    final primaryPhotoBytes = fetchedBytes[1];
    final buybackConditionFallback = await fetchBuybackConditionFallback(
      isBuyback: isBuyback,
      item: primaryItem,
    );

    String fmtMoney(dynamic v) {
      final n = double.tryParse(v?.toString() ?? '');
      if (n == null) return v?.toString() ?? '0';
      final s = n.toStringAsFixed(0);
      return s.replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      );
    }

    double? pickFirstPositiveNumber(List<dynamic> values) {
      for (final raw in values) {
        final n = double.tryParse((raw ?? '').toString());
        if (n != null && n > 0) return n;
      }
      return null;
    }

    String fmtGram(dynamic v) {
      final n = double.tryParse(v?.toString() ?? '');
      if (n == null) return (v ?? '-').toString();
      // Format like "1,580" (3 decimals, comma decimal separator)
      return n.toStringAsFixed(3).replaceAll('.', ',');
    }

    String dateStr(dynamic created) {
      if (created == null) return '-';
      try {
        return DateTime.parse(
          created.toString(),
        ).toLocal().toString().split('.').first;
      } catch (_) {
        return created.toString();
      }
    }

    final totalFinal = (() {
      final rawJumlah = orderData['jumlah'];
      final rawTotal = orderData['total'];
      final j = double.tryParse(rawJumlah?.toString() ?? '');
      if (j != null) return (j / 5000).ceil() * 5000;
      final t = double.tryParse(rawTotal?.toString() ?? '') ?? 0;
      return (t / 5000).ceil() * 5000;
    })();

    final pickupTotalBiayaPdf = isPickupFaktur
        ? pickupTotalBiayaFromWorkshopInput(orderData)
        : totalFinal;

    final serviceDpAmount = isServiceOrCustom
        ? await resolveFakturDpAmount(orderData)
        : 0.0;
    final pickupDpLinePdf = isPickupFaktur
        ? (((pickupPaymentSnapshot?['dp'] ?? 0) > 0)
              ? pickupPaymentSnapshot!['dp']!
              : serviceDpAmount)
        : 0.0;
    final pickupSaldoVersusDp = isPickupFaktur
        ? (pickupTotalBiayaPdf - pickupDpLinePdf)
        : 0.0;
    final pickupDpDisplay =
        pickupDpLinePdf > 0 ? 'Rp. ${fmtMoney(pickupDpLinePdf)}' : '-';
    final serviceDpDisplay =
        serviceDpAmount > 0 ? 'Rp. ${fmtMoney(serviceDpAmount)}' : '-';
    final pickupSaldoLineLabel = !isPickupFaktur
        ? ''
        : pickupSaldoVersusDp > 0
            ? 'Kurang Bayar'
            : pickupSaldoVersusDp < 0
                ? 'Sisa Uang Muka'
                : 'Lunas';
    final pickupSaldoLineValue = !isPickupFaktur
        ? '-'
        : 'Rp. ${fmtMoney(pickupSaldoVersusDp.abs())}';
    final pickupPaymentStatusLeft = !isPickupFaktur
        ? ''
        : pickupSaldoVersusDp > 0
            ? 'Telah dibayar ke kasir'
            : pickupSaldoVersusDp < 0
                ? 'Telah dibayar ke customer'
                : 'Lunas';
    final pickupPaymentStatusRight = !isPickupFaktur
        ? ''
        : pickupSaldoVersusDp > 0
            ? 'Rp. ${fmtMoney(pickupSaldoVersusDp)}'
            : pickupSaldoVersusDp < 0
                ? 'Rp. ${fmtMoney(-pickupSaldoVersusDp)}'
                : '';

    String toTitleCase(String s) {
      final cleaned = s.trim();
      if (cleaned.isEmpty) return cleaned;
      final words = cleaned.split(RegExp(r'\s+'));
      final titled = words
          .map((w) {
            if (w.isEmpty) return w;
            final lower = w.toLowerCase();
            return lower[0].toUpperCase() + lower.substring(1);
          })
          .join(' ');
      return titled;
    }

    final terbilangText = isPickupFaktur
        ? (pickupSaldoVersusDp != 0
            ? toTitleCase(
                '${terbilang(pickupSaldoVersusDp.abs().toInt()).trim()} rupiah'
                    .trim(),
              )
            : '')
        : toTitleCase(
            '${terbilang(totalFinal.toInt()).trim()} rupiah'.trim(),
          );

    final noNota = (orderData['order_number'] ?? orderData['order_id'] ?? '-')
        .toString();
    final orderNumber = (orderData['order_number'] ?? '').toString().trim();
    final qrPayload = orderNumber.isNotEmpty
        ? orderNumber
        : (orderData['order_id'] ?? '').toString().trim();
    final tanggal = dateStr(orderData['created_at']);
    final tanggalDisplay = (() {
      final monthNames = const [
        'Januari',
        'Februari',
        'Maret',
        'April',
        'Mei',
        'Juni',
        'Juli',
        'Agustus',
        'September',
        'Oktober',
        'November',
        'Desember',
      ];
      if (isPickupFaktur) {
        final raw =
            orderData['pickup_faktur_date'] ??
            orderData['picked_up_at'] ??
            orderData['updated_at'];
        DateTime? dt;
        if (raw != null) {
          try {
            dt = DateTime.parse(raw.toString()).toLocal();
          } catch (_) {}
        }
        dt ??= DateTime.now();
        return '${dt.day.toString().padLeft(2, '0')} ${monthNames[dt.month - 1]} ${dt.year}';
      }
      try {
        final dt =
            DateTime.parse(orderData['created_at'].toString()).toLocal();
        return '${dt.day.toString().padLeft(2, '0')} ${monthNames[dt.month - 1]} ${dt.year}';
      } catch (_) {
        return tanggal.split(' ').first;
      }
    })();
    final customerName = (orderData['customer_name'] ?? '-').toString();
    final customerAddr = (orderData['customer_address'] ?? '-').toString();
    final csName =
        (orderData['created_by_name'] ??
                orderData['cs_name'] ??
                orderData['username'] ??
                '-')
            .toString();

    final idProduk =
        (orderItemSource['kode_produk'] ?? orderItemSource['item_code'] ?? '-')
            .toString();
    final idProdukWithOldNota =
        (isBuyback || isServiceOrCustom) && oldNotaReference.isNotEmpty
        ? '$idProduk (Nota lama: $oldNotaReference)'
        : idProduk;
    final deskripsi =
        (orderItemSource['deskripsi'] ??
                orderItemSource['description'] ??
                orderItemSource['nama_item'] ??
                orderItemSource['name'] ??
                '-')
            .toString();
    final kadarItem =
        (orderItemSource['purity'] ??
                orderItemSource['item_purity'] ??
                primaryItem['purity'] ??
                primaryItem['item_purity'] ??
                '')
            .toString()
            .trim();
    final deskripsiDenganKadar = kadarItem.isEmpty || kadarItem == '-'
        ? deskripsi
        : '$deskripsi ($kadarItem)';

    final qty = (orderItemSource['qty'] ?? orderItemSource['quantity'] ?? 1)
        .toString();
    final berat =
        (orderItemSource['weight'] ?? orderItemSource['berat'] ?? '-');
    final hargaPerGramOrderItemsRaw = pickFirstPositiveNumber([
      orderItemSource['harga_per_gram'],
      orderItemSource['hargaPerGram'],
      orderItemSource['harga_pergram'],
      orderItemSource['price_per_gram'],
      orderItemSource['harga_gram'],
    ]);
    final beratNum = double.tryParse(
      (orderItemSource['weight'] ?? orderItemSource['berat'] ?? '').toString(),
    );
    final totalLine = double.tryParse(
      (orderItemSource['manual_total'] ??
              orderItemSource['total'] ??
              orderItemSource['subtotal'] ??
              '')
          .toString(),
    );
    final derivedHargaPerGram =
        (hargaPerGramOrderItemsRaw == null || hargaPerGramOrderItemsRaw <= 0) &&
            beratNum != null &&
            beratNum > 0 &&
            totalLine != null &&
            totalLine > 0
        ? totalLine / beratNum
        : null;
    final hargaPerGramOrderItems = hargaPerGramOrderItemsRaw != null &&
            hargaPerGramOrderItemsRaw > 0
        ? fmtMoney(hargaPerGramOrderItemsRaw)
        : (derivedHargaPerGram != null ? fmtMoney(derivedHargaPerGram) : '-');
    final hargaPerGramOrderItemsDisplay = hargaPerGramOrderItems == '-'
        ? '-'
        : 'Rp. $hargaPerGramOrderItems';
    final kondisiBarang = <String, dynamic>{
      ...buybackConditionFallback,
      ...toMap(orderData['kondisi_barang']),
      ...toMap(primaryItem['kondisi_barang']),
    };
    final untungRugi = (kondisiBarang['untung_rugi'] ?? '-').toString();
    final kondisiFisik = (kondisiBarang['kondisi_fisik'] ?? '-').toString();
    final hargaPerGramItemConditions = fmtMoney(
      kondisiBarang['harga_per_gram'] ?? 0,
    );
    // Left block (order item) must come from order_items payload.
    final hargaAwalOrderItems = fmtMoney(
      orderItemSource['total'] ??
          orderItemSource['subtotal'] ??
          orderItemSource['jumlah'] ??
          totalFinal,
    );
    final beratSesuai = kondisiBarang['berat_akhir'] ?? '-';
    final nilaiUntungRugi = fmtMoney(kondisiBarang['nilai_untung_rugi'] ?? 0);
    final potonganKondisi = fmtMoney(kondisiBarang['potongan_kondisi'] ?? 0);
    final svcFields = fakturServiceCustomFieldRows(
      orderData,
      orderItemSource: orderItemSource,
    );
    final serviceType = svcFields['jenis_service'] ?? '-';
    final serviceAccessories = svcFields['kelengkapan'] ?? '-';
    final serviceNote = svcFields['catatan'] ?? '-';
    final serviceEstimateCost = svcFields['estimasi_biaya'] ?? '-';
    final serviceBiayaRowLabel =
        svcFields['service_biaya_row_label'] ?? 'Estimasi biaya';
    final serviceEstimatedFinish = svcFields['estimasi_selesai'] ?? '-';
    String oneLineItemName(String text) {
      final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (compact.length <= 28) return compact;
      return '${compact.substring(0, 27)}...';
    }

    String twoLineTerbilang(String text) {
      final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (compact.length <= 40) return compact;
      final cutAt = compact.lastIndexOf(' ', 40);
      if (cutAt <= 0 || cutAt >= compact.length - 1) return compact;
      return '${compact.substring(0, cutAt)}\n${compact.substring(cutAt + 1)}';
    }

    doc.addPage(
      pw.Page(
        // Use the default size from InvoicePixelPerfect: 1100 x 650
        pageFormat: PdfPageFormat(21 * PdfPageFormat.cm, 11 * PdfPageFormat.cm),
        margin: pw.EdgeInsets.all(0.5 * PdfPageFormat.cm),
        build: (ctx) {
          const designW = 1100.0;
          const designH = 650.0;
          final pageW = 21 * PdfPageFormat.cm;
          final pageH = 11 * PdfPageFormat.cm;

          // Fixed conversion (no adaptive scaling):
          // map "design pixels" -> printable area (after margins).
          final contentW = pageW - (1.0 * PdfPageFormat.cm);
          final contentH = pageH - (1.0 * PdfPageFormat.cm);
          final kx = contentW / designW;
          final ky = contentH / designH;
          double pxX(double v) => v * kx;
          double pxY(double v) => v * ky;

          pw.Widget textLine(
            String text, {
            double size = 14,
            PdfColor? color,
            pw.FontWeight? weight,
            pw.FontStyle? style,
            pw.TextAlign? align,
          }) {
            return pw.Text(
              text,
              textAlign: align,
              style: pw.TextStyle(
                fontSize: size,
                color: color,
                fontWeight: weight,
                fontStyle: style,
              ),
            );
          }

          pw.Widget detailItemText(
            String text, {
            pw.FontWeight? weight,
            pw.FontStyle? style,
            pw.TextAlign? align,
          }) {
            return pw.Text(
              text,
              textAlign: align,
              style: pw.TextStyle(
                font: pw.Font.helvetica(),
                fontSize: 10,
                fontWeight: weight,
                fontStyle: style,
                color: PdfColors.black,
              ),
            );
          }

          pw.Widget netImageOrPlaceholder({
            required Uint8List? bytes,
            required double w,
            double? h,
          }) {
            if (bytes == null) {
              return pw.Container(
                width: w,
                height: h,
                color: PdfColors.grey300,
                child: pw.Center(
                  child: pw.Text(
                    'Tidak ada foto',
                    style: pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
                  ),
                ),
              );
            }
            return pw.Image(
              pw.MemoryImage(bytes),
              width: w,
              height: h,
              fit: pw.BoxFit.cover,
            );
          }

          final background = PdfColors.grey300;
          final purple = PdfColor.fromInt(0xFF6A1B9A);
          final green = PdfColor.fromInt(0xFF2E7D32);
          final red = PdfColor.fromInt(0xFFEF2E2E);
          final footerReservedHeight = isSaleOrder ? pxY(38) : pxY(26);
          final footerBottomInset = pxY(8);

          return pw.Container(
            color: background,
            child: pw.Center(
              child: pw.Container(
                width: contentW,
                height: contentH,
                color: PdfColors.white,
                child: (() {
                  final leftWidth = pxX(740);
                  final rightWidth = contentW - leftWidth;
                  pw.Widget rightInfoLine(
                    String label,
                    String value, {
                    bool boldValue = false,
                  }) {
                    return pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 2),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.SizedBox(
                            width: pxX(96),
                            child: pw.Text(
                              label,
                              style: pw.TextStyle(fontSize: 10.5),
                            ),
                          ),
                          pw.Text(
                            ': ',
                            style: const pw.TextStyle(fontSize: 10.5),
                          ),
                          pw.SizedBox(width: pxX(4)),
                          pw.Expanded(
                            child: pw.Text(
                              value,
                              style: pw.TextStyle(fontSize: 10.5),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  pw.Widget buybackInfoLine(
                    String label,
                    String value, {
                    bool boldValue = false,
                    double labelWidthPx = 110,
                    double colonWidthPx = 8,
                    double leftInsetPx = 0,
                    bool singleLine = true,
                  }) {
                    pw.Widget lineText(String text, {pw.FontWeight? weight}) {
                      return pw.Text(
                        text,
                        maxLines: singleLine ? 1 : null,
                        overflow: singleLine
                            ? pw.TextOverflow.clip
                            : pw.TextOverflow.visible,
                        style: pw.TextStyle(
                          font: pw.Font.helvetica(),
                          fontSize: 9.5,
                          fontWeight: weight,
                          color: PdfColors.black,
                        ),
                      );
                    }

                    return pw.Padding(
                      padding: pw.EdgeInsets.only(bottom: pxY(2)),
                      child: pw.Padding(
                        padding: pw.EdgeInsets.only(left: pxX(leftInsetPx)),
                        child: pw.Row(
                          children: [
                            pw.SizedBox(
                              width: pxX(labelWidthPx),
                              child: lineText(label),
                            ),
                            pw.SizedBox(
                              width: pxX(colonWidthPx),
                              child: lineText(':'),
                            ),
                            pw.Expanded(child: lineText(value, weight: null)),
                          ],
                        ),
                      ),
                    );
                  }

                  return pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.SizedBox(
                        width: leftWidth,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                          children: [
                            pw.Padding(
                              padding: pw.EdgeInsets.fromLTRB(
                                pxX(12),
                                pxY(8),
                                pxX(12),
                                pxY(4),
                              ),
                              child: pw.Container(
                                width: double.infinity,
                                alignment: pw.Alignment.center,
                                child: branchLogoBytes == null
                                    ? pw.Container(
                                        color: PdfColors.grey100,
                                        alignment: pw.Alignment.center,
                                        child: textLine(
                                          'Logo cabang tidak ditemukan',
                                          size: 10,
                                          color: PdfColors.grey700,
                                        ),
                                      )
                                    : pw.Image(
                                        pw.MemoryImage(branchLogoBytes),
                                        width: 13.5 * PdfPageFormat.cm,
                                        fit: pw.BoxFit.contain,
                                      ),
                              ),
                            ),
                            pw.Row(
                              children: [
                                pw.Expanded(
                                  child: pw.Container(
                                    color: green,
                                    padding: pw.EdgeInsets.symmetric(
                                      vertical: pxY(5),
                                    ),
                                    child: pw.Center(
                                      child: textLine(
                                        'MENERIMA SERVIS EMAS DAN PERAK',
                                        size: 11,
                                        color: PdfColors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                pw.SizedBox(width: pxX(4)),
                                pw.SizedBox(
                                  width: pxX(300),
                                  child: pw.Container(
                                    color: purple,
                                    padding: pw.EdgeInsets.symmetric(
                                      vertical: pxY(5),
                                    ),
                                    child: pw.Center(
                                      child: textLine(
                                        'HARGA MENGIKUTI PASAR',
                                        size: 11,
                                        color: PdfColors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            isBuyback
                                ? pw.Container(
                                    // Keep buyback detail columns aligned with the
                                    // green/purple header bars above.
                                    decoration: pw.BoxDecoration(
                                      border: pw.Border.all(
                                        color: PdfColors.grey500,
                                      ),
                                    ),
                                    padding: pw.EdgeInsets.symmetric(
                                      horizontal: pxX(10),
                                      vertical: pxY(6),
                                    ),
                                    child: pw.Row(
                                      crossAxisAlignment:
                                          pw.CrossAxisAlignment.start,
                                      children: [
                                        pw.SizedBox(
                                          width:
                                              (leftWidth -
                                              pxX(20) -
                                              pxX(300) -
                                              pxX(4)),
                                          child: pw.Column(
                                            crossAxisAlignment:
                                                pw.CrossAxisAlignment.start,
                                            children: [
                                              buybackInfoLine(
                                                'ID Barang',
                                                idProdukWithOldNota,
                                                labelWidthPx: 102,
                                                colonWidthPx: 8,
                                                leftInsetPx: 6,
                                              ),
                                              buybackInfoLine(
                                                'Nama Barang',
                                                oneLineItemName(
                                                  deskripsiDenganKadar,
                                                ),
                                                labelWidthPx: 102,
                                                colonWidthPx: 8,
                                                leftInsetPx: 6,
                                              ),
                                              buybackInfoLine(
                                                'Berat',
                                                '${fmtGram(berat)} gram',
                                                labelWidthPx: 102,
                                                colonWidthPx: 8,
                                                leftInsetPx: 6,
                                              ),
                                              buybackInfoLine(
                                                'Qty',
                                                qty,
                                                labelWidthPx: 102,
                                                colonWidthPx: 8,
                                                leftInsetPx: 6,
                                              ),
                                              buybackInfoLine(
                                                'Harga/gram',
                                                hargaPerGramOrderItemsDisplay,
                                                labelWidthPx: 102,
                                                colonWidthPx: 8,
                                                leftInsetPx: 6,
                                              ),
                                              buybackInfoLine(
                                                'Harga awal',
                                                'Rp. $hargaAwalOrderItems',
                                                labelWidthPx: 102,
                                                colonWidthPx: 8,
                                                leftInsetPx: 6,
                                              ),
                                            ],
                                          ),
                                        ),
                                        pw.SizedBox(width: pxX(4)),
                                        pw.SizedBox(
                                          width: pxX(300),
                                          child: pw.Column(
                                            crossAxisAlignment:
                                                pw.CrossAxisAlignment.start,
                                            children: [
                                              buybackInfoLine(
                                                'Untung/Rugi',
                                                untungRugi,
                                                leftInsetPx: 12,
                                              ),
                                              buybackInfoLine(
                                                'Kondisi',
                                                kondisiFisik,
                                                leftInsetPx: 12,
                                              ),
                                              buybackInfoLine(
                                                'Harga/gram',
                                                'Rp. $hargaPerGramItemConditions',
                                                leftInsetPx: 12,
                                              ),
                                              buybackInfoLine(
                                                'Berat sesuai',
                                                '${fmtGram(beratSesuai)} gram',
                                                leftInsetPx: 12,
                                              ),
                                              buybackInfoLine(
                                                'Keuntungan',
                                                'Rp. $nilaiUntungRugi',
                                                leftInsetPx: 12,
                                              ),
                                              buybackInfoLine(
                                                'Pot. Kondisi',
                                                'Rp. $potonganKondisi',
                                                leftInsetPx: 12,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : isServiceOrCustom
                                ? pw.Container(
                                    decoration: pw.BoxDecoration(
                                      border: pw.Border.all(
                                        color: PdfColors.grey500,
                                      ),
                                    ),
                                    padding: pw.EdgeInsets.symmetric(
                                      horizontal: pxX(10),
                                      vertical: pxY(6),
                                    ),
                                    child: pw.Row(
                                      crossAxisAlignment:
                                          pw.CrossAxisAlignment.start,
                                      children: [
                                        pw.SizedBox(
                                          width:
                                              (leftWidth -
                                              pxX(20) -
                                              pxX(300) -
                                              pxX(4)),
                                          child: pw.Column(
                                            crossAxisAlignment:
                                                pw.CrossAxisAlignment.start,
                                            children: [
                                              buybackInfoLine(
                                                'ID Barang',
                                                idProdukWithOldNota,
                                                labelWidthPx: 102,
                                                colonWidthPx: 8,
                                                leftInsetPx: 6,
                                              ),
                                              buybackInfoLine(
                                                'Nama Barang',
                                                oneLineItemName(
                                                  deskripsiDenganKadar,
                                                ),
                                                labelWidthPx: 102,
                                                colonWidthPx: 8,
                                                leftInsetPx: 6,
                                              ),
                                              buybackInfoLine(
                                                'Berat',
                                                '${fmtGram(berat)} gram',
                                                labelWidthPx: 102,
                                                colonWidthPx: 8,
                                                leftInsetPx: 6,
                                              ),
                                              buybackInfoLine(
                                                'Qty',
                                                qty,
                                                labelWidthPx: 102,
                                                colonWidthPx: 8,
                                                leftInsetPx: 6,
                                              ),
                                              buybackInfoLine(
                                                'Harga/gram',
                                                hargaPerGramOrderItemsDisplay,
                                                labelWidthPx: 102,
                                                colonWidthPx: 8,
                                                leftInsetPx: 6,
                                              ),
                                            ],
                                          ),
                                        ),
                                        pw.SizedBox(width: pxX(4)),
                                        pw.SizedBox(
                                          width: pxX(300),
                                          child: pw.Column(
                                            crossAxisAlignment:
                                                pw.CrossAxisAlignment.start,
                                            children: [
                                              buybackInfoLine(
                                                'Jenis Service',
                                                serviceType,
                                                leftInsetPx: 12,
                                              ),
                                              buybackInfoLine(
                                                'Kelengkapan',
                                                serviceAccessories,
                                                leftInsetPx: 12,
                                              ),
                                              buybackInfoLine(
                                                'Catatan Service',
                                                serviceNote,
                                                leftInsetPx: 12,
                                              ),
                                              buybackInfoLine(
                                                isPickupFaktur
                                                    ? 'Total Biaya'
                                                    : serviceBiayaRowLabel,
                                                isPickupFaktur
                                                    ? 'Rp. ${fmtMoney(pickupTotalBiayaPdf)}'
                                                    : serviceEstimateCost,
                                                leftInsetPx: 12,
                                              ),
                                              buybackInfoLine(
                                                'Uang Muka (DP)',
                                                isPickupFaktur
                                                    ? pickupDpDisplay
                                                    : serviceDpDisplay,
                                                leftInsetPx: 12,
                                              ),
                                              if (isPickupFaktur)
                                                buybackInfoLine(
                                                  pickupSaldoLineLabel,
                                                  pickupSaldoLineValue,
                                                  leftInsetPx: 12,
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : isSaleOrder
                                ? pw.Container(
                                    decoration: pw.BoxDecoration(
                                      border: pw.Border(
                                        top: pw.BorderSide(
                                          color: PdfColors.grey500,
                                        ),
                                        bottom: pw.BorderSide(
                                          color: PdfColors.grey500,
                                        ),
                                      ),
                                    ),
                                    child: pw.Column(
                                      children: [
                                        pw.Padding(
                                          padding: pw.EdgeInsets.symmetric(
                                            horizontal: pxX(8),
                                            vertical: pxY(4),
                                          ),
                                          child: pw.Row(
                                            children: [
                                              pw.SizedBox(
                                                width: pxX(42),
                                                child: detailItemText(
                                                  'Qty',
                                                  align: pw.TextAlign.center,
                                                ),
                                              ),
                                              pw.SizedBox(
                                                width: pxX(132),
                                                child: detailItemText(
                                                  'ID Barang',
                                                  align: pw.TextAlign.left,
                                                ),
                                              ),
                                              pw.Expanded(
                                                child: detailItemText(
                                                  'Nama Barang',
                                                  align: pw.TextAlign.center,
                                                ),
                                              ),
                                              pw.SizedBox(
                                                width: pxX(114),
                                                child: detailItemText(
                                                  'Berat',
                                                  align: pw.TextAlign.center,
                                                ),
                                              ),
                                              pw.SizedBox(
                                                width: pxX(128),
                                                child: detailItemText(
                                                  'Harga/gram',
                                                  align: pw.TextAlign.center,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        pw.Container(
                                          height: 0.8,
                                          color: PdfColors.grey500,
                                        ),
                                        pw.Padding(
                                          padding: pw.EdgeInsets.symmetric(
                                            horizontal: pxX(8),
                                            vertical: pxY(5),
                                          ),
                                          child: pw.Row(
                                            children: [
                                              pw.SizedBox(
                                                width: pxX(42),
                                                child: detailItemText(
                                                  qty,
                                                  align: pw.TextAlign.center,
                                                ),
                                              ),
                                              pw.SizedBox(
                                                width: pxX(132),
                                                child: detailItemText(
                                                  idProdukWithOldNota,
                                                  align: pw.TextAlign.left,
                                                ),
                                              ),
                                              pw.Expanded(
                                                child: detailItemText(
                                                  deskripsiDenganKadar,
                                                  align: pw.TextAlign.left,
                                                ),
                                              ),
                                              pw.SizedBox(
                                                width: pxX(114),
                                                child: detailItemText(
                                                  '${fmtGram(berat)} gram',
                                                  align: pw.TextAlign.center,
                                                ),
                                              ),
                                              pw.SizedBox(
                                                width: pxX(128),
                                                child: detailItemText(
                                                  hargaPerGramOrderItemsDisplay,
                                                  align: pw.TextAlign.center,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : pw.Container(
                                    decoration: pw.BoxDecoration(
                                      border: pw.Border.all(
                                        color: PdfColors.grey500,
                                      ),
                                    ),
                                    child: pw.Column(
                                      children: [
                                        pw.Padding(
                                          padding: pw.EdgeInsets.symmetric(
                                            horizontal: pxX(8),
                                            vertical: pxY(4),
                                          ),
                                          child: pw.Row(
                                            children: [
                                              pw.SizedBox(
                                                width: pxX(38),
                                                child: detailItemText(
                                                  'Qty',
                                                  align: pw.TextAlign.center,
                                                ),
                                              ),
                                              pw.SizedBox(
                                                width:
                                                    (isServiceOrCustom &&
                                                        oldNotaReference
                                                            .isNotEmpty)
                                                    ? pxX(190)
                                                    : pxX(62),
                                                child: pw.Transform.translate(
                                                  offset: PdfPoint(pxX(6), 0),
                                                  child: detailItemText(
                                                    'ID',
                                                    align: pw.TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                              pw.SizedBox(width: pxX(6)),
                                              pw.Expanded(
                                                child: detailItemText(
                                                  'Nama Barang',
                                                  align: pw.TextAlign.center,
                                                ),
                                              ),
                                              pw.SizedBox(
                                                width: pxX(105),
                                                child: pw.Transform.translate(
                                                  offset: PdfPoint(-pxX(8), 0),
                                                  child: detailItemText(
                                                    'Berat',
                                                    align: pw.TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                              pw.SizedBox(
                                                width: pxX(115),
                                                child: detailItemText(
                                                  'Harga/gram',
                                                  align: pw.TextAlign.center,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        pw.Container(
                                          height: 0.8,
                                          color: PdfColors.grey500,
                                        ),
                                        pw.Padding(
                                          padding: pw.EdgeInsets.symmetric(
                                            horizontal: pxX(8),
                                            vertical: pxY(5),
                                          ),
                                          child: pw.Row(
                                            children: [
                                              pw.SizedBox(
                                                width: pxX(38),
                                                child: detailItemText(
                                                  qty,
                                                  align: pw.TextAlign.center,
                                                ),
                                              ),
                                              pw.SizedBox(
                                                width:
                                                    (isServiceOrCustom &&
                                                        oldNotaReference
                                                            .isNotEmpty)
                                                    ? pxX(190)
                                                    : pxX(62),
                                                child: pw.Transform.translate(
                                                  offset: PdfPoint(pxX(6), 0),
                                                  child: detailItemText(
                                                    idProdukWithOldNota,
                                                    align: pw.TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                              pw.SizedBox(width: pxX(6)),
                                              pw.Expanded(
                                                child: detailItemText(
                                                  deskripsiDenganKadar,
                                                  align: pw.TextAlign.center,
                                                ),
                                              ),
                                              pw.SizedBox(
                                                width: pxX(105),
                                                child: pw.Transform.translate(
                                                  offset: PdfPoint(-pxX(8), 0),
                                                  child: detailItemText(
                                                    '${fmtGram(berat)} gram',
                                                    align: pw.TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                              pw.SizedBox(
                                                width: pxX(115),
                                                child: detailItemText(
                                                  hargaPerGramOrderItemsDisplay,
                                                  align: pw.TextAlign.center,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                            if (isServiceOrCustom)
                              pw.Padding(
                                padding: pw.EdgeInsets.fromLTRB(
                                  0,
                                  pxY(4),
                                  0,
                                  pxY(2),
                                ),
                                child: pw.Column(
                                  children: [
                                    pw.Container(
                                      height: 0.8,
                                      color: PdfColors.grey500,
                                    ),
                                    pw.SizedBox(height: pxY(2)),
                                    if (isPickupFaktur && pickupSaldoVersusDp == 0)
                                      pw.Center(child: detailItemText('Lunas'))
                                    else
                                      pw.Row(
                                        mainAxisAlignment:
                                            pw.MainAxisAlignment.center,
                                        children: [
                                          if (isPickupFaktur) ...[
                                            detailItemText(
                                              pickupPaymentStatusLeft,
                                            ),
                                            pw.SizedBox(width: pxX(10)),
                                            detailItemText(
                                              pickupPaymentStatusRight,
                                            ),
                                          ] else ...[
                                            detailItemText('Estimasi Selesai'),
                                            pw.SizedBox(width: pxX(10)),
                                            detailItemText(
                                              serviceEstimatedFinish,
                                            ),
                                          ],
                                        ],
                                      ),
                                    pw.SizedBox(height: pxY(2)),
                                    pw.Container(
                                      height: 0.8,
                                      color: PdfColors.grey500,
                                    ),
                                    pw.SizedBox(height: pxY(2)),
                                    if (!isPickupFaktur)
                                      pw.Center(
                                        child: detailItemText(
                                          'KALAU AMBIL BAWA BUKTI ORDER INI, TIDAK BAWA TIDAK DILAYANI',
                                        ),
                                      ),
                                    if (isPickupFaktur &&
                                        terbilangText.isNotEmpty) ...[
                                      pw.SizedBox(height: pxY(6)),
                                      pw.Padding(
                                        padding: pw.EdgeInsets.symmetric(
                                          horizontal: pxX(8),
                                        ),
                                        child: detailItemText(
                                          'Terbilang : $terbilangText',
                                          style: pw.FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              )
                            else if (isSaleOrder)
                              pw.Padding(
                                padding: pw.EdgeInsets.fromLTRB(
                                  pxX(8),
                                  pxY(3),
                                  pxX(8),
                                  pxY(2),
                                ),
                                child: pw.Row(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Expanded(
                                      child: pw.Text(
                                        'Terbilang : ${twoLineTerbilang(terbilangText)}',
                                        maxLines: 2,
                                        overflow: pw.TextOverflow.clip,
                                        style: pw.TextStyle(
                                          font: pw.Font.helvetica(),
                                          fontSize: 10,
                                          fontStyle: pw.FontStyle.italic,
                                          color: PdfColors.black,
                                          height: 1.15,
                                        ),
                                      ),
                                    ),
                                    pw.SizedBox(width: pxX(10)),
                                    pw.SizedBox(
                                      width: pxX(260),
                                      child: pw.Row(
                                        crossAxisAlignment:
                                            pw.CrossAxisAlignment.center,
                                        mainAxisAlignment:
                                            pw.MainAxisAlignment.spaceBetween,
                                        children: [
                                          pw.Text(
                                            'TOTAL',
                                            style: pw.TextStyle(
                                              font: pw.Font.helvetica(),
                                              fontSize: 11.5,
                                              color: PdfColors.black,
                                            ),
                                          ),
                                          pw.Text(
                                            'Rp. ${fmtMoney(totalFinal)}',
                                            style: pw.TextStyle(
                                              font: pw.Font.helvetica(),
                                              fontSize: 11.5,
                                              color: PdfColors.black,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              pw.Padding(
                                padding: pw.EdgeInsets.fromLTRB(
                                  0,
                                  pxY(4),
                                  pxX(8),
                                  pxY(2),
                                ),
                                child: pw.Row(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.center,
                                  children: [
                                    pw.Expanded(
                                      child: pw.Column(
                                        crossAxisAlignment:
                                            pw.CrossAxisAlignment.start,
                                        children: [
                                          detailItemText(
                                            'Terbilang : $terbilangText',
                                            style: pw.FontStyle.italic,
                                          ),
                                        ],
                                      ),
                                    ),
                                    pw.SizedBox(width: pxX(14)),
                                    pw.Row(
                                      crossAxisAlignment:
                                          pw.CrossAxisAlignment.center,
                                      children: [
                                        pw.Text(
                                          'TOTAL',
                                          style: pw.TextStyle(
                                            font: pw.Font.helvetica(),
                                            fontSize: 10,
                                            color: PdfColors.black,
                                          ),
                                        ),
                                        pw.SizedBox(width: pxX(14)),
                                        pw.Text(
                                          'Rp. ${fmtMoney(totalFinal)}',
                                          style: pw.TextStyle(
                                            font: pw.Font.helvetica(),
                                            fontSize: 10,
                                            color: PdfColors.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            pw.Container(height: 0.8, color: PdfColors.grey500),
                            pw.Expanded(
                              child: pw.Stack(
                                children: [
                                  pw.Positioned.fill(
                                    child: pw.Padding(
                                      padding: pw.EdgeInsets.only(
                                        top: isSaleOrder ? pxY(2) : pxY(6),
                                        bottom:
                                            footerBottomInset +
                                            footerReservedHeight +
                                            pxY(6),
                                      ),
                                      child: pw.Column(
                                        mainAxisAlignment: isSaleOrder
                                            ? pw.MainAxisAlignment.start
                                            : pw.MainAxisAlignment.end,
                                        children: [
                                          if (isSaleOrder)
                                            pw.Container(
                                              color: red,
                                              padding: pw.EdgeInsets.symmetric(
                                                vertical: pxY(3),
                                              ),
                                              child: pw.Center(
                                                child: pw.Text(
                                                  'KALAU MENJUAL HARUS BAWA NOTA INI, BARANG RUSAK LAIN HARGA',
                                                  style: pw.TextStyle(
                                                    font: pw.Font.helvetica(),
                                                    fontSize: 10,
                                                    color: PdfColors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          // Keep sale warning banner slightly higher
                                          // from signature block.
                                          pw.SizedBox(
                                            height: isSaleOrder
                                                ? pxY(3)
                                                : pxY(2),
                                          ),
                                          pw.Row(
                                            crossAxisAlignment:
                                                pw.CrossAxisAlignment.start,
                                            children: [
                                              pw.Expanded(
                                                child: pw.Padding(
                                                  padding: pw.EdgeInsets.only(
                                                    right: isSaleOrder
                                                        ? pxX(118)
                                                        : pxX(108),
                                                  ),
                                                  child: pw.Column(
                                                    children: [
                                                      textLine(
                                                        isBuyback
                                                            ? 'Telah diperiksa, diserahkan dan dibayar'
                                                            : 'Telah diperiksa, dibayar dan diserahkan',
                                                        size: 10,
                                                      ),
                                                      pw.SizedBox(
                                                        height: isSaleOrder
                                                            ? pxY(4)
                                                            : pxY(5),
                                                      ),
                                                      pw.Row(
                                                        mainAxisAlignment: pw
                                                            .MainAxisAlignment
                                                            .spaceAround,
                                                        children: [
                                                          detailItemText(
                                                            'Kasir',
                                                          ),
                                                          detailItemText('CS'),
                                                          detailItemText(
                                                            'Customer',
                                                          ),
                                                        ],
                                                      ),
                                                      pw.SizedBox(
                                                        // Taller signature area.
                                                        height: isSaleOrder
                                                            ? pxY(24)
                                                            : pxY(26),
                                                      ),
                                                      pw.Row(
                                                        mainAxisAlignment: pw
                                                            .MainAxisAlignment
                                                            .spaceAround,
                                                        children: [
                                                          detailItemText(
                                                            '-',
                                                            style: pw
                                                                .FontStyle
                                                                .italic,
                                                          ),
                                                          detailItemText(
                                                            csName,
                                                          ),
                                                          detailItemText(
                                                            customerName,
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  pw.Positioned(
                                    right: pxX(8),
                                    bottom:
                                        footerBottomInset +
                                        footerReservedHeight +
                                        (isSaleOrder ? pxY(8) : pxY(6)),
                                    child: pw.Container(
                                      width: pxX(100),
                                      height: pxX(100),
                                      decoration: pw.BoxDecoration(
                                        color: PdfColors.white,
                                      ),
                                      child: qrPayload.isEmpty
                                          ? pw.Center(
                                              child: detailItemText('QR'),
                                            )
                                          : pw.Padding(
                                              padding: const pw.EdgeInsets.all(
                                                4,
                                              ),
                                              child: pw.BarcodeWidget(
                                                barcode: pw.Barcode.qrCode(),
                                                data: qrPayload,
                                              ),
                                            ),
                                    ),
                                  ),
                                  pw.Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: footerBottomInset,
                                    child: pw.Container(
                                      color: green,
                                      padding: pw.EdgeInsets.symmetric(
                                        vertical: pxY(4),
                                      ),
                                      child: pw.Center(
                                        child: pw.Text(
                                          'SEMOGA ANDA TETAP MENJADI PELANGGAN SETIA KAMI',
                                          style: pw.TextStyle(
                                            font: pw.Font.helvetica(),
                                            fontSize: 10,
                                            color: PdfColors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(
                        width: rightWidth,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                          children: [
                            pw.Container(
                              color: isBuyback
                                  ? green
                                  : (isServiceOrCustom ? purple : red),
                              padding: pw.EdgeInsets.symmetric(
                                vertical: pxY(8),
                              ),
                              child: pw.Center(
                                child: pw.Text(
                                  isPickupFaktur
                                      ? (isCustomOrder
                                            ? 'AMBIL CUSTOM'
                                            : 'AMBIL SERVICE')
                                      : (isCustomOrder
                                            ? 'ORDER CUSTOM'
                                            : (isServiceOrder
                                                  ? 'ORDER SERVICE'
                                                  : transactionLabel)),
                                  maxLines: 1,
                                  softWrap: false,
                                  style: pw.TextStyle(
                                    font: pw.Font.helvetica(),
                                    fontSize: isServiceOrCustom ? 13 : 12,
                                    color: PdfColors.white,
                                  ),
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: pw.EdgeInsets.fromLTRB(
                                pxX(10),
                                pxY(8),
                                pxX(10),
                                pxY(6),
                              ),
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  rightInfoLine('No. Nota', noNota),
                                  rightInfoLine('Tanggal', tanggalDisplay),
                                  rightInfoLine('Customer', customerName),
                                  rightInfoLine('Alamat', customerAddr),
                                ],
                              ),
                            ),
                            pw.Expanded(
                              child: netImageOrPlaceholder(
                                bytes: primaryPhotoBytes,
                                w: rightWidth,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                })(),
              ),
            ),
          );
        },
      ),
    );

    final filename = isPickupFaktur
        ? 'faktur_ambil_${orderData['order_number'] ?? orderData['order_id'] ?? 'order'}.pdf'
        : 'faktur_${orderData['order_number'] ?? orderData['order_id'] ?? 'order'}.pdf';
    final pdfBytes = await doc.save();
    try {
      final info = await Printing.info();
      if (info.canPrint) {
        await Printing.layoutPdf(
          name: filename,
          onLayout: (format) async => pdfBytes,
        );
      } else {
        await Printing.sharePdf(bytes: pdfBytes, filename: filename);
      }
    } catch (_) {
      // Fallback for devices/emulators without stable print service.
      await Printing.sharePdf(bytes: pdfBytes, filename: filename);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal mencetak: $e')));
    }
  }
}
