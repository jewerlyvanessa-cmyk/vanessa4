import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

/// Hasil pilih foto (mobile: file JPEG terkompresi; web: bytes JPEG terkompresi).
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

  /// Sama dengan [compressToJpeg] / Android: max 800×800, JPEG kualitas 90%.
  static const int _compressMaxSide = 800;
  static const int _compressQuality = 90;

  static Future<File> compressToJpeg(File file) async {
    final targetPath =
        '${file.parent.path}/foto_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final resultX = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      minWidth: _compressMaxSide,
      minHeight: _compressMaxSide,
      quality: _compressQuality,
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
        minWidth: _compressMaxSide,
        minHeight: _compressMaxSide,
        quality: _compressQuality,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (compressed.isNotEmpty) return compressed;
    } catch (_) {}
    return input;
  }

  static String _defaultFileName(String name) =>
      name.isNotEmpty ? name : 'foto.jpg';

  static String _jpegFileName(String name) {
    final base = _defaultFileName(name);
    final lower = base.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return base;
    return '$base.jpg';
  }

  static Future<CsOrderPhotoPickResult?> _bytesToCompressedResult(
    Uint8List raw,
    String fileName,
  ) async {
    if (raw.isEmpty) return null;
    final bytes = await _compressBytesToJpeg(raw);
    return CsOrderPhotoPickResult(
      bytes: bytes,
      fileName: _jpegFileName(fileName),
    );
  }

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
    if (bytes == null) return null;
    return _bytesToCompressedResult(bytes, f.name);
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
      // Kompres sama seperti Android (800×800, JPEG 90%) via compressWithList.
      return _bytesToCompressedResult(raw, picked.name);
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
