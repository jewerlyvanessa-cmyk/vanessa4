import 'package:flutter/material.dart';
import 'package:vanessa3/modules/cs/logic/custom_form_constants.dart';
import 'package:vanessa3/modules/cs/logic/cs_form_utils.dart';

class CustomSpecSection extends StatelessWidget {
  const CustomSpecSection({
    super.key,
    required this.jenisBarang,
    required this.onJenisChanged,
    required this.asalMaterial,
    required this.onAsalMaterialChanged,
    required this.asalTambahan,
    required this.onAsalTambahanChanged,
    required this.totalBiayaController,
    required this.uangMukaController,
    required this.namaItemController,
    required this.spesifikasiController,
    required this.materialController,
    required this.materialTambahanController,
    required this.kadarController,
    required this.beratTargetController,
    required this.estimasiWaktuController,
  });

  final String jenisBarang;
  final ValueChanged<String> onJenisChanged;
  final String asalMaterial;
  final ValueChanged<String> onAsalMaterialChanged;
  final String asalTambahan;
  final ValueChanged<String> onAsalTambahanChanged;
  final TextEditingController totalBiayaController;
  final TextEditingController uangMukaController;
  final TextEditingController namaItemController;
  final TextEditingController spesifikasiController;
  final TextEditingController materialController;
  final TextEditingController materialTambahanController;
  final TextEditingController kadarController;
  final TextEditingController beratTargetController;
  final TextEditingController estimasiWaktuController;

  Widget _labelRow(String label, Widget field) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(label),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: field),
      ],
    );
  }

  Widget _choiceChips({
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final opt in options)
          ChoiceChip(
            label: Text(opt),
            selected: selected == opt,
            onSelected: (_) => onSelected(opt),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'SPESIFIKASI BARANG CUSTOM',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        _labelRow(
          'Jenis',
          _choiceChips(
            options: CustomFormConstants.jenisBarangOptions,
            selected: jenisBarang,
            onSelected: onJenisChanged,
          ),
        ),
        const SizedBox(height: 12),
        _labelRow(
          'Estimasi Biaya',
          TextFormField(
            controller: totalBiayaController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              prefixText: 'Rp ',
              hintText: 'Contoh: 500000',
            ),
            validator: (value) {
              final raw = (value ?? '').trim();
              if (raw.isEmpty) return 'Estimasi biaya wajib diisi';
              if (csParseMoney(raw) < 0) return 'Estimasi biaya tidak valid';
              return null;
            },
          ),
        ),
        const SizedBox(height: 12),
        _labelRow(
          'Uang Muka',
          TextFormField(
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
        const SizedBox(height: 12),
        _labelRow(
          'Nama Barang',
          TextFormField(
            controller: namaItemController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Contoh: Cincin Pernikahan Custom',
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Nama barang wajib diisi';
              }
              return null;
            },
          ),
        ),
        const SizedBox(height: 12),
        _labelRow(
          'Spesifikasi Detail',
          TextFormField(
            controller: spesifikasiController,
            maxLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText:
                  'Contoh: Ukuran cincin 18, dengan batu mulia ruby, warna emas kuning',
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Spesifikasi wajib diisi';
              }
              return null;
            },
          ),
        ),
        const SizedBox(height: 12),
        _labelRow(
          'Material',
          TextFormField(
            controller: materialController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Contoh: Emas, Perak, Tembaga',
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Material wajib diisi';
              }
              return null;
            },
          ),
        ),
        const SizedBox(height: 12),
        _labelRow(
          'Asal Material',
          _choiceChips(
            options: CustomFormConstants.asalMaterialOptions,
            selected: asalMaterial,
            onSelected: onAsalMaterialChanged,
          ),
        ),
        const SizedBox(height: 12),
        _labelRow(
          'Tambahan',
          TextFormField(
            controller: materialTambahanController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Contoh: Berlian, Ruby, Safir',
            ),
          ),
        ),
        const SizedBox(height: 12),
        _labelRow(
          'Asal Tambahan',
          _choiceChips(
            options: CustomFormConstants.asalMaterialOptions,
            selected: asalTambahan,
            onSelected: onAsalTambahanChanged,
          ),
        ),
        const SizedBox(height: 12),
        _labelRow(
          'Kadar Kemurnian',
          TextFormField(
            controller: kadarController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Contoh: 70%, 22K',
            ),
          ),
        ),
        const SizedBox(height: 12),
        _labelRow(
          'Berat Target (gram)',
          TextFormField(
            controller: beratTargetController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        const SizedBox(height: 12),
        _labelRow(
          'Estimasi Waktu',
          TextFormField(
            controller: estimasiWaktuController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Contoh: 2 minggu, 3 hari, dll',
            ),
          ),
        ),
      ],
    );
  }
}
