import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/utils/import_data_excel_template.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/responsive_layout.dart';
import 'package:vanessa3/utils/save_download_bytes.dart';

class ImportDataPage extends ConsumerStatefulWidget {
  const ImportDataPage({super.key});

  @override
  ConsumerState<ImportDataPage> createState() => _ImportDataPageState();
}

class _ImportDataPageState extends ConsumerState<ImportDataPage> {
  String _selectedDataType = 'customers';
  Map<String, dynamic>? _selectedFile;
  bool _isImporting = false;
  bool _isDownloadingTemplate = false;
  String _importStatus = '';
  Map<String, dynamic>? _importResult;

  final List<Map<String, String>> _dataTypes = [
    {'value': 'customers', 'label': 'Pelanggan (Customers)'},
    {'value': 'branches', 'label': 'Cabang (Branches)'},
    {'value': 'items', 'label': 'Barang (Items)'},
    {'value': 'users', 'label': 'Pengguna (Users)'},
    {'value': 'orders', 'label': 'Order / Transaksi (Orders)'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Data'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetImport,
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
                        const Icon(Icons.upload_file, color: Colors.blue, size: 32),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Import Data Massal',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Upload file CSV atau Excel untuk mengimport data secara massal',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _selectedDataType,
                      decoration: const InputDecoration(
                        labelText: 'Pilih jenis data yang akan diimport',
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
                          _resetImport();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed:
                          _isDownloadingTemplate ? null : _downloadTemplate,
                      icon: _isDownloadingTemplate
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_outlined),
                      label: Text(
                        _isDownloadingTemplate
                            ? 'Menyiapkan template…'
                            : 'Download template Excel',
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // File Selection
            const Text(
              'File Data',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (_selectedFile == null) ...[
                      const Icon(
                        Icons.file_upload,
                        size: 48,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Belum ada file yang dipilih',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _pickFile,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Pilih File'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          const Icon(
                            Icons.insert_drive_file,
                            color: Colors.blue,
                            size: 32,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedFile!['name'] ?? 'File',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${(_selectedFile!['size'] ?? 0) / 1024.toStringAsFixed(1)} KB',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(() {
                                _selectedFile = null;
                                _resetImport();
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _isImporting ? null : _importData,
                        icon: _isImporting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.upload),
                        label: Text(_isImporting ? 'Mengimport...' : 'Import Data'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Import Status
            if (_importStatus.isNotEmpty) ...[
              const Text(
                'Status Import',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                color: _importResult?['success'] == true ? Colors.green[50] : Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _importResult?['success'] == true
                                ? Icons.check_circle
                                : Icons.error,
                            color: _importResult?['success'] == true
                                ? Colors.green
                                : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _importStatus,
                            style: TextStyle(
                              color: _importResult?['success'] == true
                                  ? Colors.green
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (_importResult != null) ...[
                        const SizedBox(height: 16),
                        if (_importResult!['inserted'] != null)
                          Text('Data berhasil diinsert: ${_importResult!['inserted']}'),
                        if (_importResult!['updated'] != null)
                          Text('Data berhasil diupdate: ${_importResult!['updated']}'),
                        if (_importResult!['errors'] != null && _importResult!['errors'].isNotEmpty)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Error:', style: TextStyle(color: Colors.red)),
                              ...(_importResult!['errors'] as List).map((error) =>
                                Text('• $error', style: const TextStyle(color: Colors.red, fontSize: 12))
                              ),
                            ],
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Instructions
            const Text(
              'Panduan Import',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInstructionItem(
                      'Format File',
                      'CSV atau Excel (XLSX). Baris pertama = header kolom. '
                      'Gunakan tombol Download template Excel di atas.',
                    ),
                    const SizedBox(height: 12),
                    _buildInstructionItem(
                      'Header Kolom',
                      _getColumnHeaders(),
                    ),
                    const SizedBox(height: 12),
                    _buildInstructionItem(
                      'Validasi',
                      'Data akan divalidasi sebelum diimport. Baris dengan error akan dilewati',
                    ),
                    const SizedBox(height: 12),
                    _buildInstructionItem(
                      'Duplikasi',
                      'Data dengan ID yang sama akan diupdate, bukan ditambahkan',
                    ),
                    if (_selectedDataType == 'orders') ...[
                      const SizedBox(height: 12),
                      _buildInstructionItem(
                        'Order',
                        'order_type: jual, buyback, service, custom. '
                        'Update by order_id atau order_number jika sudah ada. '
                        'Baris item order tidak diimport lewat file ini.',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionItem(String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.black),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: description),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _getColumnHeaders() {
    final cols = importDataTemplateColumns[_selectedDataType];
    if (cols == null) return '';
    return cols.join(', ');
  }

  Future<void> _downloadTemplate() async {
    setState(() => _isDownloadingTemplate = true);
    try {
      final bytes = buildImportDataTemplateXlsx(_selectedDataType);
      final filename = importTemplateFilename(_selectedDataType);
      await saveDownloadBytes(
        filename: filename,
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Template $filename siap'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal unduh template: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isDownloadingTemplate = false);
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          _selectedFile = {
            'name': file.name,
            'path': file.path,
            'size': file.size,
            'extension': file.extension,
          };
          _resetImport();
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File "${file.name}" berhasil dipilih'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error memilih file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _importData() async {
    if (_selectedFile == null || !_selectedFile!.containsKey('path')) return;

    setState(() {
      _isImporting = true;
      _importStatus = 'Mengupload dan memproses file...';
      _importResult = null;
    });

    try {
      final filePath = _selectedFile!['path'];
      final file = File(filePath);

      if (!await file.exists()) {
        throw Exception('File tidak ditemukan');
      }

      // Create multipart request
      final uri = Uri.parse('${NetworkConfig.baseUrl}/api/import/$_selectedDataType');
      final request = http.MultipartRequest('POST', uri);

      // Add file to request
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: _selectedFile!['name'],
        ),
      );

      request.fields['dataType'] = _selectedDataType;

      final authHeaders = Map<String, String>.from(NetworkConfig.defaultHeaders)
        ..remove('Content-Type');
      request.headers.addAll(authHeaders);

      // Send request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(responseBody);
        setState(() {
          _isImporting = false;
          _importStatus = 'Import berhasil';
          _importResult = {
            'success': true,
            'inserted': result['inserted'] ?? 0,
            'updated': result['updated'] ?? 0,
            'errors': result['errors'] ?? [],
          };
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Data berhasil diimport'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        final errorData = jsonDecode(responseBody);
        throw Exception(errorData['message'] ?? 'Gagal mengimport data');
      }
    } catch (e) {
      setState(() {
        _isImporting = false;
        _importStatus = 'Import gagal';
        _importResult = {
          'success': false,
          'errors': [e.toString()],
        };
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _resetImport() {
    setState(() {
      _selectedFile = null;
      _isImporting = false;
      _importStatus = '';
      _importResult = null;
    });
  }
}
