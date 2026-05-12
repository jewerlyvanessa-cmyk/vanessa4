import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart' show PdfColor;
import 'package:pdf/widgets.dart' as pw;
import 'package:vanessa3/utils/network_config.dart';

/// Cache ringan: hanya hasil sukses (byte gambar).
final Map<String, Uint8List> _branchLogoPositiveCache = <String, Uint8List>{};

String? branchLogoAbsoluteUrlFromRaw(dynamic raw) {
  final s0 = raw?.toString().trim();
  if (s0 == null || s0.isEmpty) return null;
  if (s0.startsWith('http://') || s0.startsWith('https://')) return s0;
  final s = s0.replaceAll('\\', '/');
  if (s.startsWith('/')) return '${NetworkConfig.baseUrl}$s';
  if (RegExp(r'^uploads/', caseSensitive: false).hasMatch(s)) {
    return '${NetworkConfig.baseUrl}/$s';
  }
  return '${NetworkConfig.baseUrl}/uploads/$s';
}

bool _bytesLookLikeJsonObject(Uint8List b) {
  for (var i = 0; i < b.length && i < 64; i++) {
    final c = b[i];
    if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) continue;
    return c == 0x7b;
  }
  return false;
}

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

bool _isSameApiOrigin(String url) {
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

Future<Uint8List?> _httpGetBytes(
  String? url, {
  required bool imageBinary,
  Duration timeout = const Duration(seconds: 12),
}) async {
  if (url == null || url.isEmpty) return null;
  try {
    final Map<String, String>? headers = () {
      if (!_isSameApiOrigin(url)) return null;
      final t = NetworkConfig.authToken;
      if (t == null || t.trim().isEmpty) return null;
      if (imageBinary) {
        return {'Authorization': 'Bearer $t'};
      }
      return NetworkConfig.defaultHeaders;
    }();
    final resp = await http.get(Uri.parse(url), headers: headers).timeout(timeout);
    if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;
    final body = resp.bodyBytes;
    if (imageBinary && _bytesLookLikeJsonObject(body)) return null;
    if (imageBinary &&
        (!_bytesLookLikeRasterImage(body))) {
      return null;
    }
    return body;
  } catch (_) {
    return null;
  }
}

/// `logo_url` dari GET /branches/:id (sumber sama Manajemen Cabang).
Future<String?> fetchBranchLogoUrlFromBranchesApi(String branchId) async {
  final id = branchId.trim();
  if (id.isEmpty) return null;
  for (final p in ['/branches/$id', '/api/branches/$id']) {
    try {
      final resp = await http
          .get(
            Uri.parse('${NetworkConfig.baseUrl}$p'),
            headers: NetworkConfig.defaultHeaders,
          )
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) continue;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) continue;
      final s = decoded['logo_url']?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    } catch (_) {}
  }
  return null;
}

/// Raster (JPEG/PNG/WebP/GIF) untuk [pw.MemoryImage], sama urutan dengan faktur:
/// proxy `/branches/:id/logo` → `logo_url` dari API.
Future<Uint8List?> loadBranchLogoRasterBytesForPdf(String branchId) async {
  final id = branchId.trim();
  if (id.isEmpty) return null;
  final cached = _branchLogoPositiveCache[id];
  if (cached != null) return cached;

  Uint8List? out;
  try {
    for (final logoPath in ['/branches/$id/logo', '/api/branches/$id/logo']) {
      final proxy = '${NetworkConfig.baseUrl}$logoPath';
      final via = await _httpGetBytes(proxy, imageBinary: true);
      if (via != null && via.isNotEmpty) {
        out = via;
        break;
      }
    }
    if (out == null) {
      final remote = await fetchBranchLogoUrlFromBranchesApi(id);
      final abs = branchLogoAbsoluteUrlFromRaw(remote);
      if (abs != null) {
        out = await _httpGetBytes(
          abs,
          imageBinary: !_isSameApiOrigin(abs),
        );
      }
    }
  } catch (_) {}

  if (out != null && out.isNotEmpty) {
    if (_branchLogoPositiveCache.length > 48) {
      _branchLogoPositiveCache.remove(_branchLogoPositiveCache.keys.first);
    }
    _branchLogoPositiveCache[id] = out;
  }
  return out;
}

/// Skala layout logo cabang di PDF relatif terhadap lebar/tinggi piksel file.
const double _kBranchLogoPdfLayoutScale = 0.25;

/// Logo cabang di PDF: kotak layout [pw.Image] = [_kBranchLogoPdfLayoutScale] ×
/// dimensi piksel decode ([pw.MemoryImage]), proporsi tetap.

/// Raster cabang di PDF pada **25%** dari lebar × tinggi piksel asli file.
pw.Widget pdfBranchLogoRasterImage(Uint8List bytes) {
  final mem = pw.MemoryImage(bytes);
  final iw = mem.width;
  final ih = mem.height;
  if (iw == null || ih == null || iw < 1 || ih < 1) {
    return pw.SizedBox.shrink();
  }
  final w = iw * _kBranchLogoPdfLayoutScale;
  final h = ih * _kBranchLogoPdfLayoutScale;
  return pw.Image(mem, width: w, height: h, fit: pw.BoxFit.scaleDown);
}

/// Header [pw.MultiPage] — logo di **setiap halaman** fisik PDF.
pw.Widget Function(pw.Context)? pdfMultiPageHeaderFromLogoBytes(
  Uint8List? logoBytes,
) {
  if (logoBytes == null || logoBytes.isEmpty) return null;
  return (pw.Context ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Center(
          child: pdfBranchLogoRasterImage(logoBytes),
        ),
      );
}

