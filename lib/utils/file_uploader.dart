import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:vanessa3/utils/network_config.dart';

class FileUploader {
  // Ganti URL ini dengan endpoint upload backend kamu
  static String get uploadUrl => '${NetworkConfig.storageUrl}/upload';

  static MediaType _detectImageMediaType(String filePath) {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    // default to jpeg for .jpg/.jpeg or unknown (we compress to jpg in most flows)
    return MediaType('image', 'jpeg');
  }

  static Future<String?> uploadImage(File imageFile, {String? token}) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          imageFile.path,
          contentType: _detectImageMediaType(imageFile.path),
        ),
      );
      final effectiveToken = (token != null && token.isNotEmpty)
          ? token
          : NetworkConfig.authToken;
      if (effectiveToken != null && effectiveToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $effectiveToken';
      }
      final response = await request.send();
      final respStr = await response.stream.bytesToString();
      if (response.statusCode == 200) {
        // Jika backend mengembalikan JSON, ambil url dari key "url"
        if (respStr.trim().startsWith('{')) {
          final url = RegExp(r'"url"\s*:\s*"([^"]+)"').firstMatch(respStr)?.group(1);
          if (url != null) return url;
        }
        // Jika plain text, return langsung
        return respStr.trim();
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }
}
