import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'
    if (dart.library.html) '../../../utils/image_picker_stub.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/modules/kasir/logic/store_operational_types.dart';
import 'package:vanessa3/modules/kasir/logic/store_operational_utils.dart';

class StoreOperationalEntryForm extends StatelessWidget {
  const StoreOperationalEntryForm({
    super.key,
    required this.formKey,
    required this.kind,
    required this.onKindChanged,
    required this.category,
    required this.onCategoryChanged,
    required this.categories,
    required this.loadingCategories,
    required this.categoriesError,
    required this.amountController,
    required this.notesController,
    required this.submitting,
    required this.uploadingProof,
    required this.newProofX,
    required this.onPickProof,
    required this.onClearProof,
    required this.onOpenCategoryManager,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final StoreOperationalMoneyKind kind;
  final ValueChanged<StoreOperationalMoneyKind> onKindChanged;
  final String category;
  final ValueChanged<String> onCategoryChanged;
  final List<String> categories;
  final bool loadingCategories;
  final String? categoriesError;
  final TextEditingController amountController;
  final TextEditingController notesController;
  final bool submitting;
  final bool uploadingProof;
  final XFile? newProofX;
  final ValueChanged<ImageSource> onPickProof;
  final VoidCallback onClearProof;
  final VoidCallback onOpenCategoryManager;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      elevation: 0,
      color: cs.surfaceContainerLow.withValues(alpha: 0.65),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Entri baru',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<StoreOperationalMoneyKind>(
                segments: const [
                  ButtonSegment<StoreOperationalMoneyKind>(
                    value: StoreOperationalMoneyKind.expense,
                    label: Text('Pengeluaran'),
                    icon: Icon(Icons.south_east, size: 18),
                  ),
                  ButtonSegment<StoreOperationalMoneyKind>(
                    value: StoreOperationalMoneyKind.income,
                    label: Text('Pemasukan'),
                    icon: Icon(Icons.north_east, size: 18),
                  ),
                ],
                selected: {kind},
                onSelectionChanged: (s) => onKindChanged(s.first),
              ),
              const SizedBox(height: 12),
              if (categoriesError != null) ...[
                Text(
                  categoriesError!,
                  style: TextStyle(
                    color: cs.error,
                    fontSize: AppTypography.bodySmall,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              DropdownButtonFormField<String>(
                key: ValueKey<String>('cat_$kind'),
                initialValue: categories.contains(category)
                    ? category
                    : (categories.isNotEmpty ? categories.first : null),
                decoration: InputDecoration(
                  labelText: 'Kategori',
                  border: const OutlineInputBorder(),
                  suffixIcon: loadingCategories
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                items: categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (loadingCategories || categories.isEmpty)
                    ? null
                    : (v) {
                        if (v != null) onCategoryChanged(v);
                      },
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpenCategoryManager,
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text('Kelola kategori'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nominal (Rp)',
                  border: OutlineInputBorder(),
                  prefixText: 'Rp ',
                ),
                validator: (value) {
                  if (StoreOperationalUtils.parseAmount(value ?? '') <= 0) {
                    return 'Nominal wajib diisi';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Keterangan (opsional)',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (submitting || uploadingProof)
                          ? null
                          : () => onPickProof(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Kamera'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (submitting || uploadingProof)
                          ? null
                          : () => onPickProof(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Galeri'),
                    ),
                  ),
                ],
              ),
              if (newProofX != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Foto bukti dipilih',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ),
                    TextButton(
                      onPressed:
                          (submitting || uploadingProof) ? null : onClearProof,
                      child: const Text('Hapus'),
                    ),
                  ],
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: kIsWeb
                      ? Container(
                          height: 160,
                          color: cs.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: const Text('Preview tidak tersedia di web'),
                        )
                      : Image.file(
                          File(newProofX!.path),
                          height: 160,
                          fit: BoxFit.cover,
                        ),
                ),
              ],
              if (uploadingProof) ...[
                const SizedBox(height: 10),
                const Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Mengupload foto bukti...'),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: submitting ? null : onSubmit,
                child: submitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Simpan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