/// Tiap halaman: **[logo cabang kiri] | blok tengah (judul dsb.) | [slot kanan]**.
/// Kanan hanya terisi jika `rightLogoBytes` tidak kosong (tanpa fallback ke kiri).
/// Tanpa logo di satu sisi: slot kosong lebar [emptyLeftSlotWidth] / [emptyRightSlotWidth].
/// Untuk judul rata kanan mengikuti margin konten, set [emptyRightSlotWidth] ke `0` bila
/// tidak ada logo kanan.
/// [centerCrossAxisAlignment] mengatur rata teks blok tengah (`end` = rata kanan).
pw.Widget Function(pw.Context)? pdfMultiPageHeaderBranchLogosFlankingCenter({
  required List<pw.Widget> centerColumn,
  Uint8List? leftLogoBytes,
  Uint8List? rightLogoBytes,
  double emptyLeftSlotWidth = 100,
  double emptyRightSlotWidth = 100,
  pw.CrossAxisAlignment centerCrossAxisAlignment = pw.CrossAxisAlignment.center,
}) {
  final left = leftLogoBytes;
  final right = (rightLogoBytes != null && rightLogoBytes.isNotEmpty)
      ? rightLogoBytes
      : null;

  pw.Widget sideSlot(
    Uint8List? bytes,
    pw.Alignment align, {
    required double emptyWidth,
  }) {
    if (bytes == null || bytes.isEmpty) {
      return pw.SizedBox(width: emptyWidth);
    }
    return pw.Align(
      alignment: align,
      child: pdfBranchLogoRasterImage(bytes),
    );
  }

  pw.Alignment alignmentForCenterColumn(pw.CrossAxisAlignment c) {
    switch (c) {
      case pw.CrossAxisAlignment.end:
        return pw.Alignment.topRight;
      case pw.CrossAxisAlignment.start:
        return pw.Alignment.topLeft;
      default:
        return pw.Alignment.topCenter;
    }
  }

  return (pw.Context ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                sideSlot(left, pw.Alignment.centerLeft,
                    emptyWidth: emptyLeftSlotWidth),
                pw.Expanded(
                  child: pw.Align(
                    alignment: alignmentForCenterColumn(centerCrossAxisAlignment),
                    child: pw.Column(
                      crossAxisAlignment: centerCrossAxisAlignment,
                      mainAxisSize: pw.MainAxisSize.min,
                      children: centerColumn,
                    ),
                  ),
                ),
                sideSlot(right, pw.Alignment.centerRight,
                    emptyWidth: emptyRightSlotWidth),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1),
          ],
        ),
      );
}

/// Baris teks di bawah judul header laporan (rata kanan, di bawah judul utama).
class PdfLaporanHeaderSubtitleLine {
  const PdfLaporanHeaderSubtitleLine(
    this.text, {
    this.fontSize = 12,
    this.fontWeight = pw.FontWeight.normal,
    this.color,
  });

  final String text;
  final double fontSize;
  final pw.FontWeight fontWeight;
  final PdfColor? color;
}

/// Header multi-halaman seragam laporan cabang: logo kiri + judul & subjudul rata kanan
/// (sama pola Order Today). Logo kanan opsional (mis. surat jalan dua cabang).
pw.Widget Function(pw.Context)? pdfMultiPageHeaderLaporanCabang({
  required String title,
  Uint8List? leftLogoBytes,
  Uint8List? rightLogoBytes,
  List<PdfLaporanHeaderSubtitleLine> subtitles = const [],
  double emptyLeftSlotWidth = 100,
  double? emptyRightSlotWidth,
}) {
  final hasRightLogo = rightLogoBytes != null && rightLogoBytes.isNotEmpty;
  final er = emptyRightSlotWidth ?? (hasRightLogo ? 100 : 0);

  final center = <pw.Widget>[
    pw.Text(
      title,
      textAlign: pw.TextAlign.right,
      style: pw.TextStyle(
        fontSize: 18,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  ];
  for (final s in subtitles) {
    if (s.text.trim().isEmpty) continue;
    center
      ..add(pw.SizedBox(height: 4))
      ..add(
        pw.Text(
          s.text,
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(
            fontSize: s.fontSize,
            fontWeight: s.fontWeight,
            color: s.color,
          ),
        ),
      );
  }

  return pdfMultiPageHeaderBranchLogosFlankingCenter(
    leftLogoBytes: leftLogoBytes,
    rightLogoBytes: rightLogoBytes,
    emptyLeftSlotWidth: emptyLeftSlotWidth,
    emptyRightSlotWidth: er,
    centerCrossAxisAlignment: pw.CrossAxisAlignment.end,
    centerColumn: center,
  );
}

/// Dua logo (mis. surat jalan cabang asal & tujuan), satu baris, ukuran intrinsik masing-masing.
pw.Widget Function(pw.Context)? pdfMultiPageHeaderFromTwoLogoBytes(
  Uint8List? left,
  Uint8List? right,
) {
  if ((left == null || left.isEmpty) && (right == null || right.isEmpty)) {
    return null;
  }
  return (pw.Context ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
          children: [
            if (left != null && left.isNotEmpty) pdfBranchLogoRasterImage(left),
            if (right != null && right.isNotEmpty) pdfBranchLogoRasterImage(right),
          ],
        ),
      );
}

/// Logo sekali di isi dokumen (bukan per halaman).
List<pw.Widget> pdfInlineLogoWidgets(Uint8List? logoBytes) {
  if (logoBytes == null || logoBytes.isEmpty) return const [];
  return [
    pw.Center(
      child: pdfBranchLogoRasterImage(logoBytes),
    ),
    pw.SizedBox(height: 10),
  ];
}
