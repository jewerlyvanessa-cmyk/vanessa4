import 'package:excel/excel.dart';

/// Kolom template import massal superadmin (selaras [ImportDataPage._getColumnHeaders]).
const Map<String, List<String>> importDataTemplateColumns = {
  'customers': ['name', 'phone', 'email', 'address'],
  'branches': ['name', 'code', 'alias', 'initials', 'address', 'phone_number'],
  'items': ['name', 'weight', 'material', 'purity', 'status', 'branch_id'],
  'users': ['username', 'password_hash', 'status'],
  'orders': [
    'order_id',
    'order_type',
    'order_number',
    'branch_id',
    'user_id',
    'customer_id',
    'total',
    'diskon',
    'status',
    'mode',
  ],
};

/// Contoh baris kedua (petunjuk isian, boleh dihapus sebelum import).
const Map<String, List<String>> importDataTemplateSampleRow = {
  'customers': [
    'Budi Santoso',
    '081234567890',
    'budi@email.com',
    'Jl. Contoh No. 1',
  ],
  'branches': [
    'Toko Jakarta',
    'JKT01',
    'Jakarta Pusat',
    'JKT',
    'Alamat cabang',
    '0211234567',
  ],
  'items': [
    'Cincin Emas',
    '5.25',
    'EMAS',
    '22K',
    'ready',
    '1',
  ],
  'users': ['user_baru', '(isi password / hash)', 'active'],
  'orders': [
    '',
    'jual',
    'ORD-2025-001',
    '1',
    '1',
    '1',
    '1500000',
    '0',
    'completed',
    '',
  ],
};

String importTemplateFilename(String dataType) =>
    'template_import_$dataType.xlsx';

/// Buat file XLSX: baris 1 header, baris 2 contoh (opsional).
List<int> buildImportDataTemplateXlsx(String dataType, {bool includeSampleRow = true}) {
  final headers = importDataTemplateColumns[dataType];
  if (headers == null || headers.isEmpty) {
    throw ArgumentError('Jenis data tidak dikenal: $dataType');
  }

  final excel = Excel.createExcel();
  final sheetName = excel.getDefaultSheet() ?? excel.tables.keys.first;
  final sheet = excel[sheetName];

  for (var c = 0; c < headers.length; c++) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
        .value = TextCellValue(headers[c]);
  }

  if (includeSampleRow) {
    final sample = importDataTemplateSampleRow[dataType] ?? [];
    for (var c = 0; c < headers.length; c++) {
      final v = c < sample.length ? sample[c] : '';
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1))
          .value = TextCellValue(v);
    }
  }

  final encoded = excel.encode();
  if (encoded == null) {
    throw Exception('Gagal membuat file template Excel');
  }
  return encoded;
}
