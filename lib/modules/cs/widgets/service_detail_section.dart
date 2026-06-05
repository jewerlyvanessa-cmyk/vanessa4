import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:vanessa3/shared_widgets/cs_order_photo_field.dart';
import 'package:vanessa3/utils/app_date_picker.dart';

/// Jenis service, kelengkapan, catatan, estimasi selesai, dan foto.
class ServiceDetailSection extends StatelessWidget {
  const ServiceDetailSection({
    super.key,
    required this.jenisService,
    required this.onJenisServiceChanged,
    required this.kelengkapan,
    required this.onKelengkapanChanged,
    required this.keteranganController,
    required this.estimasiSelesaiController,
    required this.onEstimasiSelesaiChanged,
    required this.fotoXFile,
    required this.fotoBytes,
    required this.onPickFotoCamera,
    required this.onPickFotoGallery,
  });

  final String jenisService;
  final ValueChanged<String> onJenisServiceChanged;
  final Map<String, bool> kelengkapan;
  final void Function(String key, bool value) onKelengkapanChanged;
  final TextEditingController keteranganController;
  final TextEditingController estimasiSelesaiController;
  final ValueChanged<String> onEstimasiSelesaiChanged;
  final XFile? fotoXFile;
  final Uint8List? fotoBytes;
  final VoidCallback onPickFotoCamera;
  final VoidCallback onPickFotoGallery;

  static const _serviceOptions = [
    'Patri',
    'Cuci',
    'Sambung',
    'Ubah Ukuran',
    'Ganti Batu',
    'Lainnya',
  ];

  static const _kelengkapanKeys = ['Barang', 'Surat', 'Identitas'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'KETERANGAN',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const SizedBox(
              width: 120,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Jenis Service'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: _serviceOptions
                    .map(
                      (jenis) => ChoiceChip(
                        label: Text(jenis),
                        selected: jenisService == jenis,
                        onSelected: (selected) {
                          if (selected) onJenisServiceChanged(jenis);
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const SizedBox(
              width: 120,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Kelengkapan'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _kelengkapanKeys
                    .map(
                      (key) => CheckboxListTile(
                        title: Text(key),
                        value: kelengkapan[key] ?? false,
                        onChanged: (value) =>
                            onKelengkapanChanged(key, value ?? false),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Catatan (opsional)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: keteranganController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Keluhan / Keterangan Perbaikan',
            border: OutlineInputBorder(),
            hintText:
                'Contoh: Rusak, Bengkok, Gemuk, dll (boleh dikosongkan)',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const SizedBox(
              width: 120,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Estimasi Selesai'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: estimasiSelesaiController,
                readOnly: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Tanggal estimasi selesai',
                ),
                onTap: () async {
                  final picked = await showAppDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 4)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    onEstimasiSelesaiChanged(
                      '${picked.day.toString().padLeft(2, '0')}/'
                      '${picked.month.toString().padLeft(2, '0')}/'
                      '${(picked.year % 100).toString().padLeft(2, '0')}',
                    );
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        CsOrderPhotoField(
          hasPhoto: fotoXFile != null || fotoBytes != null,
          imageBytes: fotoBytes,
          imageFile: fotoXFile != null ? File(fotoXFile!.path) : null,
          onCamera: onPickFotoCamera,
          onGallery: onPickFotoGallery,
          requiredMessage: (fotoXFile == null && fotoBytes == null)
              ? 'Foto barang WAJIB untuk service'
              : null,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
