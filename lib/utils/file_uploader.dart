import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:vanessa3/utils/network_config.dart';

class FileUploader {
  // Ganti URL ini dengan endpoint upload backend kamu
  static String get uploadUrl => '${NetworkConfig.baseUrl.replaceAll('3000', '4000')}/upload';

  static Future<String?> uploadImage(File imageFile, {String? token}) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
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
