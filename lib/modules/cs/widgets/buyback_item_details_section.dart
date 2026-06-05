import 'package:flutter/material.dart';
import 'package:vanessa3/modules/cs/logic/buyback_form_constants.dart';
import 'package:vanessa3/utils/order_item_kategori_jenis.dart';

/// Bagian detail item barang pada form buyback CS.
class BuybackItemDetailsSection extends StatelessWidget {
  const BuybackItemDetailsSection({
    super.key,
    required this.kodeProdukController,
    required this.kategoriController,
    required this.jenisController,
    required this.notaJual,
    required this.selectedTipeBarang,
    required this.tipeController,
    required this.namaItemController,
    required this.materialController,
    required this.kadarController,
    required this.beratController,
    required this.quantityController,
    required this.isDataFromOrderItems,
    required this.onKategoriChanged,
    required this.onTipeBarangChanged,
  });

  final TextEditingController kodeProdukController;
  final TextEditingController kategoriController;
  final TextEditingController jenisController;
  final String notaJual;
  final String? selectedTipeBarang;
  final TextEditingController tipeController;
  final TextEditingController namaItemController;
  final TextEditingController materialController;
  final TextEditingController kadarController;
  final TextEditingController beratController;
  final TextEditingController quantityController;
  final bool isDataFromOrderItems;
  final ValueChanged<String?> onKategoriChanged;
  final ValueChanged<String?> onTipeBarangChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Kode Produk')),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: kodeProdukController,
                decoration: const InputDecoration(
                  hintText: 'Kode produk (opsional)',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Kategori')),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: kategoriController.text.isNotEmpty
                    ? kategoriController.text
                    : null,
                decoration: const InputDecoration(hintText: 'Kategori'),
                items: const [
                  DropdownMenuItem(
                    value: 'PERHIASAN',
                    child: Text('PERHIASAN'),
                  ),
                  DropdownMenuItem(
                    value: 'AKSESORIES',
                    child: Text('AKSESORIES'),
                  ),
                  DropdownMenuItem(
                    value: 'LOGAM MULIA',
                    child: Text('LOGAM MULIA'),
                  ),
                ],
                onChanged: onKategoriChanged,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Kategori wajib dipilih';
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
            const SizedBox(width: 100, child: Text('Jenis')),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue:
                    jenisController.text.isNotEmpty ? jenisController.text : null,
                decoration: const InputDecoration(hintText: 'Jenis'),
                items: orderItemJenisOptionsForKategori(kategoriController.text)
                    .map(
                      (jenis) => DropdownMenuItem(
                        value: jenis,
                        child: Text(jenis),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  jenisController.text = value ?? '';
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Jenis wajib dipilih';
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
            const SizedBox(width: 100, child: Text('Tipe Barang')),
            const SizedBox(width: 8),
            Expanded(
              child: notaJual == 'TIDAK_ADA'
                  ? DropdownButtonFormField<String>(
                      initialValue: selectedTipeBarang,
                      decoration: const InputDecoration(
                        hintText: 'Pilih Tipe Barang',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'BIASA',
                          child: Text('BIASA'),
                        ),
                        DropdownMenuItem(
                          value: 'GRESS',
                          child: Text('GRESS'),
                        ),
                      ],
                      onChanged: onTipeBarangChanged,
                    )
                  : TextFormField(
                      controller: tipeController,
                      decoration: const InputDecoration(
                        hintText: 'Tipe Barang',
                      ),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Nama Item')),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: namaItemController,
                decoration: const InputDecoration(hintText: 'Nama item'),
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
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Material')),
            const SizedBox(width: 8),
            Expanded(
              child: Autocomplete<String>(
                optionsBuilder: (textEditingValue) {
                  return BuybackFormConstants.materialSuggestions.where(
                    (material) => material.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    ),
                  );
                },
                onSelected: (selection) {
                  materialController.text = selection;
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  return TextFormField(
                    controller: materialController,
                    focusNode: focusNode,
                    readOnly: isDataFromOrderItems,
                    decoration: InputDecoration(
                      hintText: 'Material',
                      filled: isDataFromOrderItems,
                      fillColor: isDataFromOrderItems
                          ? const Color(0xFFF5F5F5)
                          : null,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Material wajib diisi';
                      }
                      return null;
                    },
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Kadar')),
            const SizedBox(width: 8),
            Expanded(
              child: Autocomplete<String>(
                optionsBuilder: (textEditingValue) {
                  return BuybackFormConstants.kadarSuggestions.where(
                    (kadar) => kadar.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    ),
                  );
                },
                onSelected: (selection) {
                  kadarController.text = selection;
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  return TextFormField(
                    controller: kadarController,
                    focusNode: focusNode,
                    readOnly: isDataFromOrderItems,
                    decoration: InputDecoration(
                      hintText: 'Kadar',
                      filled: isDataFromOrderItems,
                      fillColor: isDataFromOrderItems
                          ? const Color(0xFFF5F5F5)
                          : null,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Kadar wajib diisi';
                      }
                      return null;
                    },
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Berat')),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: beratController,
                decoration: const InputDecoration(hintText: 'Berat (gram)'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Berat wajib diisi';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Berat harus berupa angka';
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
            const SizedBox(width: 100, child: Text('Quantity')),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: quantityController,
                decoration: const InputDecoration(hintText: 'Quantity'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Quantity wajib diisi';
                  }
                  if (int.tryParse(value) == null) {
                    return 'Quantity harus berupa angka';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
