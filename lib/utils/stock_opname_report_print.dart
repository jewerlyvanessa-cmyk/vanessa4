import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:vanessa3/shared_widgets/stock_status_filter_summary_header.dart';
import 'package:vanessa3/utils/branch_logo_pdf.dart';
import 'package:vanessa3/utils/stock_opname_session_snapshot.dart';

String _itemCode(Map<String, dynamic> i) =>
    (i['item_code'] ?? i['kode_produk'] ?? '-').toString();

String _opnameResultLabel({
  required String itemId,
  required Set<String> verifiedIds,
  required Set<String> missingIds,
}) {
  if (verifiedIds.contains(itemId)) return 'Terverifikasi';
  if (missingIds.contains(itemId)) return 'Hilang';
  return 'Belum scan';
}

/// Cetak dari snapshot sesi (mis. setelah simpan).
Future<void> printStockOpnameReportFromSnapshot(
  BuildContext context,
  StockOpnameSessionSnapshot snapshot,
) {
  return printStockOpnameReportPdf(
    context,
    branchLabel: snapshot.branchLabel,
    branchIdForLogo: snapshot.branchId,
    selectedStatus: snapshot.selectedStatus,
    scopeItems: snapshot.scopeItems,
    verifiedIds: snapshot.verifiedIds,
    missingIds: snapshot.missingIds,
    sessionNotes: snapshot.sessionNotes,
    savedSummaryLine:
        'Tersimpan: ${snapshot.savedVerifiedCount} terverifikasi, '
        '${snapshot.savedMissingCount} koreksi hilang'
        '${snapshot.pendingAtSave > 0 ? ', ${snapshot.pendingAtSave} belum discan' : ''}',
  );
}

/// Cetak PDF laporan stok opname (hasil scan / tanda hilang per kode).
Future<void> printStockOpnameReportPdf(
  BuildContext context, {
  required String branchLabel,
  required String branchIdForLogo,
  required String selectedStatus,
  required List<Map<String, dynamic>> scopeItems,
  required Set<String> verifiedIds,
  required Set<String> missingIds,
  String sessionNotes = '',
  String? savedSummaryLine,
}) async {
  if (!context.mounted) return;

  if (scopeItems.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tidak ada data opname untuk dicetak')),
    );
    return;
  }

  try {
    final logoBytes = await loadBranchLogoRasterBytesForPdf(branchIdForLogo);
    final statusLabel = stockUiFilterScopeLabel(selectedStatus);
    final printedAt =
        DateFormat('dd/MM/yyyy HH:mm', 'id_ID').format(DateTime.now());
    final notes = sessionNotes.trim();

    final verifiedCount =
        scopeItems.where((m) => verifiedIds.contains(_itemIdStr(m))).length;
    final missingCount =
        scopeItems.where((m) => missingIds.contains(_itemIdStr(m))).length;
    final pendingCount =
        scopeItems.length - verifiedCount - missingCount;

    final sorted = List<Map<String, dynamic>>.from(scopeItems)
      ..sort((a, b) {
        final ka = _itemCode(a).toLowerCase();
        final kb = _itemCode(b).toLowerCase();
        return ka.compareTo(kb);
      });

    const maxRows = 300;
    final truncated = sorted.length > maxRows;
    final printItems = truncated ? sorted.sublist(0, maxRows) : sorted;

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: pdfMultiPageHeaderLaporanCabang(
          title: 'LAPORAN STOK OPNAME',
          leftLogoBytes: logoBytes,
          subtitles: [
            PdfLaporanHeaderSubtitleLine(
              'Dicetak: $printedAt',
              fontSize: 10,
              color: PdfColors.grey700,
            ),
            PdfLaporanHeaderSubtitleLine(
              'Cabang: $branchLabel',
              fontSize: 11,
              color: PdfColors.grey700,
            ),
            PdfLaporanHeaderSubtitleLine(
              'Scope status: $statusLabel',
              fontSize: 11,
              color: PdfColors.grey700,
            ),
            if (notes.isNotEmpty)
              PdfLaporanHeaderSubtitleLine(
                'Catatan: $notes',
                fontSize: 10,
                color: PdfColors.grey700,
              ),
          ],
        ),
        build: (ctx) {
          final blocks = <pw.Widget>[
            pw.Text(
              'Ringkasan',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text('Total barang (scope): ${scopeItems.length}'),
            pw.Text('Terverifikasi: $verifiedCount'),
            pw.Text('Ditandai hilang: $missingCount'),
            pw.Text('Belum scan: $pendingCount'),
            if (savedSummaryLine != null && savedSummaryLine.trim().isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text(
                savedSummaryLine.trim(),
                style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey800,
                ),
              ),
            ],
            pw.SizedBox(height: 14),
            pw.Text(
              'Detail per kode',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: const [
                'No',
                'Kode',
                'Nama',
                'Qty',
                'Status stok',
                'Hasil opname',
              ],
              data: [
                for (var i = 0; i < printItems.length; i++)
                  () {
                    final m = printItems[i];
                    final id = _itemIdStr(m);
                    final name = (m['name'] ?? '-').toString();
                    final shortName = name.length > 32
                        ? '${name.substring(0, 29)}...'
                        : name;
                    return [
                      '${i + 1}',
                      _itemCode(m),
                      shortName,
                      '${stockItemQuantity(m)}',
                      stockItemStatusLabel((m['status'] ?? '-').toString()),
                      _opnameResultLabel(
                        itemId: id,
                        verifiedIds: verifiedIds,
                        missingIds: missingIds,
                      ),
                    ];
                  }(),
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
              cellStyle: const pw.TextStyle(fontSize: 9),
              columnWidths: const {
                0: pw.FlexColumnWidth(0.35),
                1: pw.FlexColumnWidth(0.85),
                2: pw.FlexColumnWidth(1.4),
                3: pw.FlexColumnWidth(0.35),
                4: pw.FlexColumnWidth(0.65),
                5: pw.FlexColumnWidth(0.85),
              },
            ),
          ];

          if (truncated) {
            blocks.add(pw.SizedBox(height: 10));
            blocks.add(
              pw.Text(
                'Catatan: PDF memuat $maxRows baris pertama '
                'dari ${scopeItems.length} barang.',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            );
          }

          blocks.add(pw.SizedBox(height: 12));
          blocks.add(
            pw.Text(
              'Keterangan: scan/verifikasi = barang ada fisik (qty tidak berubah). '
              '"Hilang" = ditandai tidak ditemukan (koreksi qty saat simpan).',
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey700,
              ),
            ),
          );

          return blocks;
        },
      ),
    );

    final slug = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
    await Printing.layoutPdf(
      name: 'stok_opname_$slug.pdf',
      onLayout: (format) async => doc.save(),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak laporan opname: $e')),
      );
    }
  }
}

String _itemIdStr(Map<String, dynamic> m) => (m['item_id'] ?? '').toString();
