import 'package:flutter/material.dart';

class FakturServiceSection extends StatelessWidget {
  const FakturServiceSection({
    super.key,
    required this.fields,
    required this.dense,
  });

  final Map<String, String> fields;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) return const SizedBox.shrink();

    Widget row(String key, String label) {
      final v = fields[key] ?? '-';
      return Padding(
        padding: EdgeInsets.only(bottom: dense ? 4 : 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: dense ? 108 : 132,
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: dense ? 12 : null,
                ),
              ),
            ),
            Expanded(
              child: Text(v, style: TextStyle(fontSize: dense ? 12 : null)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Detail servis',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        SizedBox(height: dense ? 4 : 8),
        Card(
          elevation: 2,
          child: Padding(
            padding: EdgeInsets.all(dense ? 10 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row('jenis_service', 'Jenis service'),
                row('kelengkapan', 'Kelengkapan'),
                row('catatan', 'Catatan'),
                row(
                  'estimasi_biaya',
                  fields['service_biaya_row_label'] ?? 'Estimasi biaya',
                ),
                row('estimasi_selesai', 'Estimasi selesai'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
