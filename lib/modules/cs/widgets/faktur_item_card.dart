import 'package:flutter/material.dart';
import 'package:vanessa3/modules/cs/logic/faktur_page_utils.dart';
import 'package:vanessa3/utils/network_config.dart';

class FakturItemCard extends StatelessWidget {
  const FakturItemCard({
    super.key,
    required this.item,
    required this.dense,
  });

  final dynamic item;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final photoUrl = FakturPageUtils.photoUrl(item['photo_produk']);
    final hargaPerGram = double.tryParse(
          (item['harga_per_gram'] ?? 0).toString(),
        )
            ?.toStringAsFixed(0)
            .replaceAllMapped(
              RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
              (Match m) => '${m[1]}.',
            ) ??
        (item['harga_per_gram'] ?? 0).toString();

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Kode: ${item['kode_produk'] ?? '-'}',
          style: TextStyle(fontSize: dense ? 13 : null),
        ),
        Text(
          item['nama_item'] ?? 'Unknown Item',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: dense ? 14 : 16,
          ),
        ),
        Text(
          'Berat: ${item['weight'] ?? '-'}g',
          style: TextStyle(fontSize: dense ? 13 : null),
        ),
        Text(
          'Harga/g: Rp $hargaPerGram',
          style: TextStyle(fontSize: dense ? 13 : null),
        ),
        Text(
          'Total: Rp ${FakturPageUtils.fmtMoney(item['total'] ?? 0)}',
          style: TextStyle(fontSize: dense ? 13 : null),
        ),
      ],
    );

    Widget? photo;
    if (photoUrl != null) {
      photo = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: dense
            ? Image.network(
                photoUrl,
                width: 120,
                height: 90,
                fit: BoxFit.cover,
                headers: NetworkConfig.imageHeaders,
                errorBuilder: (_, _, _) => Container(
                  width: 120,
                  height: 90,
                  color: Colors.grey.shade200,
                  alignment: Alignment.center,
                  child: const Text(
                    'Gagal memuat foto',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    width: 120,
                    height: 90,
                    color: Colors.grey.shade100,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
              )
            : AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  headers: NetworkConfig.imageHeaders,
                  errorBuilder: (_, _, _) => Container(
                    color: Colors.grey.shade200,
                    alignment: Alignment.center,
                    child: const Text('Gagal memuat foto'),
                  ),
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    final expected = loadingProgress.expectedTotalBytes;
                    final loaded = loadingProgress.cumulativeBytesLoaded;
                    final value =
                        (expected != null && expected > 0) ? loaded / expected : null;
                    return Container(
                      color: Colors.grey.shade100,
                      alignment: Alignment.center,
                      child: CircularProgressIndicator(value: value),
                    );
                  },
                ),
              ),
      );
    }

    return Card(
      elevation: 1,
      margin: EdgeInsets.only(bottom: dense ? 6 : 8),
      child: Padding(
        padding: EdgeInsets.all(dense ? 10 : 16),
        child: dense && photo != null
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  photo,
                  const SizedBox(width: 10),
                  Expanded(child: details),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (photo != null) ...[
                    photo,
                    SizedBox(height: dense ? 8 : 12),
                  ],
                  details,
                ],
              ),
      ),
    );
  }
}
