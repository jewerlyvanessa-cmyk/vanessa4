import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> saveDownloadBytes({
  required String filename,
  required List<int> bytes,
  String mimeType = 'application/octet-stream',
}) async {
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/$filename';
  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(path, mimeType: mimeType, name: filename)],
      subject: filename,
    ),
  );
}
