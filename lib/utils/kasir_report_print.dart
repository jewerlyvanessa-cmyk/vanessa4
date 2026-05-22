import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:vanessa3/utils/branch_logo_pdf.dart';
import 'package:vanessa3/utils/print_progress.dart';

String _paymentMethodLabel(String method) {
  switch (method.trim().toLowerCase()) {
    case 'cash':
      return 'Tunai';
    case 'transfer':
      return 'Transfer Bank';
    case 'qris':
      return 'QRIS';
    case 'ewallet':
    case 'e-wallet':
      return 'E-Wallet';
    default:
      return method.isEmpty ? '-' : method;
  }
}

String _formatTime(dynamic createdAt) {
  if (createdAt == null) return '-';
  try {
    final dt = DateTime.parse(createdAt.toString()).toLocal();
    return DateFormat('HH:mm', 'id_ID').format(dt);
  } catch (_) {
    return createdAt.toString();
  }
}

String _paymentRowOrderLabel(Map<String, dynamic> p) {
  final n = (p['order_number'] ?? '').toString().trim();
  if (n.isNotEmpty) return n;
  final id = (p['order_id'] ?? '').toString().trim();
  if (id.isNotEmpty) return '#$id';
  return '-';
}

/// Cetak / PDF laporan harian kasir (ringkasan order + pembayaran yang difilter sama seperti layar).
Future<void> printKasirDailyReport(
  BuildContext context, {
  required String reportDateLabel,
  required String reportDateSlug,
  required String branchLabel,
  required String branchIdForLogo,
  required String cashierLabel,
  required int orderCount,
  required double totalOrderAmount,
  required int paymentTransactionCount,
  required double totalPaymentAmount,
  required List<Map<String, dynamic>> paymentRows,
}) async {
  if (!context.mounted) return;
  final money = NumberFormat('#,###', 'id_ID');

  try {
    await runWithPrintProgress(
      context,
      () async {
    final logoBytes = await loadBranchLogoRasterBytesForPdf(branchIdForLogo);
    final doc = pw.Document();

    final tableRows =
        paymentRows.length > 80 ? paymentRows.sublist(0, 80) : paymentRows;

    final amountByMethod = <String, double>{};
    for (final p in paymentRows) {
      final method =
          (p['payment_method'] ?? p['method'] ?? '').toString().trim();
      if (method.isEmpty) continue;
      final amount = double.tryParse(p['amount']?.toString() ?? '') ?? 0;
      amountByMethod[method] = (amountByMethod[method] ?? 0) + amount;
    }
    final methodLines = amountByMethod.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: pdfMultiPageHeaderLaporanCabang(
          title: 'LAPORAN KASIR',
          leftLogoBytes: logoBytes,
          subtitles: [
            PdfLaporanHeaderSubtitleLine(reportDateLabel),
          ],
        ),
        build: (ctx) => [
          pw.Text('Cabang: $branchLabel'),
          pw.Text('Kasir: $cashierLabel'),
          pw.SizedBox(height: 16),
          pw.Text(
            'Ringkasan order',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Jumlah order: $orderCount'),
          pw.Text('Total nilai order: Rp ${money.format(totalOrderAmount)}'),
          pw.SizedBox(height: 14),
          pw.Text(
            'Ringkasan pembayaran (sesuai filter layar)',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Jumlah transaksi: $paymentTransactionCount'),
          pw.Text('Total nominal: Rp ${money.format(totalPaymentAmount)}'),
          if (methodLines.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              'Per metode pembayaran',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            ...methodLines.map(
              (e) => pw.Text(
                '  ${_paymentMethodLabel(e.key)}: Rp ${money.format(e.value)}',
              ),
            ),
          ],
          pw.SizedBox(height: 16),
          pw.Text(
            'Detail pembayaran',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (tableRows.isEmpty)
            pw.Text('Tidak ada pembayaran pada tanggal ini.')
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'Nomor order',
                'Metode',
                'Nominal',
                'Status',
                'Jam',
              ],
              data: tableRows.map((p) {
                final pm = Map<String, dynamic>.from(p);
                final amount =
                    double.tryParse(p['amount']?.toString() ?? '') ?? 0;
                return [
                  _paymentRowOrderLabel(pm),
                  _paymentMethodLabel(
                    (p['payment_method'] ?? p['method'] ?? '').toString(),
                  ),
                  'Rp ${money.format(amount)}',
                  (p['status'] ?? '-').toString(),
                  _formatTime(p['created_at']),
                ];
              }).toList(),
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            ),
          if (paymentRows.length > 80)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                'Catatan: PDF memuat 80 baris pertama dari ${paymentRows.length} transaksi.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ),
        ],
      ),
    );

    await Printing.layoutPdf(
      name: 'laporan_kasir_$reportDateSlug.pdf',
      onLayout: (format) async => doc.save(),
    );
      },
      message: 'Menyiapkan laporan kasir…',
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak laporan: $e')),
      );
    }
  }
}

