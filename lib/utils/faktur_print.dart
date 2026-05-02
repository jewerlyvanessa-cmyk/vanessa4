import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/terbilang.dart';

/// Builds a simple invoice PDF and opens the system print / share UI.
Future<void> printFakturOrder(
  BuildContext context,
  Map<String, dynamic> orderData,
) async {
  try {
    final items = orderData['items'] as List<dynamic>? ?? [];
    final doc = pw.Document();

    Future<Uint8List?> loadAssetBytes(String assetPath) async {
      try {
        final data = await rootBundle.load(assetPath);
        return data.buffer.asUint8List();
      } catch (_) {
        return null;
      }
    }

    String? photoUrl(dynamic raw) {
      final s = raw?.toString().trim();
      if (s == null || s.isEmpty) return null;
      if (s.startsWith('http://') || s.startsWith('https://')) return s;
      if (s.startsWith('/')) return '${NetworkConfig.baseUrl}$s';
      return '${NetworkConfig.baseUrl}/uploads/$s';
    }

    Future<Uint8List?> fetchBytes(String? url) async {
      if (url == null) return null;
      try {
        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) return resp.bodyBytes;
      } catch (_) {}
      return null;
    }

    Future<List<String>> fetchBranchNames() async {
      try {
        final url = '${NetworkConfig.baseUrl}/api/branches';
        final resp = await http
            .get(Uri.parse(url), headers: NetworkConfig.defaultHeaders)
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode != 200) return const [];

        final decoded = jsonDecode(resp.body);
        if (decoded is! List) return const [];

        final namesAll = <String>[];
        final namesFiltered = <String>[];
        for (final e in decoded) {
          if (e is Map) {
            final m = Map<String, dynamic>.from(e);
            final n = (m['name'] ?? '').toString().trim();
            final lower = n.toLowerCase();
            if (n.isEmpty) continue;
            namesAll.add(n);
            if (lower != 'cabang utama' && lower != 'workshop vanessa kendalsari') {
              namesFiltered.add(n);
            }
          }
        }
        final effective = namesFiltered.isNotEmpty ? namesFiltered : namesAll;
        final uniq = effective.toSet().toList()..sort();
        return uniq;
      } catch (_) {
        return const [];
      }
    }

    // Prefetch images once (best-effort) so PDF rendering stays synchronous.
    final itemMaps = items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final photoBytesByIndex = <int, Uint8List?>{};
    final logoBytes = await loadAssetBytes('assets/logo_bulat.png');
    final headerLogoBytes = await loadAssetBytes('assets/LOGO BRANGKAL1.png');
    final pw.Font? barlowCondensedBold = await (() async {
      try {
        return await PdfGoogleFonts.barlowCondensedBold();
      } catch (_) {
        return null;
      }
    })();
    await Future.wait(
      List.generate(itemMaps.length, (i) async {
        final url = photoUrl(itemMaps[i]['photo_produk']);
        photoBytesByIndex[i] = await fetchBytes(url);
      }),
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
      final titled = words.map((w) {
        if (w.isEmpty) return w;
        final lower = w.toLowerCase();
        return lower[0].toUpperCase() + lower.substring(1);
      }).join(' ');
      return titled;
    }

    final terbilangText = toTitleCase(
      '${terbilang(totalFinal.toInt()).trim()} rupiah'.trim(),
    );

    final primaryItem = itemMaps.isNotEmpty
        ? itemMaps.first
        : <String, dynamic>{};
    final primaryPhotoBytes = itemMaps.isNotEmpty ? photoBytesByIndex[0] : null;

    final noNota = (orderData['order_number'] ?? orderData['order_id'] ?? '-')
        .toString();
    final orderNumber = (orderData['order_number'] ?? '').toString().trim();
    final tanggal = dateStr(orderData['created_at']);
    final customerName = (orderData['customer_name'] ?? '-').toString();
    final customerAddr = (orderData['customer_address'] ?? '-').toString();
    final csName =
        (orderData['created_by_name'] ??
                orderData['cs_name'] ??
                orderData['username'] ??
                '-')
            .toString();

    List<String> extractBranchNames(Map<String, dynamic> data) {
      bool isCabangUtama(String s) => s.trim().toLowerCase() == 'cabang utama';
      bool isExcludedBranch(String s) =>
          s.trim().toLowerCase() == 'workshop vanessa kendalsari';

      final raw = data['branches'] ?? data['all_branches'] ?? data['branch_list'];
      if (raw is List) {
        final namesAll = <String>[];
        final namesFiltered = <String>[];
        for (final e in raw) {
          if (e is Map) {
            final m = Map<String, dynamic>.from(e);
            final n = (m['name'] ?? m['branch_name'] ?? '').toString().trim();
            if (n.isEmpty) continue;
            namesAll.add(n);
            if (!isExcludedBranch(n) && !isCabangUtama(n)) namesFiltered.add(n);
          } else {
            final n = e?.toString().trim() ?? '';
            if (n.isEmpty) continue;
            namesAll.add(n);
            if (!isExcludedBranch(n) && !isCabangUtama(n)) namesFiltered.add(n);
          }
        }
        final effective = namesFiltered.isNotEmpty ? namesFiltered : namesAll;
        return effective.toSet().toList()..sort();
      }

      final rawNames =
          data['branch_names'] ?? data['branches_names'] ?? data['branchesName'];
      if (rawNames is String) {
        final parts =
            rawNames.split(RegExp(r'[,\n;|]+')).map((e) => e.trim()).toList();
        final namesAll = parts.where((e) => e.isNotEmpty).toList();
        final namesFiltered =
            parts
                .where(
                  (e) =>
                      e.isNotEmpty && !isCabangUtama(e) && !isExcludedBranch(e),
                )
                .toList();
        final effective = namesFiltered.isNotEmpty ? namesFiltered : namesAll;
        return effective.toSet().toList()..sort();
      }

      return const [];
    }

    var branchNames = extractBranchNames(orderData);
    if (branchNames.isEmpty) {
      branchNames = await fetchBranchNames();
    }

    final idProduk =
        (primaryItem['kode_produk'] ?? primaryItem['item_code'] ?? '-')
            .toString();
    final deskripsi =
        (primaryItem['deskripsi'] ??
                primaryItem['description'] ??
                primaryItem['nama_item'] ??
                primaryItem['name'] ??
                '-')
            .toString();

    final qty = (primaryItem['qty'] ?? primaryItem['quantity'] ?? 1).toString();
    final berat = (primaryItem['weight'] ?? primaryItem['berat'] ?? '-');
    final hargaPerGram = fmtMoney(primaryItem['harga_per_gram'] ?? 0);

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

          final tipe =
              (primaryItem['tipe'] ??
                      primaryItem['type'] ??
                      primaryItem['jenis'] ??
                      '')
                  .toString()
                  .trim();

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
          }) {
            return pw.Text(
              text,
              style: pw.TextStyle(
                font: pw.Font.helvetica(),
                fontSize: 12,
                fontWeight: weight,
                fontStyle: style,
                color: PdfColors.black,
              ),
            );
          }

          pw.Widget detailItemKv(
            String label,
            String value, {
            double fontSize = 12,
            pw.FontWeight? weight,
            pw.FontStyle? style,
            pw.Font? font,
          }) {
            final baseStyle = pw.TextStyle(
              font: font ?? pw.Font.helvetica(),
              fontSize: fontSize,
              fontWeight: weight,
              fontStyle: style,
              color: PdfColors.black,
            );

            // Fixed label width so ":" aligns vertically on every row.
            // Make it wide enough to avoid label wrapping.
            final labelW = pxX(170);

            return pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: labelW,
                  child: pw.Text(label, style: baseStyle),
                ),
                pw.SizedBox(
                  width: pxX(12),
                  child: pw.Text(':', style: baseStyle),
                ),
                pw.SizedBox(width: pxX(6)),
                pw.Expanded(
                  child: pw.Text(value, style: baseStyle),
                ),
              ],
            );
          }

          pw.Widget detailTxnKv(
            String label,
            String value, {
            double fontSize = 12,
          }) {
            final baseStyle = pw.TextStyle(
              font: pw.Font.helvetica(),
              fontSize: fontSize,
              color: PdfColors.black,
            );

            // Fixed label width so ":" aligns vertically in RIGHT INFO block.
            final labelW = pxX(95);

            return pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: labelW,
                  child: pw.Text(label, style: baseStyle),
                ),
                pw.SizedBox(
                  width: pxX(10),
                  child: pw.Text(':', style: baseStyle),
                ),
                pw.SizedBox(width: pxX(6)),
                pw.Expanded(
                  child: pw.Text(value, style: baseStyle),
                ),
              ],
            );
          }

          pw.Widget netImageOrPlaceholder({
            required Uint8List? bytes,
            required double w,
            required double h,
          }) {
            if (bytes == null) {
              return pw.Container(
                width: w,
                height: h,
                color: PdfColors.grey300,
                child: pw.Center(
                  child: pw.Text(
                    'Tidak ada foto',
                    style: pw.TextStyle(color: PdfColors.grey700, fontSize: 12),
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
          final blue = PdfColor.fromInt(0xFF0D47A1);

          return pw.Container(
            color: background,
            child: pw.Center(
              child: pw.Container(
                width: contentW,
                height: contentH,
                color: PdfColors.white,
                child: pw.Stack(
                  children: [
                    // HEADER
                    pw.Positioned(
                      top: pxY(10),
                      left: pxX(20),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(
                            width: 2 * PdfPageFormat.cm,
                            height: 2 * PdfPageFormat.cm,
                            decoration: const pw.BoxDecoration(
                              shape: pw.BoxShape.circle,
                              color: PdfColors.black,
                            ),
                            child: pw.Center(
                              child: logoBytes == null
                                  ? textLine(
                                      'V',
                                      size: 12,
                                      color: PdfColors.yellow,
                                      weight: pw.FontWeight.bold,
                                    )
                                  : pw.ClipOval(
                                      child: pw.Image(
                                        pw.MemoryImage(logoBytes),
                                        fit: pw.BoxFit.cover,
                                      ),
                                    ),
                            ),
                          ),
                          pw.SizedBox(width: pxX(20)),
                          headerLogoBytes == null
                              ? pw.Container(
                                  // Match requested header logo height (2 cm)
                                  height: 2 * PdfPageFormat.cm,
                                  width: pxX(520),
                                  decoration: pw.BoxDecoration(
                                    color: PdfColors.grey100,
                                    border: pw.Border.all(
                                      color: PdfColors.grey400,
                                    ),
                                  ),
                                  child: pw.Center(
                                    child: textLine(
                                      'Header logo tidak ditemukan',
                                      size: 10,
                                      color: PdfColors.grey700,
                                    ),
                                  ),
                                )
                              : pw.ConstrainedBox(
                                  constraints: pw.BoxConstraints(
                                    // Fixed height; width follows aspect ratio.
                                    maxHeight: 2 * PdfPageFormat.cm,
                                    // Keep some reasonable max width so it won't collide with right title.
                                    maxWidth: pxX(560),
                                  ),
                                  child: pw.Image(
                                    pw.MemoryImage(headerLogoBytes),
                                    height: 2 * PdfPageFormat.cm,
                                    fit: pw.BoxFit.contain,
                                  ),
                                ),
                        ],
                      ),
                    ),

                    // RIGHT TITLE (removed per request)

                    // RIGHT HEADER: branches list (2 columns)
                    if (branchNames.isNotEmpty)
                      pw.Positioned(
                        top: pxY(18),
                        right: pxX(20),
                        child: pw.SizedBox(
                          // Keep bounded width so layout is stable.
                          width: pxX(520),
                          child: (() {
                            final half = (branchNames.length / 2).ceil();
                            final leftCol = branchNames.take(half).toList();
                            final rightCol = branchNames.skip(half).toList();

                            pw.Widget col(List<String> names) {
                              return pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: names
                                    .map(
                                      (n) => pw.Padding(
                                        padding:
                                            pw.EdgeInsets.only(bottom: pxY(2)),
                                        child: pw.Text(
                                          n,
                                          maxLines: 1,
                                          overflow: pw.TextOverflow.clip,
                                          style: pw.TextStyle(
                                            font: pw.Font.helvetica(),
                                            fontSize: 9,
                                            color: PdfColors.black,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              );
                            }

                            return pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.SizedBox(width: pxX(255), child: col(leftCol)),
                                pw.SizedBox(width: pxX(10)), // gutter
                                pw.SizedBox(
                                  width: pxX(255),
                                  child: col(rightCol),
                                ),
                              ],
                            );
                          })(),
                        ),
                      ),

                    // BANNER
                    pw.Positioned(
                      // Lowered to avoid overlapping the header area.
                      top: pxY(145),
                      left: 0,
                      right: 0,
                      child: pw.Row(
                        children: [
                          pw.Expanded(
                            child: pw.Container(
                              color: purple,
                              padding: pw.EdgeInsets.all(pxX(10)),
                              child: pw.Center(
                                child: textLine(
                                  'MENERIMA SERVIS EMAS DAN PERAK',
                                  size: 14,
                                  color: PdfColors.white,
                                  weight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Container(
                              color: green,
                              padding: pw.EdgeInsets.all(pxX(10)),
                              child: pw.Center(
                                child: textLine(
                                  'HARGA MENGIKUT PASAR',
                                  size: 14,
                                  color: PdfColors.white,
                                  weight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // LEFT IMAGE
                    pw.Positioned(
                      top: pxY(225),
                      // Align with purple banner's left edge.
                      left: 0,
                      child: netImageOrPlaceholder(
                        bytes: primaryPhotoBytes,
                        w: pxX(280),
                        h: pxY(420),
                      ),
                    ),

                    // CENTER TEXT
                    pw.Positioned(
                      top: pxY(225),
                      left: pxX(300),
                      child: pw.SizedBox(
                        // IMPORTANT: give bounded width so Rows with Expanded
                        // inside detailItemKv can be laid out safely.
                        width: pxX(370),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            detailItemKv('ID Produk', idProduk),
                            detailItemKv('Tipe', tipe.isEmpty ? '-' : tipe),
                            detailItemKv('Nama Produk', deskripsi),
                            detailItemKv('Qty', '$qty pcs'),
                            detailItemKv('Berat', '${fmtGram(berat)} gram'),
                            detailItemKv('Harga/gram', 'Rp. $hargaPerGram'),
                            pw.SizedBox(height: pxY(8)),
                            pw.Container(
                              width: pxX(370),
                              height: pxY(1.2),
                              color: PdfColors.black,
                            ),
                            pw.SizedBox(height: pxY(6)),
                            detailItemKv(
                              'TOTAL',
                              'Rp. ${fmtMoney(totalFinal)}',
                              fontSize: 13,
                              weight: pw.FontWeight.bold,
                              font: pw.Font.helveticaBold(),
                            ),
                            pw.SizedBox(height: pxY(6)),
                            pw.Container(
                              width: pxX(370),
                              height: pxY(1.2),
                              color: PdfColors.black,
                            ),
                            pw.SizedBox(height: pxY(10)),
                            detailItemText('Terbilang'),
                            detailItemText(
                              terbilangText,
                              style: pw.FontStyle.italic,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // RIGHT INFO
                    pw.Positioned(
                      top: pxY(225),
                      // Align to the right edge (same as right green banner).
                      right: 0,
                      child: pw.SizedBox(
                        width: pxX(410),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.SizedBox(
                                  width: pxX(290),
                                  child: pw.Column(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.start,
                                    children: [
                                      detailTxnKv('No. Nota', noNota, fontSize: 12),
                                      detailTxnKv(
                                        'Tanggal',
                                        tanggal.split(' ').first,
                                        fontSize: 12,
                                      ),
                                      detailTxnKv(
                                        'Customer',
                                        customerName,
                                        fontSize: 11,
                                      ),
                                      detailTxnKv('Alamat', customerAddr, fontSize: 12),
                                    ],
                                  ),
                                ),
                                pw.SizedBox(width: pxX(10)),
                                pw.SizedBox(
                                  width: pxX(110),
                                  height: pxY(110),
                                  child: pw.Align(
                                    alignment: pw.Alignment.topRight,
                                    child: orderNumber.isEmpty
                                        ? pw.Container(
                                            width: pxX(110),
                                            height: pxY(110),
                                            color: PdfColors.grey300,
                                            child: pw.Center(
                                              child: textLine(
                                                'QR',
                                                size: 16,
                                                weight: pw.FontWeight.bold,
                                              ),
                                            ),
                                          )
                                        : pw.BarcodeWidget(
                                            barcode: pw.Barcode.qrCode(),
                                            data: orderNumber,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                            pw.SizedBox(height: pxY(5)),
                            pw.Align(
                              alignment: pw.Alignment.centerRight,
                              child: pw.Container(
                                // Make this box flush to the right edge of the
                                // right-side block (info + QR).
                                width: pxX(410),
                                color: blue,
                                padding: pw.EdgeInsets.all(pxX(8)),
                                child: pw.Center(
                                  child: pw.Text(
                                    'KALAU MENJUAL HARUS BAWA NOTA INI,\nBARANG RUSAK LAIN HARGA',
                                    textAlign: pw.TextAlign.center,
                                    maxLines: 2,
                                    style: pw.TextStyle(
                                      font:
                                          barlowCondensedBold ??
                                          pw.Font.helveticaBold(),
                                      fontSize: 14,
                                      color: PdfColors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            pw.SizedBox(height: pxY(5)),
                            textLine(
                              'Telah diperiksa dan diserahkan',
                              size: 12,
                            ),
                            pw.SizedBox(height: pxY(10)),
                            textLine('CS : $csName', size: 12),
                          ],
                        ),
                      ),
                    ),

                    // FOOTER
                    pw.Positioned(
                      bottom: 0,
                      // Start under detail item (not under photo).
                      left: pxX(300),
                      right: 0,
                      child: pw.Container(
                        color: green,
                        padding: pw.EdgeInsets.all(pxX(12)),
                        child: pw.Center(
                          child: pw.Text(
                            'SEMOGA ANDA TETAP MENJADI PELANGGAN SETIA KAMI',
                            maxLines: 1,
                            style: pw.TextStyle(
                              font: pw.Font.helveticaBold(),
                              fontSize: 13,
                              color: PdfColors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      name:
          'faktur_${orderData['order_number'] ?? orderData['order_id'] ?? 'order'}.pdf',
      onLayout: (format) async => doc.save(),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal mencetak: $e')));
    }
  }
}
