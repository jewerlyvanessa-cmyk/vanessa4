// Stub implementation for web platform — API surface aligned with
// package:image_picker so conditional imports compile on web.
import 'package:cross_file/cross_file.dart';

export 'package:cross_file/cross_file.dart' show XFile;

enum CameraDevice {
  rear,
  front,
}

enum ImageSource {
  camera,
  gallery,
}

class ImagePicker {
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    return null;
  }
}
