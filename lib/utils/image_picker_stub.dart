// Stub implementation for web platform
import 'package:cross_file/cross_file.dart';

class ImagePicker {
  Future<XFile?> pickImage({required ImageSource source}) async {
    // Web implementation - could use file picker or show message
    return null;
  }
}

enum ImageSource {
  camera,
  gallery,
}
