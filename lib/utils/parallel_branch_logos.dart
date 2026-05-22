import 'dart:typed_data';

import 'package:vanessa3/utils/branch_logo_pdf.dart';

/// Unduh logo cabang secara paralel dengan batas konkurensi.
Future<Map<String, Uint8List>> loadBranchLogosParallel(
  Iterable<String> branchIds, {
  int concurrency = 4,
}) async {
  final ids = branchIds
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();
  if (ids.isEmpty) return {};

  final out = <String, Uint8List>{};
  var index = 0;

  Future<void> worker() async {
    while (true) {
      final i = index;
      index++;
      if (i >= ids.length) return;
      final bid = ids[i];
      final bytes = await loadBranchLogoRasterBytesForPdf(bid);
      if (bytes != null && bytes.isNotEmpty) {
        out[bid] = bytes;
      }
    }
  }

  final workers = List.generate(
    concurrency.clamp(1, ids.length),
    (_) => worker(),
  );
  await Future.wait(workers);
  return out;
}
