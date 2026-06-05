import 'package:flutter/material.dart';
import 'package:vanessa3/modules/cs/logic/cs_form_utils.dart';

/// Jenis barang, detail item, dan biaya pada form service CS.
class ServiceItemPricingSection extends StatelessWidget {
  const ServiceItemPricingSection({
    super.key,
    required this.jenisBarang,
    required this.onJenisBarangChanged,
    required this.namaItemController,
    required this.beratController,
    required this.materialController,
    required this.kadarController,
    required this.totalBiayaController,
    required this.uangMukaController,
  });

  final String jenisBarang;
  final ValueChanged<String> onJenisBarangChanged;
  final TextEditingController namaItemController;
  final TextEditingController beratController;
  final TextEditingController materialController;
  final TextEditingController kadarController;
  final TextEditingController totalBiayaController;
  final TextEditingController uangMukaController;

  static const _jenisOptions = [
    'KALUNG',
    'GELANG',
    'ANTING',
    'CINCIN',
    'LIONTIN',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 120,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Jenis'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: _jenisOptions
                    .map(
                      (jenis) => ChoiceChip(
                        label: Text(jenis),
                        selected: jenisBarang == jenis,
                        onSelected: (selected) {
                          if (selected) onJenisBarangChanged(jenis);
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const SizedBox(
              width: 120,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Nama Barang'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: namaItemController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Contoh: Gelang Emas',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Nama barang wajib diisi';
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
              width: 120,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Berat (gram)'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: beratController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(border: OutlineInputBorder()),
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
                child: Text('Material'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: materialController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Contoh: Emas, Perak, Tembaga',
                ),
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
                child: Text('Kadar Kemurnian'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: kadarController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Contoh: 70%, 22K',
                ),
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
                child: Text('Estimasi Biaya'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: totalBiayaController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixText: 'Rp ',
                  hintText: 'Contoh: 150000',
                ),
                validator: (value) {
                  final raw = (value ?? '').trim();
                  if (raw.isEmpty) return 'Estimasi biaya wajib diisi';
                  final v = csParseMoney(raw);
                  if (v < 0) return 'Estimasi biaya tidak valid';
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
              width: 120,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Uang Muka'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: uangMukaController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixText: 'Rp ',
                  hintText: 'Opsional (boleh 0)',
                ),
                validator: (value) {
                  final dp = csParseMoney(value ?? '');
                  final total = csParseMoney(totalBiayaController.text);
                  if (dp < 0) return 'Uang muka tidak valid';
                  if (dp > total) return 'Uang muka melebihi total biaya';
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
