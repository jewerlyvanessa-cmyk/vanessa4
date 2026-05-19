import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Fallback: bagikan file (platform yang tidak punya download langsung).
Future<void> saveDownloadBytes({
  required String filename,
  required List<int> bytes,
  String mimeType = 'application/octet-stream',
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(bytes),
          name: filename,
          mimeType: mimeType,
        ),
      ],
      subject: filename,
    ),
  );
}