/// Cetak / PDF khusus halaman "Pembayaran Hari Ini" kasir.
Future<void> printKasirDailyPaymentsReport(
  BuildContext context, {
  required String reportDateLabel,
  required String reportDateSlug,
  required String branchLabel,
  required String branchIdForLogo,
  required String cashierLabel,
  required int paymentTransactionCount,
  required double incomeAmount,
  required double expenseAmount,
  required double netAmount,
  required Map<String, dynamic> paymentMethods,
  required List<Map<String, dynamic>> paymentRows,
}) async {
  if (!context.mounted) return;
  final money = NumberFormat('#,###', 'id_ID');

  try {
    await runWithPrintProgress(
      context,
      () async {
    final logoBytes = await loadBranchLogoRasterBytesForPdf(branchIdForLogo);
    final doc = pw.Document();
    final tableRows =
        paymentRows.length > 120 ? paymentRows.sublist(0, 120) : paymentRows;

    final methodLines = paymentMethods.entries.toList()
      ..sort((a, b) {
        num toNet(dynamic raw) {
          if (raw is Map) {
            final m = Map<String, dynamic>.from(raw);
            return (num.tryParse(m['net']?.toString() ?? '') ?? 0).abs();
          }
          return (num.tryParse(raw?.toString() ?? '') ?? 0).abs();
        }

        return toNet(b.value).compareTo(toNet(a.value));
      });

    String methodLineText(MapEntry<String, dynamic> e) {
      final v = e.value;
      if (v is Map) {
        final m = Map<String, dynamic>.from(v);
        final income = num.tryParse(m['income']?.toString() ?? '') ?? 0;
        final expense = num.tryParse(m['expense']?.toString() ?? '') ?? 0;
        final net = num.tryParse(m['net']?.toString() ?? '') ?? 0;
        return '  ${_paymentMethodLabel(e.key)}: '
            'masuk Rp ${money.format(income)}, '
            'keluar Rp ${money.format(expense)}, '
            'net Rp ${money.format(net)}';
      }
      final amount = num.tryParse(v?.toString() ?? '') ?? 0;
      return '  ${_paymentMethodLabel(e.key)}: Rp ${money.format(amount)}';
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: pdfMultiPageHeaderLaporanCabang(
          title: 'LAPORAN PEMBAYARAN HARIAN KASIR',
          leftLogoBytes: logoBytes,
          subtitles: [
            PdfLaporanHeaderSubtitleLine(reportDateLabel),
          ],
        ),
        build: (ctx) => [
          pw.Text('Cabang: $branchLabel'),
          pw.Text('Kasir: $cashierLabel'),
          pw.SizedBox(height: 16),
          pw.Text(
            'Ringkasan',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Jumlah transaksi: $paymentTransactionCount'),
          pw.Text('Total masuk: Rp ${money.format(incomeAmount)}'),
          pw.Text('Total keluar: Rp ${money.format(expenseAmount)}'),
          pw.Text('Saldo bersih: Rp ${money.format(netAmount)}'),
          if (methodLines.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              'Ringkasan per metode pembayaran',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            ...methodLines.map((e) => pw.Text(methodLineText(e))),
          ],
          pw.SizedBox(height: 16),
          pw.Text(
            'Detail transaksi',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (tableRows.isEmpty)
            pw.Text('Tidak ada pembayaran pada tanggal ini.')
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'Nomor order',
                'Jenis',
                'Customer',
                'Metode',
                'Nominal',
              ],
              data: tableRows.map((p) {
                final pm = Map<String, dynamic>.from(p);
                final amount =
                    double.tryParse(p['amount']?.toString() ?? '') ?? 0;
                return [
                  _paymentRowOrderLabel(pm),
                  (p['order_type'] ?? '-').toString(),
                  (p['customer_name'] ?? '-').toString(),
                  _paymentMethodLabel(
                    (p['payment_method'] ?? p['method'] ?? '').toString(),
                  ),
                  'Rp ${money.format(amount)}',
                ];
              }).toList(),
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            ),
          if (paymentRows.length > 120)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                'Catatan: PDF memuat 120 baris pertama dari ${paymentRows.length} transaksi.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ),
        ],
      ),
    );

    await Printing.layoutPdf(
      name: 'laporan_pembayaran_kasir_$reportDateSlug.pdf',
      onLayout: (format) async => doc.save(),
    );
      },
      message: 'Menyiapkan laporan pembayaran…',
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak laporan: $e')),
      );
    }
  }
}

