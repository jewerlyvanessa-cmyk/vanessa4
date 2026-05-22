import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:vanessa3/utils/branch_logo_pdf.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/workshop_order_batch_group.dart';

/// Info cabang untuk header surat jalan workshop.
class WorkshopSuratJalanBranches {
  const WorkshopSuratJalanBranches({
    required this.fromBranchName,
    required this.toBranchName,
    required this.fromBranchIdForLogo,
    this.kurir = '',
    this.notes = '',
  });

  final String fromBranchName;
  final String toBranchName;
  final String fromBranchIdForLogo;
  final String kurir;
  final String notes;
}

/// Ambil nama cabang workshop pertama dari API (fallback label generik).
Future<WorkshopSuratJalanBranches> resolveWorkshopSuratJalanBranches({
  required String storeBranchId,
  required String storeBranchName,
  String kurir = '',
  String notes = '',
}) async {
  var toName = 'Workshop / Bengkel';
  try {
    final resp = await http.get(
      Uri.parse('${NetworkConfig.baseUrl}/branches'),
      headers: NetworkConfig.defaultHeaders,
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      if (data is List) {
        for (final e in data) {
          if (e is! Map) continue;
          final type = (e['branch_type'] ?? '').toString().trim().toLowerCase();
          if (type != 'workshop') continue;
          final n = (e['name'] ?? '').toString().trim();
          if (n.isNotEmpty) {
            toName = n;
            break;
          }
        }
      }
    }
  } catch (_) {}
  return WorkshopSuratJalanBranches(
    fromBranchName: storeBranchName.isEmpty ? 'Toko' : storeBranchName,
    toBranchName: toName,
    fromBranchIdForLogo: storeBranchId.trim(),
    kurir: kurir,
    notes: notes,
  );
}

String _orderNota(Map<String, dynamic> o) {
  final n = o['order_number']?.toString().trim();
  if (n != null && n.isNotEmpty) return n;
  return o['order_id']?.toString() ?? '-';
}

String _fmtDate(dynamic raw) {
  if (raw == null) return '-';
  try {
    return DateTime.parse(raw.toString())
        .toLocal()
        .toString()
        .split('.')
        .first;
  } catch (_) {
    return raw.toString();
  }
}

/// Cetak surat jalan pengiriman order service/custom ke workshop.
Future<void> printSuratJalanWorkshopOrders(
  BuildContext context, {
  required List<Map<String, dynamic>> orders,
  required WorkshopSuratJalanBranches branches,
}) async {
  if (orders.isEmpty) return;

  try {
    final logoBytes =
        await loadBranchLogoRasterBytesForPdf(branches.fromBranchIdForLogo);
    final doc = pw.Document();

    final orderIds = orders
        .map((o) => o['order_id']?.toString())
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList();

    final createdAt = orders
        .map((o) => o['created_at'] ?? o['updated_at'])
        .firstWhere((v) => v != null, orElse: () => null);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: pdfMultiPageHeaderLaporanCabang(
          title: 'SURAT JALAN KE WORKSHOP',
          leftLogoBytes: logoBytes,
          subtitles: const [
            PdfLaporanHeaderSubtitleLine(
              'Service & Custom',
              fontSize: 11,
              color: PdfColors.grey700,
            ),
          ],
        ),
        build: (ctx) => [
          pw.Text(
            'No. Order: ${orderIds.isEmpty ? '-' : orderIds.map((id) => '#$id').join(', ')}',
          ),
          pw.Text('Tanggal: ${_fmtDate(createdAt)}'),
          pw.SizedBox(height: 12),
          pw.Text('Dari (Toko): ${branches.fromBranchName}'),
          pw.Text('Ke (Workshop): ${branches.toBranchName}'),
          if (branches.kurir.trim().isNotEmpty)
            pw.Text('Kurir: ${branches.kurir.trim()}'),
          if (branches.notes.trim().isNotEmpty)
            pw.Text('Catatan: ${branches.notes.trim()}'),
          pw.SizedBox(height: 16),
          pw.Text(
            'Order / Barang',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const ['No. Nota', 'Jenis', 'Item', 'Pelanggan'],
            data: orders
                .map(
                  (o) => [
                    _orderNota(o),
                    (o['order_type'] ?? '—').toString(),
                    (o['item_name'] ?? o['nama_item'] ?? '—').toString(),
                    (o['customer_name'] ?? '—').toString(),
                  ],
                )
                .toList(),
            cellAlignment: pw.Alignment.centerLeft,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          ),
          pw.SizedBox(height: 28),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                children: [
                  pw.Text('Pengirim (Toko)'),
                  pw.SizedBox(height: 48),
                  pw.Text('(....................)'),
                ],
              ),
              pw.Column(
                children: [
                  pw.Text('Penerima (Workshop)'),
                  pw.SizedBox(height: 48),
                  pw.Text('(....................)'),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    final firstId = orderIds.isEmpty ? 'workshop' : orderIds.first;
    await Printing.layoutPdf(
      name: 'surat_jalan_workshop_$firstId.pdf',
      onLayout: (format) async => doc.save(),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak surat jalan workshop: $e')),
      );
    }
  }
}

/// Cetak dari batch dokumen UI (subset baris terpilih).
Future<void> printSuratJalanFromWorkshopBatch(
  BuildContext context, {
  required WorkshopOrderDocumentBatch batch,
  required WorkshopSuratJalanBranches branches,
  Set<int>? onlyOrderIds,
}) async {
  final lines = onlyOrderIds == null
      ? batch.lines
      : batch.lines
          .where((o) {
            final id = orderIdFromLine(o);
            return id != null && onlyOrderIds.contains(id);
          })
          .toList();
  await printSuratJalanWorkshopOrders(
    context,
    orders: lines,
    branches: branches,
  );
}
