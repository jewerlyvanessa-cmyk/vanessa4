import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'package:image_picker/image_picker.dart'
    if (dart.library.html) 'image_picker_stub.dart';

/// Hasil pilih foto (mobile: file terkompresi; web: bytes).
class CsOrderPhotoPickResult {
  const CsOrderPhotoPickResult({
    this.file,
    this.bytes,
    this.fileName,
  });

  final File? file;
  final Uint8List? bytes;
  final String? fileName;

  bool get hasPhoto =>
      (bytes != null && bytes!.isNotEmpty) || file != null;
}

/// Kamera / galeri / file (web) — dipakai form CS (Jual, Service, Custom, Buyback, Ambil).
abstract final class CsOrderPhotoPicker {
  CsOrderPhotoPicker._();

  static final ImagePicker _picker = ImagePicker();

  static Future<File> compressToJpeg(File file) async {
    final targetPath =
        '${file.parent.path}/foto_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final resultX = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      minWidth: 800,
      minHeight: 800,
      quality: 90,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    if (resultX != null) return File(resultX.path);
    return file;
  }

  static Future<CsOrderPhotoPickResult?> pickFromFilePicker() async {
    final f = await FilePicker.pickFile(type: FileType.image);
    if (f == null) return null;
    final bytes = await f.readAsBytes();
    if (bytes.isEmpty) return null;
    return CsOrderPhotoPickResult(
      bytes: bytes,
      fileName: f.name.isNotEmpty ? f.name : 'foto.jpg',
    );
  }

  static Future<CsOrderPhotoPickResult?> pickFromCamera({
    int imageQuality = 85,
  }) async {
    if (kIsWeb) return pickFromFilePicker();
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: imageQuality,
    );
    if (picked == null) return null;
    final file = await compressToJpeg(File(picked.path));
    return CsOrderPhotoPickResult(file: file);
  }

  static Future<CsOrderPhotoPickResult?> pickFromGallery({
    int imageQuality = 85,
  }) async {
    if (kIsWeb) return pickFromFilePicker();
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: imageQuality,
    );
    if (picked == null) return null;
    final file = await compressToJpeg(File(picked.path));
    return CsOrderPhotoPickResult(file: file);
  }
}
