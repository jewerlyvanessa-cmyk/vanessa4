import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:vanessa3/utils/cs_order_photo_picker.dart';
import 'package:vanessa3/utils/network_config.dart';

/// Upload bukti pembayaran (mobile: file; web: bytes) ke `/upload`.
abstract final class PaymentProofUpload {
  PaymentProofUpload._();

  static String get _uploadUrl => '${NetworkConfig.storageUrl}/upload';

  static MediaType _mediaTypeForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    return MediaType('image', 'jpeg');
  }

  static String? _parseUploadResponse(String respStr, String storageUrl) {
    final trimmed = respStr.trim();
    if (trimmed.startsWith('{')) {
      try {
        final data = jsonDecode(trimmed);
        if (data is Map) {
          final url = data['url'] ?? data['fileUrl'] ?? data['path'];
          if (url is String && url.isNotEmpty) {
            if (url.startsWith('/')) return '$storageUrl$url';
            return url;
          }
        }
      } catch (_) {
        final url = RegExp(r'"url"\s*:\s*"([^"]+)"')
            .firstMatch(trimmed)
            ?.group(1);
        if (url != null) return url;
      }
    }
    if (trimmed.isNotEmpty) return trimmed;
    return null;
  }

  static Future<String?> upload(
    CsOrderPhotoPickResult pick, {
    String? token,
  }) async {
    if (!pick.hasPhoto) return null;

    final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl));
    final effectiveToken = (token != null && token.isNotEmpty)
        ? token
        : NetworkConfig.authToken;
    if (effectiveToken != null && effectiveToken.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $effectiveToken';
    }

    if (pick.bytes != null && pick.bytes!.isNotEmpty) {
      final name = pick.fileName ?? 'bukti.jpg';
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          pick.bytes!,
          filename: name,
          contentType: _mediaTypeForName(name),
        ),
      );
    } else if (pick.file != null) {
      final path = pick.file!.path;
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          path,
          contentType: _mediaTypeForName(path),
        ),
      );
    } else {
      return null;
    }

    final response = await request.send();
    final respStr = await response.stream.bytesToString();
    if (response.statusCode != 200) return null;
    return _parseUploadResponse(respStr, NetworkConfig.storageUrl);
  }
}
