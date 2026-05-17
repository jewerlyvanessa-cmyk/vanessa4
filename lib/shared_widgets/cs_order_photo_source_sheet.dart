import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Pilih sumber foto: kamera atau galeri (mobile); web → file picker saja.
Future<void> showCsOrderPhotoSourceSheet(
  BuildContext context, {
  required VoidCallback onCamera,
  required VoidCallback onGallery,
}) async {
  if (kIsWeb) {
    onGallery();
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Ambil Foto'),
              subtitle: const Text('Buka kamera langsung'),
              onTap: () {
                Navigator.pop(ctx);
                onCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Pilih dari Galeri'),
              subtitle: const Text('Upload dari album foto'),
              onTap: () {
                Navigator.pop(ctx);
                onGallery();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
