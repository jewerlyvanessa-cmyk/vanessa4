import 'dart:convert';

Map<String, dynamic> fakturMetadataMap(Map<String, dynamic> orderData) {
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

double pickupTotalBiayaFromWorkshopInput(Map<String, dynamic> orderData) {
  final meta = fakturMetadataMap(orderData);
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

double fakturDpFromPayloadSync(Map<String, dynamic> orderData) {
  final type = (orderData['order_type'] ?? '').toString().trim().toLowerCase();
  if (type != 'service' && type != 'custom') return 0;
  final metadata = fakturMetadataMap(orderData);
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

/// Field servis/custom untuk faktur layar & PDF.
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
  final metadata = fakturMetadataMap(orderData);
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
  final hasFinalWorkshopCost = rev != null && rev > 0;

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
  final estimasiBiaya = estNum != null ? fmtMoneyOrDashEst(estNum) : '-';

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
