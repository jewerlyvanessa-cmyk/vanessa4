import 'package:flutter/material.dart';
import 'package:vanessa3/utils/order_item_kategori_jenis.dart';

/// Field kategori, jenis, tipe, nama, material, kadar, berat, qty pada form jual CS.
class JualItemFormSection extends StatelessWidget {
  const JualItemFormSection({
    super.key,
    required this.saleType,
    required this.kategoriController,
    required this.jenisController,
    required this.tipeController,
    required this.namaItemController,
    required this.materialController,
    required this.kadarController,
    required this.beratController,
    required this.qtyController,
    required this.materialChoice,
    required this.onKategoriChanged,
    required this.onJenisChanged,
    required this.onTipeChanged,
    required this.onMaterialChoiceChanged,
    required this.onRecalculate,
  });

  final String saleType;
  final TextEditingController kategoriController;
  final TextEditingController jenisController;
  final TextEditingController tipeController;
  final TextEditingController namaItemController;
  final TextEditingController materialController;
  final TextEditingController kadarController;
  final TextEditingController beratController;
  final TextEditingController qtyController;
  final String materialChoice;
  final ValueChanged<String> onKategoriChanged;
  final ValueChanged<String> onJenisChanged;
  final ValueChanged<String> onTipeChanged;
  final void Function(String choice, {required bool clearMaterialText})
      onMaterialChoiceChanged;
  final VoidCallback onRecalculate;

  bool get _fromStock => saleType == 'from_stock';
  bool get _manualEntry =>
      saleType == 'unregistered' || saleType == 'qsr';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_fromStock)
          Row(
            children: [
              const SizedBox(
                width: 100,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Kategori'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: kategoriController,
                  readOnly: true,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'Otomatis dari item',
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                ),
              ),
            ],
          ),
        if (_fromStock) const SizedBox(height: 12),
        if (!_fromStock)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Kategori *'),
              const SizedBox(height: 8),
              if (_manualEntry)
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: [
                    ChoiceChip(
                      label: const Text('PERHIASAN'),
                      selected: kategoriController.text == 'PERHIASAN',
                      onSelected: (selected) {
                        if (selected) onKategoriChanged('PERHIASAN');
                      },
                    ),
                    ChoiceChip(
                      label: const Text('AKSESORIES'),
                      selected: kategoriController.text == 'AKSESORIES',
                      onSelected: (selected) {
                        if (selected) onKategoriChanged('AKSESORIES');
                      },
                    ),
                    ChoiceChip(
                      label: const Text('LOGAM MULIA'),
                      selected: kategoriController.text == 'LOGAM MULIA',
                      onSelected: (selected) {
                        if (selected) onKategoriChanged('LOGAM MULIA');
                      },
                    ),
                  ],
                )
              else
                TextFormField(
                  controller: kategoriController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Kategori item',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Kategori wajib diisi';
                    }
                    return null;
                  },
                ),
            ],
          ),
        if (!_fromStock) const SizedBox(height: 12),
        _fromStock
            ? Row(
                children: [
                  const SizedBox(
                    width: 100,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Jenis'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: jenisController,
                      readOnly: true,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: 'Otomatis dari item',
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Jenis *'),
                  const SizedBox(height: 8),
                  _manualEntry
                      ? Wrap(
                          spacing: 8.0,
                          runSpacing: 8.0,
                          children: orderItemJenisOptionsForKategori(
                            kategoriController.text,
                          )
                              .map(
                                (jenis) => ChoiceChip(
                                  label: Text(jenis),
                                  selected: jenisController.text == jenis,
                                  onSelected: (selected) {
                                    if (selected) onJenisChanged(jenis);
                                  },
                                ),
                              )
                              .toList(),
                        )
                      : TextFormField(
                          controller: jenisController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Jenis item',
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Jenis wajib diisi';
                            }
                            return null;
                          },
                        ),
                ],
              ),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 100,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_fromStock ? 'Tipe Barang' : 'Tipe Barang *'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _fromStock
                  ? TextFormField(
                      controller: tipeController,
                      readOnly: true,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: 'Otomatis dari item',
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                    )
                  : Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: [
                        ChoiceChip(
                          label: const Text('BIASA'),
                          selected: tipeController.text == 'BIASA',
                          onSelected: (selected) {
                            if (selected) onTipeChanged('BIASA');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('GRESS'),
                          selected: tipeController.text == 'GRESS',
                          onSelected: (selected) {
                            if (selected) onTipeChanged('GRESS');
                          },
                        ),
                      ],
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
                child: Text('Nama Item'),
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
                readOnly: _fromStock,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Nama item wajib diisi';
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
                child: Text('Material'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _fromStock
                  ? TextFormField(
                      controller: materialController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Otomatis dari item (opsional)',
                      ),
                      readOnly: true,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('EMAS'),
                              selected: materialChoice == 'EMAS',
                              onSelected: (selected) {
                                if (!selected) return;
                                onMaterialChoiceChanged(
                                  'EMAS',
                                  clearMaterialText: false,
                                );
                              },
                            ),
                            ChoiceChip(
                              label: const Text('PERAK'),
                              selected: materialChoice == 'PERAK',
                              onSelected: (selected) {
                                if (!selected) return;
                                onMaterialChoiceChanged(
                                  'PERAK',
                                  clearMaterialText: false,
                                );
                              },
                            ),
                            ChoiceChip(
                              label: const Text('Lainnya'),
                              selected: materialChoice == 'LAINNYA',
                              onSelected: (selected) {
                                if (!selected) return;
                                onMaterialChoiceChanged(
                                  'LAINNYA',
                                  clearMaterialText: true,
                                );
                              },
                            ),
                          ],
                        ),
                        if (materialChoice == 'LAINNYA') ...[
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: materialController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Tulis material (contoh: PLATINA)',
                            ),
                          ),
                        ],
                      ],
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
                child: Text('Kadar'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: kadarController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Contoh: 70%, 22K (opsional)',
                ),
                readOnly: _fromStock,
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
                child: Text('Berat'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: beratController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'gram',
                ),
                readOnly: _fromStock,
                onChanged: !_fromStock
                    ? (_) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          onRecalculate();
                        });
                      }
                    : null,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Berat wajib diisi';
                  }
                  final weight = double.tryParse(value);
                  if (weight == null || weight <= 0) {
                    return 'Berat harus angka positif';
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
                child: Text('Qty'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Jumlah item',
                ),
                onChanged: (_) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    onRecalculate();
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Qty wajib diisi';
                  }
                  final qty = int.tryParse(value);
                  if (qty == null || qty <= 0) {
                    return 'Qty harus angka positif';
                  }
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
