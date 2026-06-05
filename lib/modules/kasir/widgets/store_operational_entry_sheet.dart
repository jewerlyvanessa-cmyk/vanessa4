import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'
    if (dart.library.html) '../../../utils/image_picker_stub.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/modules/kasir/logic/store_operational_utils.dart';
import 'package:vanessa3/utils/file_uploader.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/store_operational_print.dart';

Future<void> showStoreOperationalEntrySheet({
  required BuildContext context,
  required Map<String, dynamic> entry,
  required String branchId,
  required String branchLabel,
  required String branchIdForLogo,
  required String? authToken,
  required ImagePicker picker,
  required ValueChanged<Map<String, dynamic>> onEntryUpdated,
}) async {
  final proofUrl = StoreOperationalUtils.normalizeProofUrl(
    entry['proof_photo_url'],
  );
  final entryId = entry['entry_id']?.toString() ?? '';

  final money = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  final dt = DateTime.tryParse(entry['created_at']?.toString() ?? '');
  final whenStr = dt != null
      ? DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(dt.toLocal())
      : '—';
  final income = StoreOperationalUtils.entryIsIncome(entry);
  final cat = entry['category']?.toString() ?? '—';
  final notes = entry['notes']?.toString() ?? '';
  final amt = entry['amount'];
  final value = amt is num ? amt.toDouble() : double.tryParse('$amt') ?? 0;

  Future<void> uploadOrChangePhoto() async {
    if (branchId.isEmpty || entryId.isEmpty) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Kamera'),
              onTap: () => Navigator.of(c).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeri'),
              onTap: () => Navigator.of(c).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (picked == null) return;
    if (kIsWeb) return;

    final url = await FileUploader.uploadImage(
      File(picked.path),
      token: authToken,
    );
    if (url == null || url.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal upload foto bukti.')),
        );
      }
      return;
    }

    final res = await ApiClient.post(
      '/store-operational/$entryId/proof-photo',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'branch_id': int.tryParse(branchId),
        'proof_photo_url': url,
      }),
    );
    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        onEntryUpdated(Map<String, dynamic>.from(decoded));
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto bukti tersimpan.')),
        );
      }
    } else if (context.mounted) {
      final msg = StoreOperationalUtils.messageFromStoreOpsBody(
        res.body,
        res.statusCode,
        'Gagal menyimpan foto bukti',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Bukti entri',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 10),
            Text('Jenis: ${income ? 'Pemasukan' : 'Pengeluaran'}'),
            Text('Kategori: $cat'),
            Text('Nominal: ${money.format(value)}'),
            Text('Waktu: $whenStr'),
            if (notes.trim().isNotEmpty) Text('Ket: $notes'),
            const SizedBox(height: 12),
            if (proofUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  proofUrl,
                  height: 180,
                  fit: BoxFit.cover,
                  headers: NetworkConfig.imageHeaders,
                  errorBuilder: (_, _, _) =>
                      const Text('Gagal memuat foto bukti.'),
                ),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await printStoreOperationalReceiptPdf(
                  context,
                  branchLabel: branchLabel,
                  branchIdForLogo: branchIdForLogo,
                  entry: entry,
                );
              },
              icon: const Icon(Icons.print_outlined),
              label: const Text('Cetak bukti'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await uploadOrChangePhoto();
              },
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(
                proofUrl == null ? 'Upload foto bukti' : 'Ubah foto bukti',
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Tutup'),
            ),
          ],
        ),
      ),
    ),
  );
}
