import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

class ExportDataPage extends ConsumerStatefulWidget {
  const ExportDataPage({super.key});

  @override
  ConsumerState<ExportDataPage> createState() => _ExportDataPageState();
}

class _ExportDataPageState extends ConsumerState<ExportDataPage> {
  String _selectedDataType = 'customers';
  String _exportFormat = 'csv';
  bool _isExporting = false;
  String _exportStatus = '';
  Map<String, dynamic>? _exportResult;

  final List<Map<String, String>> _dataTypes = [
    {'value': 'customers', 'label': 'Pelanggan (Customers)'},
    {'value': 'branches', 'label': 'Cabang (Branches)'},
    {'value': 'items', 'label': 'Barang (Items)'},
    {'value': 'users', 'label': 'Pengguna (Users)'},
    {'value': 'orders', 'label': 'Pesanan (Orders)'},
    {'value': 'payments', 'label': 'Pembayaran (Payments)'},
  ];

  final List<Map<String, String>> _exportFormats = [
    {'value': 'csv', 'label': 'CSV'},
    {'value': 'xlsx', 'label': 'Excel (XLSX)'},
    {'value': 'json', 'label': 'JSON'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export Data'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetExport,
            tooltip: 'Reset',
          ),
        ],
      ),
      body: ResponsiveLayout.scrollablePage(
        context: context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.download,
                          color: Colors.green,
                          size: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Export Data',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Export data sistem dalam berbagai format untuk backup atau analisis',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Data Type Selection
            const Text(
              'Jenis Data',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedDataType,
                  decoration: const InputDecoration(
                    labelText: 'Pilih jenis data yang akan diexport',
                    border: OutlineInputBorder(),
                  ),
                  items: _dataTypes.map((type) {
                    return DropdownMenuItem(
                      value: type['value'],
                      child: Text(type['label']!),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedDataType = value!;
                      _resetExport();
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Export Format Selection
            const Text(
              'Format Export',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<String>(
                  initialValue: _exportFormat,
                  decoration: const InputDecoration(
                    labelText: 'Pilih format file export',
                    border: OutlineInputBorder(),
                  ),
                  items: _exportFormats.map((format) {
                    return DropdownMenuItem(
                      value: format['value'],
                      child: Text(format['label']!),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _exportFormat = value!;
                      _resetExport();
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Export Button
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(
                      Icons.file_download,
                      size: 48,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Siap untuk Export',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'File akan diunduh dalam format ${_exportFormats.firstWhere((f) => f['value'] == _exportFormat)['label']}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isExporting ? null : _exportData,
                      icon: _isExporting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                      label: Text(
                        _isExporting ? 'Mengexport...' : 'Export Data',
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Export Status
            if (_exportStatus.isNotEmpty) ...[
              const Text(
                'Status Export',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                color: _exportResult?['success'] == true
                    ? Colors.green[50]
                    : Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _exportResult?['success'] == true
                                ? Icons.check_circle
                                : Icons.error,
                            color: _exportResult?['success'] == true
                                ? Colors.green
                                : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _exportStatus,
                            style: TextStyle(
                              color: _exportResult?['success'] == true
                                  ? Colors.green
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (_exportResult != null &&
                          _exportResult!['recordCount'] != null) ...[
                        const SizedBox(height: 16),
                        Text('Jumlah data: ${_exportResult!['recordCount']}'),
                        Text(
                          'Format: ${_exportFormats.firstWhere((f) => f['value'] == _exportFormat)['label']}',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Export History
            const Text(
              'Riwayat Export',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.history, size: 32, color: Colors.grey),
                    const SizedBox(height: 8),
                    const Text(
                      'Belum ada riwayat export',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'File export akan muncul di sini setelah berhasil diexport',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Information
            const Text(
              'Informasi',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoItem(
                      'CSV',
                      'Format universal yang dapat dibuka dengan Excel, Google Sheets, dll.',
                    ),
                    const SizedBox(height: 12),
                    _buildInfoItem(
                      'Excel (XLSX)',
                      'Format Excel modern dengan dukungan formula dan styling.',
                    ),
                    const SizedBox(height: 12),
                    _buildInfoItem(
                      'JSON',
                      'Format data terstruktur untuk developer dan integrasi sistem.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title: ', style: const TextStyle(fontWeight: FontWeight.bold)),
        Expanded(child: Text(description)),
      ],
    );
  }

  Future<void> _exportData() async {
    setState(() {
      _isExporting = true;
      _exportStatus = 'Mengambil data dari server...';
      _exportResult = null;
    });

    try {
      final rows = await _fetchExportRows(_selectedDataType);
      if (rows.isEmpty) {
        setState(() {
          _isExporting = false;
          _exportStatus = 'Tidak ada data untuk diexport';
          _exportResult = {'success': false, 'message': 'Data kosong'};
        });
        return;
      }

      setState(() => _exportStatus = 'Membuat file...');

      final safeType = _selectedDataType.replaceAll(RegExp(r'[^\w-]'), '_');
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');

      if (_exportFormat == 'json') {
        final content = const JsonEncoder.withIndent('  ').convert(rows);
        final name = 'export_${safeType}_$stamp.json';
        await _shareExportContent(name, content);
      } else if (_exportFormat == 'csv') {
        final content = _toCsv(rows);
        final name = 'export_${safeType}_$stamp.csv';
        await _shareExportContent(name, content);
      } else if (_exportFormat == 'xlsx') {
        if (kIsWeb) {
          setState(() {
            _isExporting = false;
            _exportStatus =
                'XLSX di web belum didukung; gunakan JSON atau CSV.';
            _exportResult = {'success': false};
          });
          return;
        }
        final bytes = _toXlsx(rows);
        final name = 'export_${safeType}_$stamp.xlsx';
        await _shareExportBytes(name, bytes);
      }

      setState(() {
        _isExporting = false;
        _exportStatus =
            'Export selesai. Pilih aplikasi untuk menyimpan / membagikan.';
        _exportResult = {'success': true, 'recordCount': rows.length};
      });
    } catch (e) {
      setState(() {
        _isExporting = false;
        _exportStatus = 'Gagal export: $e';
        _exportResult = {'success': false, 'message': e.toString()};
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchExportRows(String type) async {
    final path = switch (type) {
      'customers' => '/api/customers',
      'branches' => '/branches',
      'items' => '/items',
      'users' => '/users',
      'orders' => '/orders',
      'payments' => '/payments',
      _ => throw ArgumentError('Jenis data tidak dikenal: $type'),
    };

    final response = await ApiClient.get(path);

    if (response.statusCode != 200) {
      throw Exception('Server ${response.statusCode}: ${response.body}');
    }

    final decoded = json.decode(response.body);
    if (decoded is! List) {
      throw Exception('Respons bukan array');
    }

    var rows = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    if (type == 'users') {
      rows = rows.map((r) {
        final m = Map<String, dynamic>.from(r);
        m.remove('password_hash');
        return m;
      }).toList();
    }

    return rows;
  }

  String _cell(dynamic v) {
    if (v == null) return '';
    if (v is Map || v is List) return jsonEncode(v);
    final s = v.toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  String _toCsv(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '';
    final keys = rows.expand((m) => m.keys).toSet().toList()..sort();
    final buf = StringBuffer();
    buf.writeln(keys.map(_cell).join(','));
    for (final r in rows) {
      buf.writeln(keys.map((k) => _cell(r[k])).join(','));
    }
    return buf.toString();
  }

  List<int> _toXlsx(List<Map<String, dynamic>> rows) {
    String excelCell(dynamic v) {
      if (v == null) return '';
      if (v is Map || v is List) return jsonEncode(v);
      return v.toString();
    }

    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? excel.tables.keys.first;
    final sheet = excel[sheetName];
    if (rows.isEmpty) {
      final out = excel.encode();
      if (out == null) throw Exception('Gagal membuat XLSX');
      return out;
    }
    final keys = rows.expand((m) => m.keys).toSet().toList()..sort();
    for (var c = 0; c < keys.length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .value = TextCellValue(
        keys[c],
      );
    }
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < keys.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
            .value = TextCellValue(
          excelCell(rows[r][keys[c]]),
        );
      }
    }
    final out = excel.encode();
    if (out == null) throw Exception('Gagal encode XLSX');
    return out;
  }

  Future<void> _shareExportContent(String filename, String content) async {
    if (kIsWeb) {
      await SharePlus.instance.share(
        ShareParams(text: content, subject: filename),
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$filename';
    final file = File(path);
    await file.writeAsString(content, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], subject: filename),
    );
  }

  Future<void> _shareExportBytes(String filename, List<int> bytes) async {
    if (kIsWeb) {
      throw UnsupportedError('Binary export tidak didukung di web');
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$filename';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], subject: filename),
    );
  }

  void _resetExport() {
    setState(() {
      _isExporting = false;
      _exportStatus = '';
      _exportResult = null;
    });
  }
}