bool _opsEntryIsIncome(Map<String, dynamic> e) =>
    e['entry_kind']?.toString() == 'income';

/// PDF gabungan: pembayaran order + catatan keuangan toko (non-order).
Future<void> printKasirCombinedFinanceReport(
  BuildContext context, {
  required String periodTitle,
  required String periodSlug,
  required String branchLabel,
  required String branchIdForLogo,
  required String cashierLabel,
  required int paymentTransactionCount,
  required double paymentIncome,
  required double paymentExpense,
  required double paymentNet,
  required int operationalEntryCount,
  required double operationalIncome,
  required double operationalExpense,
  required double operationalNet,
  required List<Map<String, dynamic>> paymentRows,
  required List<Map<String, dynamic>> operationalRows,
}) async {
  if (!context.mounted) return;
  final money = NumberFormat('#,###', 'id_ID');
  final grandIncome = paymentIncome + operationalIncome;
  final grandExpense = paymentExpense + operationalExpense;
  final grandNet = paymentNet + operationalNet;

  try {
    await runWithPrintProgress(
      context,
      () async {
    final logoBytes = await loadBranchLogoRasterBytesForPdf(branchIdForLogo);
    final doc = pw.Document();
    final paySlice =
        paymentRows.length > 80 ? paymentRows.sublist(0, 80) : paymentRows;
    final opsSlice = operationalRows.length > 80
        ? operationalRows.sublist(0, 80)
        : operationalRows;
    final df = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: pdfMultiPageHeaderLaporanCabang(
          title: 'LAPORAN KEUANGAN KASIR',
          leftLogoBytes: logoBytes,
          subtitles: [
            PdfLaporanHeaderSubtitleLine(periodTitle),
            PdfLaporanHeaderSubtitleLine(
              'Pembayaran order + keuangan toko (non-order)',
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ],
        ),
        build: (ctx) => [
          pw.Text('Cabang: $branchLabel'),
          pw.Text('Kasir: $cashierLabel'),
          pw.SizedBox(height: 14),
          pw.Text(
            'Ringkasan gabungan',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Total masuk: Rp ${money.format(grandIncome)}'),
          pw.Text('Total keluar: Rp ${money.format(grandExpense)}'),
          pw.Text(
            'Saldo bersih: Rp ${money.format(grandNet)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            'Pembayaran order ($paymentTransactionCount transaksi)',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Masuk: Rp ${money.format(paymentIncome)}'),
          pw.Text('Keluar: Rp ${money.format(paymentExpense)}'),
          pw.Text('Net: Rp ${money.format(paymentNet)}'),
          pw.SizedBox(height: 14),
          pw.Text(
            'Keuangan toko — non-order ($operationalEntryCount catatan)',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Pemasukan: Rp ${money.format(operationalIncome)}'),
          pw.Text('Pengeluaran: Rp ${money.format(operationalExpense)}'),
          pw.Text('Net: Rp ${money.format(operationalNet)}'),
          pw.SizedBox(height: 16),
          pw.Text(
            'Detail pembayaran order',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          if (paySlice.isEmpty)
            pw.Text('Tidak ada data.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Nota', 'Jenis', 'Metode', 'Nominal'],
              data: paySlice.map((p) {
                final amount =
                    double.tryParse(p['amount']?.toString() ?? '') ?? 0;
                return [
                  _paymentRowOrderLabel(p),
                  (p['order_type'] ?? '-').toString(),
                  _paymentMethodLabel(
                    (p['payment_method'] ?? p['method'] ?? '').toString(),
                  ),
                  'Rp ${money.format(amount)}',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
            ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Detail keuangan toko (non-order)',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          if (opsSlice.isEmpty)
            pw.Text('Tidak ada data.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Waktu', 'Jenis', 'Kategori', 'Nominal'],
              data: opsSlice.map((e) {
                final created =
                    DateTime.tryParse(e['created_at']?.toString() ?? '');
                final amt =
                    double.tryParse(e['amount']?.toString() ?? '') ?? 0;
                return [
                  created != null ? df.format(created.toLocal()) : '-',
                  _opsEntryIsIncome(e) ? 'Masuk' : 'Keluar',
                  (e['category'] ?? '-').toString(),
                  'Rp ${money.format(amt)}',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
            ),
          if (paymentRows.length > 80 || operationalRows.length > 80)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                'Catatan: PDF memuat hingga 80 baris per bagian.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ),
        ],
      ),
    );

    await Printing.layoutPdf(
      name: 'laporan_keuangan_kasir_$periodSlug.pdf',
      onLayout: (format) async => doc.save(),
    );
      },
      message: 'Menyiapkan laporan keuangan…',
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak laporan: $e')),
      );
    }
  }
}
