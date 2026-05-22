import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:vanessa3/shared_widgets/manager_report_period_selector.dart';
import 'package:vanessa3/utils/branch_logo_pdf.dart';
import 'package:vanessa3/utils/parallel_branch_logos.dart';
import 'package:vanessa3/utils/print_progress.dart';

String _moneyPdf(num v) =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
        .format(v);

String _intPdf(dynamic v) {
  if (v is int) return '$v';
  if (v is num) return '${v.toInt()}';
  return int.tryParse(v?.toString() ?? '')?.toString() ?? '0';
}

int _mapInt(Map<String, dynamic> r, String k) {
  final v = r[k];
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

String _pdfFileName(String prefix, DateTime start, DateTime end) {
  final a = managerReportIsoDate(start);
  final b = managerReportIsoDate(end);
  final slug = managerReportSameCalendarDay(start, end) ? a : '${a}_$b';
  return '${prefix}_$slug.pdf';
}

Future<void> printManagerBranchPerformancePdf(
  BuildContext context, {
  required DateTime periodStart,
  required DateTime periodEnd,
  required String periodTitle,
  required String periodSubtitle,
  required List<Map<String, dynamic>> rows,
  required String branchIdForLogo,
}) async {
  if (!context.mounted) return;
  try {
    await runWithPrintProgress(
      context,
      () async {
    final logoBytes = await loadBranchLogoRasterBytesForPdf(branchIdForLogo);
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: pdfMultiPageHeaderLaporanCabang(
          title: 'PERFORMA CABANG',
          leftLogoBytes: logoBytes,
          subtitles: [
            PdfLaporanHeaderSubtitleLine(periodTitle),
            PdfLaporanHeaderSubtitleLine(
              periodSubtitle,
              fontSize: 10,
              color: PdfColors.grey700,
            ),
          ],
        ),
        build: (ctx) => [
          if (rows.isEmpty)
            pw.Text('Tidak ada data cabang.')
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'Cabang',
                'Mode toko',
                'Mode online',
                'Jual',
                'Buyback',
                'Service',
                'Custom',
                'Catatan',
              ],
              data: rows.map((r) {
                final err = r['error']?.toString();
                final hasErr = err != null && err.isNotEmpty;
                final note = hasErr ? err : '—';
                return [
                  (r['branch_alias'] ?? r['branch_name'] ?? '-').toString(),
                  hasErr ? '—' : _intPdf(r['mode_toko']),
                  hasErr ? '—' : _intPdf(r['mode_online']),
                  hasErr ? '—' : _intPdf(r['jual']),
                  hasErr ? '—' : _intPdf(r['buyback']),
                  hasErr ? '—' : _intPdf(r['service']),
                  hasErr ? '—' : _intPdf(r['custom']),
                  note,
                ];
              }).toList(),
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
            ),
        ],
      ),
    );

    await Printing.layoutPdf(
      name: _pdfFileName('performa_cabang', periodStart, periodEnd),
      onLayout: (format) async => doc.save(),
    );
      },
      message: 'Menyiapkan laporan performa cabang…',
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak: $e')),
      );
    }
  }
}

