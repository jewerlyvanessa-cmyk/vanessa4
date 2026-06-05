import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vanessa3/modules/cs/logic/jual_form_utils.dart';
import 'package:vanessa3/shared_widgets/cs_order_photo_field.dart';

/// Harga, diskon, total, dan foto pada form jual CS.
class JualPricingSection extends StatelessWidget {
  const JualPricingSection({
    super.key,
    required this.saleType,
    required this.hasFoto,
    required this.fotoBytes,
    required this.fotoFile,
    required this.hargaPerGramController,
    required this.diskonController,
    required this.jumlahController,
    required this.onRecalculate,
    required this.onPickFotoCamera,
    required this.onPickFotoGallery,
  });

  final String saleType;
  final bool hasFoto;
  final Uint8List? fotoBytes;
  final File? fotoFile;
  final TextEditingController hargaPerGramController;
  final TextEditingController diskonController;
  final TextEditingController jumlahController;
  final VoidCallback onRecalculate;
  final VoidCallback onPickFotoCamera;
  final VoidCallback onPickFotoGallery;

  String _formatNumber(String value) =>
      JualFormUtils.formatNumberWithSeparators(value);

  double _parseNumber(String value) =>
      JualFormUtils.parseNumberWithSeparators(value);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 100,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Harga/gram'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: hargaPerGramController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Rp per gram',
                ),
                onChanged: (_) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    onRecalculate();
                  });
                },
                onEditingComplete: () {
                  hargaPerGramController.text =
                      _formatNumber(hargaPerGramController.text);
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Harga per gram wajib diisi';
                  }
                  if (_parseNumber(value) <= 0) {
                    return 'Harga per gram harus lebih dari 0';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const SizedBox(
              width: 100,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Diskon (%)'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: diskonController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Diskon dalam persen',
                ),
                onChanged: (_) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    onRecalculate();
                  });
                },
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    final discount = double.tryParse(value);
                    if (discount == null || discount < 0 || discount > 100) {
                      return 'Diskon harus antara 0-100';
                    }
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const SizedBox(
              width: 100,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Jumlah'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: jumlahController,
                readOnly: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: 'Total otomatis',
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        CsOrderPhotoField(
          hasPhoto: hasFoto,
          imageBytes: fotoBytes,
          imageFile: fotoFile,
          onCamera: onPickFotoCamera,
          onGallery: onPickFotoGallery,
          requiredMessage:
              saleType == 'qsr' && !hasFoto ? 'Foto WAJIB untuk QSR' : null,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
