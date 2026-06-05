import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/widgets.dart' as pw;
import 'package:vanessa3/utils/network_config.dart';

final Map<String, Uint8List> fakturImageByteCache = <String, Uint8List>{};

bool fakturBytesLookLikeRasterImage(Uint8List b) {
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

bool fakturBytesDecodableAsPdfImage(Uint8List b) {
  try {
    pw.MemoryImage(b);
    return true;
  } catch (_) {
    return false;
  }
}

bool fakturBytesLookLikeJsonObject(Uint8List b) {
  for (var i = 0; i < b.length && i < 64; i++) {
    final c = b[i];
    if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) continue;
    return c == 0x7b;
  }
  return false;
}

String? fakturPhotoAbsoluteUrl(dynamic raw) {
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

bool fakturIsSameApiOrigin(String url) {
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

Future<Uint8List?> fakturFetchBytes(
  String? url, {
  Duration timeout = const Duration(seconds: 3),
  bool imageBinary = false,
  bool validatePdfRaster = false,
}) async {
  if (url == null) return null;
  final cached = fakturImageByteCache[url];
  if (cached != null) return cached;
  try {
    final Map<String, String>? headers = () {
      if (!fakturIsSameApiOrigin(url)) return null;
      return NetworkConfig.imageHeaders ?? NetworkConfig.defaultHeaders;
    }();
    final resp = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(timeout);
    if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
      final body = resp.bodyBytes;
      if (imageBinary && fakturBytesLookLikeJsonObject(body)) {
        return null;
      }
      if (validatePdfRaster &&
          (!fakturBytesLookLikeRasterImage(body) ||
              !fakturBytesDecodableAsPdfImage(body))) {
        return null;
      }
      if (fakturImageByteCache.length > 40) {
        fakturImageByteCache.remove(fakturImageByteCache.keys.first);
      }
      fakturImageByteCache[url] = body;
      return body;
    }
  } catch (_) {}
  return null;
}
