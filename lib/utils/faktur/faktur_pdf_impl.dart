import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vanessa3/utils/branch_logo_pdf.dart';
import 'package:vanessa3/utils/pdf_print_delivery.dart';
import 'package:vanessa3/utils/faktur/faktur_constants.dart';
import 'package:vanessa3/utils/faktur/faktur_image_fetch.dart';
import 'package:vanessa3/utils/faktur/faktur_metadata.dart';
import 'package:vanessa3/utils/faktur/faktur_payment_api.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/pdf_fonts.dart';
import 'package:vanessa3/utils/terbilang.dart';

Future<void> printFakturOrderImpl(
  BuildContext context,
  Map<String, dynamic> orderData, {
  FakturPrintKind kind = FakturPrintKind.orderTransaction,
}) async {
  try {
    await PdfFonts.ensureLoaded();
    final items = orderData['items'] as List<dynamic>? ?? [];
    final doc = pw.Document(theme: PdfFonts.theme);

    String? branchLogoUrlFromOrderData(Map<String, dynamic> data) {
      for (final raw in [
        data['logo_url'],
        data['branch_logo_url'],
        data['branchLogoUrl'],
      ]) {
        final url = fakturPhotoAbsoluteUrl(raw);
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
          final url = fakturPhotoAbsoluteUrl(raw);
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

    /// Sumber logo sama dengan layar Manajemen Cabang (`branches.logo_url` via GET /branches/:id).
    /// Jika `GET /orders?...` tidak menyisipkan logo (join gagal / payload lama), isi dari API cabang.
    Future<void> hydrateBranchLogoFromBranchesApiIfMissing() async {
      if (branchLogoUrlFromOrderData(orderData) != null) return;
      final cachedBranches = orderData[kFakturBranchesKey];
      if (cachedBranches is List) {
        for (final bid in orderedBranchIdsForLogo()) {
          if (bid.isEmpty) continue;
          for (final raw in cachedBranches) {
            if (raw is! Map) continue;
            final m = Map<String, dynamic>.from(raw);
            if (m['branch_id']?.toString() != bid) continue;
            final s = m['logo_url']?.toString().trim() ?? '';
            if (s.isEmpty) continue;
            orderData['logo_url'] = s;
            orderData['branch_logo_url'] = s;
            return;
          }
        }
      }
      for (final bid in orderedBranchIdsForLogo()) {
        if (bid.isEmpty) continue;
        try {
          final resp = await http
              .get(
                Uri.parse('${NetworkConfig.baseUrl}/branches/$bid'),
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

      List<dynamic> decoded = const [];
      final cachedConds = orderData[kFakturItemConditionsKey];
      if (cachedConds is List && cachedConds.isNotEmpty) {
        decoded = cachedConds;
      } else {
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
          final body = jsonDecode(resp.body);
          if (body is! List || body.isEmpty) {
            return const <String, dynamic>{};
          }
          decoded = body;
        } catch (_) {
          return const <String, dynamic>{};
        }
      }

      try {
        if (decoded.isEmpty) {
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
    final isPickupFaktur = kind == FakturPrintKind.pickup && isServiceOrCustom;
    Map<String, double>? pickupPaymentSnapshot;
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
    await hydrateBranchLogoFromBranchesApiIfMissing();
    final logoBranchId = () {
      for (final id in orderedBranchIdsForLogo()) {
        if (id.isNotEmpty) return id;
      }
      return '';
    }();

    final prefetchPhase1 = await Future.wait<dynamic>([
      () async {
        final cached = fakturPaymentSummaryFromOrderData(orderData);
        if (cached != null) return cached;
        if (!isPickupFaktur) return null;
        return fetchPaymentSummaryForPickupFaktur(
          orderData['order_id']?.toString() ?? '',
        );
      }(),
      fetchOrderItemFromOldNota(
        isBuyback: isBuyback,
        fallbackItem: primaryItem,
      ),
      logoBranchId.isNotEmpty
          ? loadBranchLogoRasterBytesForPdf(logoBranchId)
          : Future<Uint8List?>.value(null),
    ]);
    pickupPaymentSnapshot = prefetchPhase1[0] as Map<String, double>?;
    final orderItemSource =
        prefetchPhase1[1] as Map<String, dynamic>? ?? primaryItem;
    final branchLogoBytes = prefetchPhase1[2] as Uint8List?;

    final primaryPhotoUrlResolved = (() {
      for (final raw in [
        orderItemSource['photo_produk'],
        orderItemSource['photo_url'],
        orderItemSource['item_photo_produk'],
        orderItemSource['item_photo_url'],
        primaryItem['photo_produk'],
        primaryItem['photo_url'],
      ]) {
        final u = fakturPhotoAbsoluteUrl(raw);
        if (u != null && u.isNotEmpty) return u;
      }
      return null;
    })();

    final prefetchPhase2 = await Future.wait([
      primaryPhotoUrlResolved == null
          ? Future<Uint8List?>.value(null)
          : fakturFetchBytes(
              primaryPhotoUrlResolved,
              imageBinary: true,
              timeout: const Duration(seconds: 5),
            ),
      fetchBuybackConditionFallback(isBuyback: isBuyback, item: primaryItem),
    ]);
    final primaryPhotoBytes = prefetchPhase2[0] as Uint8List?;
    final buybackConditionFallback = prefetchPhase2[1] as Map<String, dynamic>;

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
    final pickupDpDisplay = pickupDpLinePdf > 0
        ? 'Rp. ${fmtMoney(pickupDpLinePdf)}'
        : '-';
    final serviceDpDisplay = serviceDpAmount > 0
        ? 'Rp. ${fmtMoney(serviceDpAmount)}'
        : '-';
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
        : toTitleCase('${terbilang(totalFinal.toInt()).trim()} rupiah'.trim());

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
        final dt = DateTime.parse(orderData['created_at'].toString()).toLocal();
        return '${dt.day.toString().padLeft(2, '0')} ${monthNames[dt.month - 1]} ${dt.year}';
      } catch (_) {
        return tanggal.split(' ').first;
      }
    })();
    final customerName = (orderData['customer_name'] ?? '-').toString();
    final customerAddr = (orderData['customer_address'] ?? '-').toString();
    final csName = fakturCsDisplayName(orderData);

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
    final hargaPerGramOrderItems =
        hargaPerGramOrderItemsRaw != null && hargaPerGramOrderItemsRaw > 0
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
        // Desain InvoicePixelPerfect 1100×650 — skala ke lebar 21 cm × panjang 11 cm.
        pageFormat: kFakturPageFormat,
        build: (ctx) {
          const designW = 1100.0;
          const designH = 650.0;
          final pageW = kFakturLebarCm * PdfPageFormat.cm;
          final pageH = kFakturPanjangCm * PdfPageFormat.cm;
          final margin = 0.5 * PdfPageFormat.cm;

          // Fixed conversion (no adaptive scaling):
          // map "design pixels" -> printable area (after margins).
          final contentW = pageW - (2 * margin);
          final contentH = pageH - (2 * margin);
          final kx = contentW / designW;
          final ky = contentH / designH;
          double pxX(double v) => v * kx;
          double pxY(double v) => v * ky;

          pw.Widget textLine(
            String text, {
            double size = 12,
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
                              style: pw.TextStyle(fontSize: 10),
                            ),
                          ),
                          pw.Text(
                            ': ',
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                          pw.SizedBox(width: pxX(4)),
                          pw.Expanded(
                            child: pw.Text(
                              value,
                              style: pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  pw.Widget buybackInfoLine(
                    String label,
                    String value, {
                    bool boldValue = true,
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
                          fontSize: 9,
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
                                        weight: pw.FontWeight.bold,
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
                                        weight: pw.FontWeight.bold,
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
                                                  align: pw.TextAlign.center,
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
                                                  align: pw.TextAlign.center,
                                                ),
                                              ),
                                              pw.Expanded(
                                                child: detailItemText(
                                                  deskripsiDenganKadar,
                                                  align: pw.TextAlign.center,
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
                                    if (isPickupFaktur &&
                                        pickupSaldoVersusDp == 0)
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
                                          weight: pw.FontWeight.bold,
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
                                          'Terbilang : \n'
                                          '$terbilangText',
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
                                        'Terbilang : '
                                        '${twoLineTerbilang(terbilangText)}',
                                        maxLines: 2,
                                        overflow: pw.TextOverflow.clip,
                                        style: pw.TextStyle(
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
                                              fontSize: 10,
                                              color: PdfColors.black,
                                              fontWeight: pw.FontWeight.bold,
                                            ),
                                          ),
                                          pw.Text(
                                            'Rp. ${fmtMoney(totalFinal)}',
                                            style: pw.TextStyle(
                                              fontSize: 10,
                                              color: PdfColors.black,
                                              fontWeight: pw.FontWeight.bold,
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
                                            'Terbilang : \n'
                                            '$terbilangText',
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
                                            fontSize: 10,
                                            color: PdfColors.black,
                                          ),
                                        ),
                                        pw.SizedBox(width: pxX(14)),
                                        pw.Text(
                                          'Rp. ${fmtMoney(totalFinal)}',
                                          style: pw.TextStyle(
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
                                                    fontSize: 10.5,
                                                    color: PdfColors.white,
                                                    fontWeight:
                                                        pw.FontWeight.bold,
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
                                                        : pxX(100),
                                                  ),
                                                  child: pw.Column(
                                                    children: [
                                                      textLine(
                                                        isBuyback
                                                            ? 'Telah diperiksa, diserahkan dan dibayar'
                                                            : 'Telah diperiksa, dibayar dan diserahkan',
                                                        size: 8.5,
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
                                                            ? pxY(18)
                                                            : pxY(20),
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
                                    bottom: 0,
                                    child: pw.Container(
                                      width: pxX(120),
                                      height: pxX(120),
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
                                    right: 70,
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
                                            fontSize: 11,
                                            color: PdfColors.white,
                                            fontWeight: pw.FontWeight.bold,
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
                                    fontSize: isServiceOrCustom ? 13 : 12,
                                    color: PdfColors.white,
                                    fontWeight: pw.FontWeight.bold,
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
    if (!context.mounted) return;
    await deliverPdfDocument(
      context,
      pdfBytes: pdfBytes,
      filename: filename,
      format: kFakturPageFormat,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal mencetak: $e')));
    }
  }
}
