import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:vanessa3/shared_widgets/cs_order_photo_field.dart';

/// Bagian harga awal, untung/rugi, kondisi barang, dan foto pada form buyback CS.
class BuybackPriceConditionSection extends StatelessWidget {
  const BuybackPriceConditionSection({
    super.key,
    required this.hargaBeliController,
    required this.untungRugi,
    required this.onUntungRugiChanged,
    required this.kondisiFisik,
    required this.onKondisiFisikChanged,
    required this.catatanKondisiController,
    required this.penyesuaianBeratController,
    required this.hargaPerGramController,
    required this.potonganKondisiController,
    required this.nilaiUntungRugiController,
    required this.nilaiResaleController,
    required this.fotoXFile,
    required this.fotoBytes,
    required this.onPickFotoCamera,
    required this.onPickFotoGallery,
  });

  final TextEditingController hargaBeliController;
  final String untungRugi;
  final ValueChanged<String> onUntungRugiChanged;
  final String kondisiFisik;
  final ValueChanged<String> onKondisiFisikChanged;
  final TextEditingController catatanKondisiController;
  final TextEditingController penyesuaianBeratController;
  final TextEditingController hargaPerGramController;
  final TextEditingController potonganKondisiController;
  final TextEditingController nilaiUntungRugiController;
  final TextEditingController nilaiResaleController;
  final XFile? fotoXFile;
  final Uint8List? fotoBytes;
  final VoidCallback onPickFotoCamera;
  final VoidCallback onPickFotoGallery;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Harga Awal')),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: hargaBeliController,
                decoration: const InputDecoration(
                  hintText: 'Harga Awal (Rp)',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Harga awal wajib diisi';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Harga awal harus berupa angka';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Untung/Rugi')),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                spacing: 8.0,
                children: [
                  ChoiceChip(
                    label: const Text('UNTUNG'),
                    selected: untungRugi == 'UNTUNG',
                    onSelected: (selected) {
                      if (selected) onUntungRugiChanged('UNTUNG');
                    },
                  ),
                  ChoiceChip(
                    label: const Text('RUGI'),
                    selected: untungRugi == 'RUGI',
                    onSelected: (selected) {
                      if (selected) onUntungRugiChanged('RUGI');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Kondisi Fisik')),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                spacing: 8.0,
                children: [
                  ChoiceChip(
                    label: const Text('BAIK'),
                    selected: kondisiFisik == 'BAIK',
                    onSelected: (selected) {
                      if (selected) onKondisiFisikChanged('BAIK');
                    },
                  ),
                  ChoiceChip(
                    label: const Text('RUSAK'),
                    selected: kondisiFisik == 'RUSAK',
                    onSelected: (selected) {
                      if (selected) onKondisiFisikChanged('RUSAK');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Catatan Kondisi')),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: catatanKondisiController,
                decoration: const InputDecoration(hintText: 'Catatan Kondisi'),
                maxLines: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Penyesuaian Berat')),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: penyesuaianBeratController,
                decoration: const InputDecoration(hintText: 'Penyesuaian Berat'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Harga Per Gram')),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: hargaPerGramController,
                decoration: const InputDecoration(
                  hintText: 'Harga Per Gram (Rp)',
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Potongan Kondisi')),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: potonganKondisiController,
                decoration: const InputDecoration(
                  hintText: 'Potongan Kondisi (Rp)',
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Nilai Untung/Rugi')),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: nilaiUntungRugiController,
                readOnly: true,
                decoration: const InputDecoration(
                  hintText: 'Nilai untung/rugi (otomatis)',
                  filled: true,
                  fillColor: Color(0xFFF5F5F5),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Nilai Resale')),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: nilaiResaleController,
                readOnly: true,
                decoration: const InputDecoration(
                  hintText: 'Nilai Resale (otomatis)',
                  filled: true,
                  fillColor: Color(0xFFF5F5F5),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        CsOrderPhotoField(
          label: 'Foto Kondisi',
          hasPhoto: fotoXFile != null || fotoBytes != null,
          imageBytes: fotoBytes,
          imageFile: fotoXFile != null ? File(fotoXFile!.path) : null,
          onCamera: onPickFotoCamera,
          onGallery: onPickFotoGallery,
          requiredMessage: (fotoXFile == null && fotoBytes == null)
              ? 'Foto barang wajib diupload'
              : null,
        ),
      ],
    );
  }
}
