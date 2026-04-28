import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class QrCodeMakerPage extends StatefulWidget {
  const QrCodeMakerPage({super.key});

  @override
  State<QrCodeMakerPage> createState() => _QrCodeMakerPageState();
}

class _QrCodeMakerPageState extends State<QrCodeMakerPage> {
  final _codeController = TextEditingController();
  final _titleController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<Uint8List> _buildPdf(String code, String title) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Center(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(24),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 1),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    title.isEmpty ? 'Label' : title,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 16),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: code,
                    width: 220,
                    height: 220,
                  ),
                  pw.SizedBox(height: 16),
                  pw.Text(code, style: const pw.TextStyle(fontSize: 14)),
                ],
              ),
            ),
          );
        },
      ),
    );

    return doc.save();
  }

  Future<void> _preview() async {
    final code = _codeController.text.trim();
    final title = _titleController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi dulu kode/teks untuk QR')),
      );
      return;
    }

    final bytes = await _buildPdf(code, title);
    if (!mounted) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Code Maker'),
        actions: [
          IconButton(
            tooltip: 'Preview / Print',
            onPressed: _preview,
            icon: const Icon(Icons.print),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Judul label (opsional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Teks/Kode untuk QR',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _preview,
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Preview / Print QR'),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tip: isi dengan item_code / kode produk / nomor dokumen sesuai kebutuhan.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

