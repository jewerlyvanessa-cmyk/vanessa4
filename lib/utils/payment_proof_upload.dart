import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/utils/cs_order_photo_picker.dart';
import 'package:vanessa3/utils/cs_order_photo_upload.dart';
import 'package:vanessa3/utils/network_config.dart';

/// Upload bukti pembayaran (mobile: file; web: bytes) ke `/upload`.
abstract final class PaymentProofUpload {
  PaymentProofUpload._();

  static MediaType _mediaTypeForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    return MediaType('image', 'jpeg');
  }

  static Future<String?> upload(
    CsOrderPhotoPickResult pick, {
    String? token,
  }) async {
    if (!pick.hasPhoto) return null;

    final files = <http.MultipartFile>[];
    if (pick.bytes != null && pick.bytes!.isNotEmpty) {
      final name = pick.fileName ?? 'bukti.jpg';
      files.add(
        http.MultipartFile.fromBytes(
          'file',
          pick.bytes!,
          filename: name,
          contentType: _mediaTypeForName(name),
        ),
      );
    } else if (pick.file != null) {
      final path = pick.file!.path;
      files.add(
        await http.MultipartFile.fromPath(
          'file',
          path,
          contentType: _mediaTypeForName(path),
        ),
      );
    } else {
      return null;
    }

    final response = await ApiClient.postMultipart(
      '${NetworkConfig.storageUrl}/upload',
      headers: token != null && token.isNotEmpty
          ? {'Authorization': 'Bearer $token'}
          : null,
      files: files,
    );
    if (response.statusCode != 200) return null;
    return CsOrderPhotoUpload.parseUploadUrl(response.body);
  }
}