Future<void> printManagerPaymentSummaryPdf(
  BuildContext context, {
  required DateTime periodStart,
  required DateTime periodEnd,
  required String reportTitle,
  required String periodTitle,
  required String periodSubtitle,
  required List<Map<String, dynamic>> rows,
  required String fileSlugPrefix,
  required String branchIdForLogo,
  bool includeMethodNominals = false,
}) async {
  if (!context.mounted) return;
  try {
    await runWithPrintProgress(
      context,
      () async {
    final logoBytes = await loadBranchLogoRasterBytesForPdf(branchIdForLogo);
    final totalAll = rows.fold<num>(0, (p, r) {
      final v = num.tryParse(r['total_amount']?.toString() ?? '') ?? 0;
      return p + v;
    });
    num sumField(String key) => rows.fold<num>(0, (p, r) {
          final err = r['error']?.toString();
          if (err != null && err.isNotEmpty) return p;
          return p + (num.tryParse(r[key]?.toString() ?? '') ?? 0);
        });

    final paymentSummarySubtitles = <PdfLaporanHeaderSubtitleLine>[
      PdfLaporanHeaderSubtitleLine(periodTitle),
      PdfLaporanHeaderSubtitleLine(
        '$periodSubtitle • Total gabungan: ${_moneyPdf(totalAll)}',
        fontSize: 10,
        color: PdfColors.grey700,
      ),
    ];
    if (includeMethodNominals && rows.isNotEmpty) {
      paymentSummarySubtitles.add(
        PdfLaporanHeaderSubtitleLine(
          'Gabungan per metode · Cash ${_moneyPdf(sumField('cash_amount'))} · '
          'TRF ${_moneyPdf(sumField('transfer_amount'))} · '
          'QRIS ${_moneyPdf(sumField('qris_amount'))}',
          fontSize: 9,
          color: PdfColors.grey700,
        ),
      );
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: pdfMultiPageHeaderLaporanCabang(
          title: reportTitle.toUpperCase(),
          leftLogoBytes: logoBytes,
          subtitles: paymentSummarySubtitles,
        ),
        build: (ctx) => [
          if (rows.isEmpty)
            pw.Text('Tidak ada data.')
          else
            pw.TableHelper.fromTextArray(
              headers: includeMethodNominals
                  ? const [
                      'Cabang',
                      'Trx',
                      'Cash (# / Rp)',
                      'TRF (# / Rp)',
                      'QRIS (# / Rp)',
                      'Total',
                      'Catatan',
                    ]
                  : const [
                      'Cabang',
                      'Trx',
                      'Cash',
                      'TRF',
                      'QRIS',
                      'Total',
                      'Catatan',
                    ],
              data: rows.map((r) {
                final err = r['error']?.toString();
                final hasErr = err != null && err.isNotEmpty;
                final note = hasErr ? err : '—';
                final amt =
                    num.tryParse(r['total_amount']?.toString() ?? '') ?? 0;
                String methodCell(String countKey, String amountKey) {
                  if (hasErr) return '—';
                  if (!includeMethodNominals) return _intPdf(r[countKey]);
                  final n = _intPdf(r[countKey]);
                  final a = num.tryParse(r[amountKey]?.toString() ?? '') ?? 0;
                  return '$n trx\n${_moneyPdf(a)}';
                }

                return [
                  (r['branch_name'] ?? '-').toString(),
                  hasErr ? '—' : _intPdf(r['total_payments']),
                  methodCell('cash_payments', 'cash_amount'),
                  methodCell('transfer_payments', 'transfer_amount'),
                  methodCell('qris_payments', 'qris_amount'),
                  hasErr ? '—' : _moneyPdf(amt),
                  note,
                ];
              }).toList(),
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
            ),
        ],
      ),
    );

    await Printing.layoutPdf(
      name: _pdfFileName(fileSlugPrefix, periodStart, periodEnd),
      onLayout: (format) async => doc.save(),
    );
      },
      message: 'Menyiapkan laporan pembayaran…',
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak: $e')),
      );
    }
  }
}

/// Satu cabang untuk PDF laporan stok (mode per cabang).
class StockReportBranchPdfSection {
  StockReportBranchPdfSection({
    required this.name,
    this.branchId,
    this.error,
    required this.rowsStok,
    required this.rowsBuyback,
  });

  final String name;
  /// Cabang untuk logo di badan laporan (mode per cabang).
  final String? branchId;
  final String? error;
  final List<Map<String, dynamic>> rowsStok;
  final List<Map<String, dynamic>> rowsBuyback;
}

