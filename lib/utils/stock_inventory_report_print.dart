import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:vanessa3/modules/stockist/widgets/stock_inventory_grouped_table.dart';
import 'package:vanessa3/shared_widgets/stock_status_filter_summary_header.dart';
import 'package:vanessa3/utils/branch_logo_pdf.dart';

String _itemCode(Map<String, dynamic> i) =>
    (i['item_code'] ?? i['kode_produk'] ?? '-').toString();

double _weightGram(Map<String, dynamic> i) {
  final rawWeight = i['weight'];
  final w = rawWeight is num
      ? rawWeight.toDouble()
      : double.tryParse(rawWeight?.toString() ?? '') ?? 0.0;
  final qty = stockItemQuantity(i);
  return w * (qty <= 0 ? 1 : qty);
}

List<String> _rowCells(
  Map<String, dynamic> i, {
  required bool includeBranchColumn,
}) {
  final name = (i['name'] ?? '-').toString();
  final shortName =
      name.length > 36 ? '${name.substring(0, 33)}...' : name;
  final cells = <String>[
    _itemCode(i),
    shortName,
    '${stockItemQuantity(i)}',
    _weightGram(i) > 0 ? _weightGram(i).toStringAsFixed(2) : '-',
    (i['purity'] ?? '-').toString(),
    stockItemStatusLabel((i['status'] ?? '-').toString()),
  ];
  if (includeBranchColumn) {
    cells.insert(
      2,
      (i['branch_name'] ?? i['branch_id'] ?? '-').toString(),
    );
  }
  return cells;
}

/// Cetak PDF laporan stok inventaris (filter & pencarian sama seperti layar).
Future<void> printStockInventoryReportPdf(
  BuildContext context, {
  required String branchLabel,
  required String branchIdForLogo,
  required String selectedStatus,
  required List<dynamic> filteredItems,
  String searchQuery = '',
  bool includeBranchColumn = false,
}) async {
  if (!context.mounted) return;

  final items = <Map<String, dynamic>>[];
  for (final raw in filteredItems) {
    if (raw is! Map) continue;
    items.add(Map<String, dynamic>.from(raw));
  }

  if (items.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tidak ada data stok untuk dicetak')),
    );
    return;
  }

  try {
    final logoBytes = await loadBranchLogoRasterBytesForPdf(branchIdForLogo);
    final statusLabel = stockUiFilterScopeLabel(selectedStatus);
    final skuCount = items.length;
    final totalQty = stockListSumQuantity(items);
    final totalWeight = stockListFormatWeightGram(stockListSumWeightGram(items));
    final grouped = groupStockItemsByJenis(items);
    final printedAt =
        DateFormat('dd/MM/yyyy HH:mm', 'id_ID').format(DateTime.now());
    final q = searchQuery.trim();

    final headers = includeBranchColumn
        ? const ['Kode', 'Nama', 'Cabang', 'Qty', 'Berat (g)', 'Kadar', 'Status']
        : const ['Kode', 'Nama', 'Qty', 'Berat (g)', 'Kadar', 'Status'];

    const maxDetailRows = 200;
    var detailRowsUsed = 0;
    var truncated = false;

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: pdfMultiPageHeaderLaporanCabang(
          title: 'LAPORAN STOK',
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
              'Filter status: $statusLabel',
              fontSize: 11,
              color: PdfColors.grey700,
            ),
            if (q.isNotEmpty)
              PdfLaporanHeaderSubtitleLine(
                'Pencarian: $q',
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
            pw.Text('Jumlah SKU: $skuCount'),
            pw.Text('Total qty: $totalQty'),
            pw.Text('Total berat: $totalWeight'),
            pw.SizedBox(height: 14),
          ];

          for (final entry in grouped) {
            if (detailRowsUsed >= maxDetailRows) {
              truncated = true;
              break;
            }
            final jenis = entry.key;
            final jenisItems = entry.value;
            final jenisQty = stockListSumQuantity(jenisItems);
            final jenisWeight =
                stockListFormatWeightGram(stockListSumWeightGram(jenisItems));

            blocks.add(
              pw.Text(
                jenis,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            );
            blocks.add(pw.SizedBox(height: 4));
            blocks.add(
              pw.Text(
                '${jenisItems.length} SKU · qty $jenisQty · $jenisWeight',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            );
            blocks.add(pw.SizedBox(height: 6));

            final rows = <List<String>>[];
            for (final item in jenisItems) {
              if (detailRowsUsed >= maxDetailRows) {
                truncated = true;
                break;
              }
              rows.add(
                _rowCells(
                  item,
                  includeBranchColumn: includeBranchColumn,
                ),
              );
              detailRowsUsed++;
            }

            if (rows.isNotEmpty) {
              blocks.add(
                pw.TableHelper.fromTextArray(
                  headers: headers,
                  data: rows,
                  cellAlignment: pw.Alignment.centerLeft,
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  headerDecoration:
                      const pw.BoxDecoration(color: PdfColors.grey300),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  columnWidths: includeBranchColumn
                      ? const {
                          0: pw.FlexColumnWidth(0.85),
                          1: pw.FlexColumnWidth(1.5),
                          2: pw.FlexColumnWidth(0.75),
                          3: pw.FlexColumnWidth(0.4),
                          4: pw.FlexColumnWidth(0.55),
                          5: pw.FlexColumnWidth(0.45),
                          6: pw.FlexColumnWidth(0.65),
                        }
                      : const {
                          0: pw.FlexColumnWidth(0.9),
                          1: pw.FlexColumnWidth(1.7),
                          2: pw.FlexColumnWidth(0.45),
                          3: pw.FlexColumnWidth(0.55),
                          4: pw.FlexColumnWidth(0.5),
                          5: pw.FlexColumnWidth(0.7),
                        },
                ),
              );
            }
            blocks.add(pw.SizedBox(height: 12));
            if (truncated) break;
          }

          if (truncated) {
            blocks.add(
              pw.Text(
                'Catatan: PDF memuat $maxDetailRows baris detail pertama '
                'dari $skuCount SKU.',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            );
          }

          return blocks;
        },
      ),
    );

    final slug = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
    await Printing.layoutPdf(
      name: 'laporan_stok_$slug.pdf',
      onLayout: (format) async => doc.save(),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak laporan stok: $e')),
      );
    }
  }
}
