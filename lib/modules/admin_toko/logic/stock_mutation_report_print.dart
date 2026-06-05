import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:vanessa3/modules/admin_toko/logic/stock_mutation_utils.dart';
import 'package:vanessa3/utils/branch_logo_pdf.dart';

Future<void> printStockMutationReport({
  required List<dynamic> rows,
  required String branchId,
  required String periodLabel,
  required String filterLabel,
}) async {
  if (rows.isEmpty) return;

  final logoBytes = await loadBranchLogoRasterBytesForPdf(branchId.trim());

  final doc = pw.Document();
  final df = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');
  final sorted = List<Map<String, dynamic>>.from(
    rows.map((e) => Map<String, dynamic>.from(e as Map)),
  )..sort((a, b) {
      final ta = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return ta.compareTo(tb);
    });

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      header: pdfMultiPageHeaderLaporanCabang(
        title: 'LAPORAN MUTASI STOK',
        leftLogoBytes: logoBytes,
        subtitles: [
          PdfLaporanHeaderSubtitleLine('Periode: $periodLabel'),
          PdfLaporanHeaderSubtitleLine('Filter: $filterLabel'),
        ],
      ),
      build: (ctx) => [
        pw.TableHelper.fromTextArray(
          headers: const ['No', 'Waktu', 'Item', 'Jenis', 'Qty', 'Keterangan'],
          data: [
            for (var i = 0; i < sorted.length; i++)
              [
                '${i + 1}',
                () {
                  final d = DateTime.tryParse(
                    sorted[i]['created_at']?.toString() ?? '',
                  );
                  return d == null ? '-' : df.format(d.toLocal());
                }(),
                (sorted[i]['item_name'] ?? '-').toString(),
                StockMutationUtils.typeLabel(sorted[i]),
                (sorted[i]['quantity'] ?? '-').toString(),
                StockMutationUtils.description(sorted[i]),
              ],
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignment: pw.Alignment.centerLeft,
        ),
      ],
    ),
  );

  await Printing.layoutPdf(
    name: 'mutasi_stok_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
    onLayout: (_) async => doc.save(),
  );
}
