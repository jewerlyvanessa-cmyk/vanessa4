import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/utils/network_config.dart';

/// Upload foto order CS ke storage (`POST /upload`).
abstract final class CsOrderPhotoUpload {
  CsOrderPhotoUpload._();

  static MediaType detectImageMediaType(String filePath) {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    return MediaType('image', 'jpeg');
  }

  static String? parseUploadUrl(String respStr, {String? storageBase}) {
    final base = storageBase ?? NetworkConfig.storageUrl;
    final trimmed = respStr.trim();
    if (trimmed.startsWith('{')) {
      try {
        final data = jsonDecode(trimmed);
        if (data is Map) {
          final url = data['url'] ?? data['fileUrl'] ?? data['path'];
          if (url is String && url.isNotEmpty) {
            if (url.startsWith('/')) return '$base$url';
            return url;
          }
        }
      } catch (_) {
        final url = RegExp(r'"url"\s*:\s*"([^"]+)"')
            .firstMatch(trimmed)
            ?.group(1);
        if (url != null) {
          if (url.startsWith('/')) return '$base$url';
          return url;
        }
      }
    }
    if (trimmed.isNotEmpty) {
      if (trimmed.startsWith('/')) return '$base$trimmed';
      return trimmed;
    }
    return null;
  }

  static Future<String?> upload({
    File? file,
    Uint8List? bytes,
    String? fileName,
  }) async {
    final hasBytes = bytes != null && bytes.isNotEmpty;
    if (file == null && !hasBytes) return null;

    final files = <http.MultipartFile>[];
    if (kIsWeb || hasBytes) {
      final data = bytes ?? await file!.readAsBytes();
      final name = (fileName != null && fileName.trim().isNotEmpty)
          ? fileName.trim()
          : 'foto.jpg';
      files.add(
        http.MultipartFile.fromBytes(
          'file',
          data,
          filename: name,
          contentType: detectImageMediaType(name),
        ),
      );
    } else {
      files.add(
        await http.MultipartFile.fromPath(
          'file',
          file!.path,
          contentType: detectImageMediaType(file.path),
        ),
      );
    }

    final response = await ApiClient.postMultipart(
      '${NetworkConfig.storageUrl}/upload',
      files: files,
    );
    if (response.statusCode == 200) {
      return parseUploadUrl(response.body);
    }
    return null;
  }
}
