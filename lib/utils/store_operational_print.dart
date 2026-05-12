import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:vanessa3/shared_widgets/manager_report_period_selector.dart';
import 'package:vanessa3/utils/branch_logo_pdf.dart';
import 'package:vanessa3/utils/network_config.dart';

String _moneyPdf(num v) =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
        .format(v);

String _pdfFileName(DateTime start, DateTime end) {
  final a = managerReportIsoDate(start);
  final b = managerReportIsoDate(end);
  final slug = managerReportSameCalendarDay(start, end) ? a : '${a}_$b';
  return 'keuangan_toko_$slug.pdf';
}

bool _entryIsIncomePdf(Map<String, dynamic> e) =>
    e['entry_kind']?.toString() == 'income';

String? _absPhotoUrl(dynamic raw) {
  final s = raw?.toString().trim();
  if (s == null || s.isEmpty) return null;
  if (s.startsWith('http://') || s.startsWith('https://')) return s;
  if (s.startsWith('/')) return '${NetworkConfig.baseUrl}$s';
  return '${NetworkConfig.baseUrl}/uploads/$s';
}

/// Cetak catatan keuangan toko: pemasukan & pengeluaran (PDF).
Future<void> printStoreOperationalPdf(
  BuildContext context, {
  required String branchLabel,
  required String branchIdForLogo,
  required DateTime periodStart,
  required DateTime periodEnd,
  required List<Map<String, dynamic>> entries,
}) async {
  if (!context.mounted) return;
  final s = managerReportDateOnly(periodStart);
  final e = managerReportDateOnly(periodEnd);
  final periodTitle = managerReportPeriodTitle(s, e);

  final logoBytes = await loadBranchLogoRasterBytesForPdf(branchIdForLogo);

  final sorted = List<Map<String, dynamic>>.from(entries);
  sorted.sort((a, b) {
    final ta = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final tb = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return ta.compareTo(tb);
  });

  double totalIncome = 0;
  double totalExpense = 0;
  for (final row in sorted) {
    final amt = row['amount'];
    final n = amt is num
        ? amt.toDouble()
        : double.tryParse(amt?.toString() ?? '') ?? 0;
    if (_entryIsIncomePdf(row)) {
      totalIncome += n;
    } else {
      totalExpense += n;
    }
  }
  final net = totalIncome - totalExpense;

  final df = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');

  try {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: pdfMultiPageHeaderLaporanCabang(
          title: 'CATATAN KEUANGAN TOKO',
          leftLogoBytes: logoBytes,
          subtitles: [
            PdfLaporanHeaderSubtitleLine(
              'Pemasukan & pengeluaran operasional (bukan pembayaran order)',
              fontSize: 9,
              color: PdfColors.grey700,
            ),
            PdfLaporanHeaderSubtitleLine(branchLabel),
            PdfLaporanHeaderSubtitleLine(
              periodTitle,
              fontSize: 10,
              color: PdfColors.grey700,
            ),
          ],
        ),
        build: (ctx) => [
          if (sorted.isEmpty)
            pw.Text('Tidak ada catatan pada periode ini.')
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'No',
                'Waktu',
                'Jenis',
                'Kategori',
                'Keterangan',
                'Nominal',
              ],
              data: [
                for (var i = 0; i < sorted.length; i++)
                  _rowForPdf(sorted[i], i + 1, df),
              ],
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
            ),
          if (sorted.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Total pemasukan: ${_moneyPdf(totalIncome)}'),
                  pw.Text('Total pengeluaran: ${_moneyPdf(totalExpense)}'),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Saldo (masuk − keluar): ${_moneyPdf(net)}',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    await Printing.layoutPdf(
      name: _pdfFileName(s, e),
      onLayout: (format) async => doc.save(),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak: $e')),
      );
    }
  }
}

/// Cetak bukti per entri (PDF kecil). Jika ada `proof_photo_url`, coba sertakan fotonya.
Future<void> printStoreOperationalReceiptPdf(
  BuildContext context, {
  required String branchLabel,
  required String branchIdForLogo,
  required Map<String, dynamic> entry,
}) async {
  if (!context.mounted) return;
  try {
    final created = entry['created_at']?.toString();
    final dt = created != null ? DateTime.tryParse(created) : null;
    final whenStr = dt != null
        ? DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(dt.toLocal())
        : '—';

    final kindLabel = _entryIsIncomePdf(entry) ? 'PEMASUKAN' : 'PENGELUARAN';
    final cat = entry['category']?.toString() ?? '—';
    final notes = entry['notes']?.toString() ?? '';
    final amt = entry['amount'];
    final n = amt is num
        ? amt.toDouble()
        : double.tryParse(amt?.toString() ?? '') ?? 0;
    final entryId = entry['entry_id']?.toString() ?? '—';

    final photoUrl = _absPhotoUrl(entry['proof_photo_url']);
    pw.ImageProvider? proofImg;
    if (photoUrl != null) {
      try {
        proofImg = await networkImage(photoUrl);
      } catch (_) {
        proofImg = null;
      }
    }

    final branchLogoBytes = await loadBranchLogoRasterBytesForPdf(branchIdForLogo);

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a6,
        margin: const pw.EdgeInsets.all(18),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            ...pdfInlineLogoWidgets(branchLogoBytes),
            pw.Center(
              child: pw.Text(
                'BUKTI CATATAN KEUANGAN',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                branchLabel,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 8),
            pw.Text(kindLabel,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                )),
            pw.SizedBox(height: 6),
            pw.Text('ID: $entryId', style: const pw.TextStyle(fontSize: 8)),
            pw.Text('Waktu: $whenStr', style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 8),
            pw.Text('Kategori: $cat', style: const pw.TextStyle(fontSize: 9)),
            if (notes.trim().isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text('Ket: $notes', style: const pw.TextStyle(fontSize: 9)),
            ],
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey600),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Nominal',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      )),
                  pw.Text(
                    _moneyPdf(n),
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (proofImg != null) ...[
              pw.SizedBox(height: 10),
              pw.Text('Foto bukti:', style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 6),
              pw.ClipRRect(
                horizontalRadius: 6,
                verticalRadius: 6,
                child: pw.Image(
                  proofImg,
                  height: 220,
                  fit: pw.BoxFit.cover,
                ),
              ),
            ],
            pw.Spacer(),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                'Dicetak: ${DateFormat('dd/MM/yyyy HH:mm', 'id_ID').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
              ),
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(
      name: 'bukti_keuangan_$entryId.pdf',
      onLayout: (_) async => doc.save(),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak bukti: $e')),
      );
    }
  }
}

List<String> _rowForPdf(
  Map<String, dynamic> e,
  int no,
  DateFormat df,
) {
  final created = e['created_at']?.toString();
  final dt = created != null ? DateTime.tryParse(created) : null;
  final timeStr = dt != null ? df.format(dt.toLocal()) : '—';
  final cat = e['category']?.toString() ?? '—';
  final notes = e['notes']?.toString() ?? '';
  final amt = e['amount'];
  final n = amt is num
      ? amt.toDouble()
      : double.tryParse(amt?.toString() ?? '') ?? 0;
  final kindLabel = _entryIsIncomePdf(e) ? 'Pemasukan' : 'Pengeluaran';
  return [
    '$no',
    timeStr,
    kindLabel,
    cat,
    notes.isEmpty ? '—' : notes,
    _moneyPdf(n),
  ];
}
