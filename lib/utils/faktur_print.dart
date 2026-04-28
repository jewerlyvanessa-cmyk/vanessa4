import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Builds a simple invoice PDF and opens the system print / share UI.
Future<void> printFakturOrder(
  BuildContext context,
  Map<String, dynamic> orderData,
) async {
  try {
    final items = orderData['items'] as List<dynamic>? ?? [];
    final doc = pw.Document();

    String fmtMoney(dynamic v) {
      final n = double.tryParse(v?.toString() ?? '');
      if (n == null) return v?.toString() ?? '0';
      final s = n.toStringAsFixed(0);
      return s.replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      );
    }

    String dateStr(dynamic created) {
      if (created == null) return '-';
      try {
        return DateTime.parse(created.toString())
            .toLocal()
            .toString()
            .split('.')
            .first;
      } catch (_) {
        return created.toString();
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) => [
          pw.Center(
            child: pw.Text(
              'FAKTUR PENJUALAN',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              'VANESSA GOLD & DIAMOND',
              style: const pw.TextStyle(fontSize: 14),
            ),
          ),
          pw.Divider(thickness: 2),
          pw.SizedBox(height: 12),
          pw.Text(
            'Informasi Order',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Order ID: ${orderData['order_id'] ?? '-'}'),
          pw.Text('Order Number: ${orderData['order_number'] ?? '-'}'),
          pw.Text('Tipe Order: ${orderData['order_type'] ?? '-'}'),
          pw.Text('Status: ${orderData['status'] ?? '-'}'),
          pw.Text('Tanggal: ${dateStr(orderData['created_at'])}'),
          pw.Text('Customer: ${orderData['customer_name'] ?? '-'}'),
          pw.Text('No. HP: ${orderData['customer_phone'] ?? '-'}'),
          pw.Text('Alamat: ${orderData['customer_address'] ?? '-'}'),
          pw.SizedBox(height: 16),
          pw.Text(
            'Detail Item',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          if (items.isEmpty)
            pw.Text('Tidak ada item dalam order ini')
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'Kode',
                'Item',
                'Berat',
                'Harga/g',
                'Total',
              ],
              data: items.map((raw) {
                final item = raw as Map<String, dynamic>;
                return [
                  (item['kode_produk'] ?? '-').toString(),
                  (item['nama_item'] ?? item['name'] ?? '-').toString(),
                  (item['weight'] ?? '-').toString(),
                  fmtMoney(item['harga_per_gram'] ?? 0),
                  // Use total from order_items (source-of-truth from backend).
                  fmtMoney(item['total'] ?? 0),
                ];
              }).toList(),
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
            ),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Total Order:',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Rp ${fmtMoney(orderData['jumlah'] ?? ((() {
                  final t =
                      double.tryParse(orderData['total']?.toString() ?? '') ?? 0;
                  final rounded = (t / 5000).ceil() * 5000;
                  return rounded;
                })()))}',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Center(
            child: pw.Text(
              'Terima kasih atas kunjungan Anda!',
              style: const pw.TextStyle(fontSize: 12),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              'Dicetak: ${DateTime.now().toLocal().toString().split('.').first}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      name:
          'faktur_${orderData['order_number'] ?? orderData['order_id'] ?? 'order'}.pdf',
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
