import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/utils/cs_order_photo_upload.dart';
import 'package:vanessa3/utils/network_config.dart';

class FileUploader {
  static String get uploadUrl => '${NetworkConfig.storageUrl}/upload';

  static MediaType _detectImageMediaType(String filePath) {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    return MediaType('image', 'jpeg');
  }

  static Future<String?> uploadImage(File imageFile, {String? token}) async {
    try {
      final response = await ApiClient.postMultipart(
        uploadUrl,
        headers: token != null && token.isNotEmpty
            ? {'Authorization': 'Bearer $token'}
            : null,
        files: [
          await http.MultipartFile.fromPath(
            'file',
            imageFile.path,
            contentType: _detectImageMediaType(imageFile.path),
          ),
        ],
      );
      if (response.statusCode == 200) {
        return CsOrderPhotoUpload.parseUploadUrl(response.body);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
