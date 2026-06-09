import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

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

/// Kamera / galeri / file — dipakai form CS (Jual, Service, Custom, Buyback, Ambil).
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

  static Future<Uint8List> _compressBytesToJpeg(Uint8List input) async {
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        input,
        minWidth: 800,
        minHeight: 800,
        quality: 90,
        format: CompressFormat.jpeg,
      );
      if (compressed.isNotEmpty) return compressed;
    } catch (_) {}
    return input;
  }

  static String _defaultFileName(String name) =>
      name.isNotEmpty ? name : 'foto.jpg';

  static Future<Uint8List?> _platformFileBytes(PlatformFile file) async {
    try {
      return await file.readAsBytes();
    } catch (_) {
      final path = file.path;
      if (path != null && path.isNotEmpty && !kIsWeb) {
        return File(path).readAsBytes();
      }
    }
    return null;
  }

  static Future<CsOrderPhotoPickResult?> pickFromFilePicker() async {
    final f = await FilePicker.pickFile(
      type: FileType.image,
    );
    if (f == null) return null;
    final bytes = await _platformFileBytes(f);
    if (bytes == null || bytes.isEmpty) return null;
    final compressed = await _compressBytesToJpeg(bytes);
    return CsOrderPhotoPickResult(
      bytes: compressed,
      fileName: _defaultFileName(f.name),
    );
  }

  static Future<CsOrderPhotoPickResult?> _pickImage(
    ImageSource source, {
    int imageQuality = 85,
  }) async {
    // Web: hindari maxWidth/maxHeight/quality agresif — beberapa browser
    // (Chrome mobile) gagal membuka kamera jika constraint terlalu ketat.
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: kIsWeb ? null : imageQuality,
      maxWidth: kIsWeb ? null : 1600,
      maxHeight: kIsWeb ? null : 1600,
      requestFullMetadata: !kIsWeb,
    );
    if (picked == null) return null;

    if (kIsWeb) {
      final raw = await picked.readAsBytes();
      if (raw.isEmpty) return null;
      // flutter_image_compress tidak andal di web — kirim bytes asli.
      return CsOrderPhotoPickResult(
        bytes: raw,
        fileName: _defaultFileName(picked.name),
      );
    }

    final file = await compressToJpeg(File(picked.path));
    return CsOrderPhotoPickResult(file: file);
  }

  static Future<CsOrderPhotoPickResult?> pickFromCamera({
    int imageQuality = 85,
  }) =>
      _pickImage(ImageSource.camera, imageQuality: imageQuality);

  static Future<CsOrderPhotoPickResult?> pickFromGallery({
    int imageQuality = 85,
  }) =>
      _pickImage(ImageSource.gallery, imageQuality: imageQuality);
}
