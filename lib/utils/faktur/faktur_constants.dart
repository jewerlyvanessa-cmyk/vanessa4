import 'package:pdf/pdf.dart';

/// Faktur order — portrait toko: **lebar 21 cm** × **panjang 11 cm** (area cetak).
const double kFakturLebarCm = 21;
const double kFakturPanjangCm = 10;

PdfPageFormat get kFakturPageFormat => PdfPageFormat(
  kFakturLebarCm * PdfPageFormat.cm,
  kFakturPanjangCm * PdfPageFormat.cm,
  marginAll: 0.5 * PdfPageFormat.cm,
);

/// Faktur PDF: transaksi order awal vs bukti pengambilan (judul & footer berbeda).
enum FakturPrintKind { orderTransaction, pickup }
