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

/// Builds a simple invoice PDF and opens the system print / share UI.
Future<void> printFakturOrder(
  BuildContext context,
  Map<String, dynamic> orderData,
) async {
  try {
    final items = orderData['items'] as List<dynamic>? ?? [];
    final doc = pw.Document();

    String? photoUrl(dynamic raw) {
      final s = raw?.toString().trim();
      if (s == null || s.isEmpty) return null;
      if (s.startsWith('http://') || s.startsWith('https://')) return s;
      if (s.startsWith('/')) return '${NetworkConfig.baseUrl}$s';
      return '${NetworkConfig.baseUrl}/uploads/$s';
    }

    Future<Uint8List?> fetchBytes(
      String? url, {
      Duration timeout = const Duration(seconds: 3),
    }) async {
      if (url == null) return null;
      final cached = _imageByteCache[url];
      if (cached != null) return cached;
      try {
        final resp = await http.get(Uri.parse(url)).timeout(timeout);
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          // Keep cache lightweight and avoid unbounded growth.
          if (_imageByteCache.length > 40) {
            _imageByteCache.remove(_imageByteCache.keys.first);
          }
          _imageByteCache[url] = resp.bodyBytes;
          return resp.bodyBytes;
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
      final raw = data['branch_id'] ?? data['branchId'] ?? data['branch'];
      final s = raw?.toString().trim();
      return s ?? '';
    }

    Future<String?> fetchBranchLogoUrl() async {
      final branchId = branchIdFromOrderData(orderData);
      if (branchId.isEmpty) return null;
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
      return null;
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
    final shouldResolveFromOldNota = isBuyback || isServiceOrder;
    final orderItemSource = await fetchOrderItemFromOldNota(
      isBuyback: shouldResolveFromOldNota,
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
    final branchLogoUrlFast = branchLogoUrlFromOrderData(orderData);
    final fetchedBytes = await Future.wait<Uint8List?>([
      (() async {
        final direct = await fetchBytes(branchLogoUrlFast);
        if (direct != null) return direct;
        final fallbackUrl = await fetchBranchLogoUrl();
        return fetchBytes(fallbackUrl);
      })(),
      fetchBytes(primaryPhotoUrl),
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

    final terbilangText = toTitleCase(
      '${terbilang(totalFinal.toInt()).trim()} rupiah'.trim(),
    );

    final noNota = (orderData['order_number'] ?? orderData['order_id'] ?? '-')
        .toString();
    final orderNumber = (orderData['order_number'] ?? '').toString().trim();
    final tanggal = dateStr(orderData['created_at']);
    final tanggalDisplay = (() {
      try {
        final dt = DateTime.parse(orderData['created_at'].toString()).toLocal();
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
        (isBuyback || isServiceOrder) && oldNotaReference.isNotEmpty
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
    final hargaPerGramOrderItems = hargaPerGramOrderItemsRaw == null
        ? '-'
        : fmtMoney(hargaPerGramOrderItemsRaw);
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
    String pickFirstText(List<dynamic> candidates, {String fallback = '-'}) {
      for (final c in candidates) {
        final s = (c ?? '').toString().trim();
        if (s.isNotEmpty && s != '-' && s.toUpperCase() != 'NULL') return s;
      }
      return fallback;
    }

    String fmtMoneyOrDash(dynamic v) {
      final d = double.tryParse(v?.toString() ?? '');
      if (d == null || d <= 0) return '-';
      return 'Rp. ${fmtMoney(v)}';
    }

    String formatLongDate(dynamic raw) {
      final s = (raw ?? '').toString().trim();
      if (s.isEmpty || s == '-') return '-';
      try {
        final dt = DateTime.parse(s).toLocal();
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
        return '${dt.day.toString().padLeft(2, '0')} ${monthNames[dt.month - 1]} ${dt.year}';
      } catch (_) {
        return s;
      }
    }

    final serviceType = pickFirstText([
      orderData['jenis_service'],
      orderData['service_type'],
      metadata['jenis_service'],
      metadata['service_type'],
      orderConditionMap['jenis_service'],
      orderConditionMap['service_type'],
    ]);
    final serviceAccessories = pickFirstText([
      orderData['kelengkapan'],
      orderData['barang_bawaan'],
      metadata['kelengkapan'],
      metadata['barang_bawaan'],
      orderConditionMap['kelengkapan'],
      orderConditionMap['barang_bawaan'],
    ]);
    final serviceNote = pickFirstText([
      orderData['catatan_service'],
      orderData['service_notes'],
      orderData['catatan'],
      metadata['catatan_service'],
      metadata['service_notes'],
      orderConditionMap['catatan_service'],
      orderConditionMap['catatan'],
    ]);
    final serviceEstimateCost = fmtMoneyOrDash(
      orderData['estimate_amount'] ??
          orderData['estimasi_biaya'] ??
          orderData['estimate_cost'] ??
          metadata['estimasi_biaya'] ??
          metadata['estimate_cost'] ??
          orderConditionMap['estimasi_biaya'],
    );
    final serviceEstimatedFinish = formatLongDate(
      orderData['estimate_due_at'] ??
          orderData['estimasi_selesai'] ??
          orderData['estimated_finish_at'] ??
          orderData['estimated_completion_date'] ??
          metadata['estimasi_selesai'] ??
          metadata['estimated_finish_at'] ??
          orderData['estimate_duration_text'] ??
          orderData['estimasi_waktu'],
    );
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
                                : isServiceOrder
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
                                                'Estimasi Biaya',
                                                serviceEstimateCost,
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
                                                    (isServiceOrder &&
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
                                                    (isServiceOrder &&
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
                            if (isServiceOrder)
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
                                    pw.Row(
                                      mainAxisAlignment:
                                          pw.MainAxisAlignment.center,
                                      children: [
                                        detailItemText('Estimasi Selesai'),
                                        pw.SizedBox(width: pxX(10)),
                                        detailItemText(serviceEstimatedFinish),
                                      ],
                                    ),
                                    pw.SizedBox(height: pxY(2)),
                                    pw.Container(
                                      height: 0.8,
                                      color: PdfColors.grey500,
                                    ),
                                    pw.SizedBox(height: pxY(2)),
                                    pw.Center(
                                      child: detailItemText(
                                        'KALAU AMBIL BAWA BUKTI ORDER INI, TIDAK BAWA TIDAK DILAYANI',
                                      ),
                                    ),
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
                                      child: orderNumber.isEmpty
                                          ? pw.Center(
                                              child: detailItemText('QR'),
                                            )
                                          : pw.Padding(
                                              padding: const pw.EdgeInsets.all(
                                                4,
                                              ),
                                              child: pw.BarcodeWidget(
                                                barcode: pw.Barcode.qrCode(),
                                                data: orderNumber,
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
                                  : (isServiceOrder ? purple : red),
                              padding: pw.EdgeInsets.symmetric(
                                vertical: pxY(8),
                              ),
                              child: pw.Center(
                                child: pw.Text(
                                  isServiceOrder
                                      ? 'ORDER SERVICE'
                                      : transactionLabel,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: pw.TextStyle(
                                    font: pw.Font.helvetica(),
                                    fontSize: isServiceOrder ? 13 : 12,
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

    final filename =
        'faktur_${orderData['order_number'] ?? orderData['order_id'] ?? 'order'}.pdf';
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