Future<void> printManagerStockReportPdf(
  BuildContext context, {
  required DateTime periodStart,
  required DateTime periodEnd,
  required String periodTitle,
  required String periodSubtitle,
  required bool gabunganMode,
  required List<Map<String, dynamic>> rowsStokByJenis,
  required List<Map<String, dynamic>> rowsBuybackByJenis,
  required List<StockReportBranchPdfSection>? branchSections,
  required String branchIdForLogo,
}) async {
  if (!context.mounted) return;
  try {
    await runWithPrintProgress(
      context,
      () async {
    final headerLogoBytes = await loadBranchLogoRasterBytesForPdf(branchIdForLogo);
    final Map<String, Uint8List> sectionLogos = {};
    if (!gabunganMode && branchSections != null) {
      final ids = branchSections
          .map((s) => s.branchId?.trim() ?? '')
          .where((id) => id.isNotEmpty);
      sectionLogos.addAll(await loadBranchLogosParallel(ids));
    }

    final doc = pw.Document();

    List<pw.Widget> jenisTable(
      String title,
      List<Map<String, dynamic>> rows,
    ) {
      return [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        if (rows.isEmpty)
          pw.Text(
            '— Tidak ada baris —',
            style: const pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey700,
            ),
          )
        else
          pw.TableHelper.fromTextArray(
            headers: const ['Jenis', 'SKU', 'Qty'],
            data: rows
                .map((r) => [
                      (r['jenis'] ?? '-').toString(),
                      _intPdf(r['sku']),
                      _intPdf(r['qty']),
                    ])
                .toList(),
            cellAlignment: pw.Alignment.centerLeft,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey300),
          ),
        pw.SizedBox(height: 14),
      ];
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: pdfMultiPageHeaderLaporanCabang(
          title: 'LAPORAN STOK',
          leftLogoBytes: headerLogoBytes,
          subtitles: [
            PdfLaporanHeaderSubtitleLine(periodTitle),
            PdfLaporanHeaderSubtitleLine(
              '$periodSubtitle • ${gabunganMode ? 'Gabungan' : 'Per cabang'}',
              fontSize: 10,
              color: PdfColors.grey700,
            ),
            PdfLaporanHeaderSubtitleLine(
              'Catatan: angka stok adalah snapshot inventori saat ini; periode hanya label laporan.',
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ],
        ),
        build: (ctx) {
          final out = <pw.Widget>[];

          if (gabunganMode) {
            out.addAll(
                jenisTable('Rekap stok per jenis (non-buyback)', rowsStokByJenis));
            out.addAll(jenisTable('Buyback per jenis', rowsBuybackByJenis));
          } else {
            final sections = branchSections ?? [];
            if (sections.isEmpty) {
              out.add(pw.Text('Tidak ada data cabang.'));
            } else {
              final summaryData = sections.map((b) {
                final skuS = b.rowsStok.fold<int>(
                    0, (a, r) => a + _mapInt(r, 'sku'));
                final qtyS = b.rowsStok.fold<int>(
                    0, (a, r) => a + _mapInt(r, 'qty'));
                final skuB = b.rowsBuyback.fold<int>(
                    0, (a, r) => a + _mapInt(r, 'sku'));
                final qtyB = b.rowsBuyback.fold<int>(
                    0, (a, r) => a + _mapInt(r, 'qty'));
                final err = b.error;
                return [
                  b.name,
                  err != null ? '—' : '$skuS',
                  err != null ? '—' : '$qtyS',
                  err != null ? '—' : '$skuB',
                  err != null ? '—' : '$qtyB',
                  err ?? '—',
                ];
              }).toList();

              out.add(
                pw.Text(
                  'Ringkasan per cabang',
                  style:
                      pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
              );
              out.add(pw.SizedBox(height: 6));
              out.add(
                pw.TableHelper.fromTextArray(
                  headers: const [
                    'Cabang',
                    'SKU stok',
                    'Qty stok',
                    'SKU BB',
                    'Qty BB',
                    'Catatan',
                  ],
                  data: summaryData,
                  cellAlignment: pw.Alignment.centerLeft,
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  headerDecoration:
                      const pw.BoxDecoration(color: PdfColors.grey300),
                ),
              );
              out.add(pw.SizedBox(height: 16));

              for (final b in sections) {
                final bid = b.branchId?.trim() ?? '';
                final secLogo =
                    bid.isNotEmpty ? sectionLogos[bid] : null;
                out.addAll(pdfInlineLogoWidgets(secLogo));
                out.add(
                  pw.Text(
                    b.name,
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                );
                if (b.error != null) {
                  out.add(
                    pw.Text(
                      'Error: ${b.error}',
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.red,
                      ),
                    ),
                  );
                }
                out.add(pw.SizedBox(height: 6));
                out.addAll(jenisTable('Stok per jenis', b.rowsStok));
                out.addAll(jenisTable('Buyback per jenis', b.rowsBuyback));
              }
            }
          }

          return out;
        },
      ),
    );

    await Printing.layoutPdf(
      name: _pdfFileName('laporan_stok', periodStart, periodEnd),
      onLayout: (format) async => doc.save(),
    );
      },
      message: 'Menyiapkan laporan stok…',
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak: $e')),
      );
    }
  }
}
