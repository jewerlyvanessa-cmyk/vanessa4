import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vanessa3/shared_widgets/cs_order_photo_source_sheet.dart';

/// Field foto order CS — UI sama form Jual (PopupMenu + tombol Pilih Foto).
class CsOrderPhotoField extends StatelessWidget {
  const CsOrderPhotoField({
    super.key,
    this.label = 'Foto',
    this.labelWidth = 100,
    required this.hasPhoto,
    this.imageBytes,
    this.imageFile,
    required this.onCamera,
    required this.onGallery,
    this.requiredMessage,
    this.previewSize = 160,
  });

  final String label;
  final double labelWidth;
  final bool hasPhoto;
  final Uint8List? imageBytes;
  final File? imageFile;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final String? requiredMessage;
  final double previewSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: labelWidth,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(label),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.photo_camera),
                label: const Text('Pilih Foto'),
                onPressed: () => showCsOrderPhotoSourceSheet(
                  context,
                  onCamera: onCamera,
                  onGallery: onGallery,
                ),
              ),
              if (requiredMessage != null && !hasPhoto) ...[
                const SizedBox(height: 8),
                Text(
                  requiredMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
              if (hasPhoto) ...[
                const SizedBox(height: 8),
                Center(
                  child: _buildPreview(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    if (imageBytes != null && imageBytes!.isNotEmpty) {
      return Image.memory(
        imageBytes!,
        width: previewSize,
        height: previewSize,
        fit: BoxFit.cover,
      );
    }
    if (imageFile != null) {
      return Image.file(
        imageFile!,
        width: previewSize,
        height: previewSize,
        fit: BoxFit.cover,
      );
    }
    return SizedBox(width: previewSize, height: previewSize);
  }
}
