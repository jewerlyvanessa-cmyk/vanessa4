import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/responsive_layout.dart';
import 'package:vanessa3/utils/save_download_bytes.dart';

/// Unduh dump database (pg_dump) ke perangkat lokal (simpan / bagikan).
class BackupLocalPage extends StatefulWidget {
  const BackupLocalPage({super.key});

  @override
  State<BackupLocalPage> createState() => _BackupLocalPageState();
}

class _BackupLocalPageState extends State<BackupLocalPage> {
  bool _backingUp = false;
  String? _error;
  Map<String, dynamic>? _lastResult;

  String _formatBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String? _filenameFromDisposition(String? header) {
    if (header == null || header.isEmpty) return null;
    final match = RegExp(
      r'''filename\*=UTF-8''([^;]+)|filename="([^"]+)"|filename=([^;\s]+)''',
    ).firstMatch(header);
    if (match == null) return null;
    return (match.group(1) ?? match.group(2) ?? match.group(3))?.trim();
  }

  Future<void> _runBackup() async {
    setState(() {
      _backingUp = true;
      _error = null;
      _lastResult = null;
    });

    try {
      final uri = Uri.parse('${NetworkConfig.baseUrl}/api/admin/backup/local');
      final headers = Map<String, String>.from(NetworkConfig.defaultHeaders);
      headers['Accept'] = 'application/sql, application/octet-stream, */*';

      final res = await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode(<String, dynamic>{}),
          )
          .timeout(const Duration(minutes: 15));

      if (res.statusCode != 200) {
        String msg = 'Backup gagal (${res.statusCode})';
        if (res.statusCode == 404) {
          msg =
              'Endpoint backup belum tersedia di server (${NetworkConfig.baseUrl}). '
              'Deploy/restart backend terbaru (file admin_api.js dengan POST /api/admin/backup/local), '
              'atau jalankan app dengan USE_LOCAL_API=true ke API lokal yang sudah di-restart.';
        }
        try {
          final m = jsonDecode(res.body);
          if (m is Map && m['error'] != null) {
            msg = m['error'].toString();
            final hint = m['hint']?.toString();
            if (hint != null && hint.isNotEmpty) {
              msg = '$msg\n$hint';
            }
          }
        } catch (_) {
          if (res.statusCode != 404 && res.body.isNotEmpty) {
            msg = '$msg: ${res.body}';
          }
        }
        setState(() {
          _error = msg;
          _backingUp = false;
        });
        return;
      }

      final bytes = res.bodyBytes;
      if (bytes.isEmpty) {
        setState(() {
          _error = 'File backup kosong';
          _backingUp = false;
        });
        return;
      }

      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final fileName = _filenameFromDisposition(
            res.headers['content-disposition'],
          ) ??
          'vanessa_store_$stamp.sql';

      await saveDownloadBytes(
        filename: fileName,
        bytes: bytes,
        mimeType: 'application/sql',
      );

      if (!mounted) return;
      setState(() {
        _lastResult = {
          'file_name': fileName,
          'size_bytes': bytes.length,
          'saved_at': DateTime.now().toLocal().toString().split('.')[0],
        };
        _backingUp = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Backup berhasil. Simpan file di perangkat Anda (Files / Downloads).',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _backingUp = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup Lokal'),
      ),
      body: ResponsiveLayout.scrollablePage(
        context: context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.phone_android,
                          color: cs.primary,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Backup ke perangkat',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Server membuat dump PostgreSQL (seluruh database), lalu file .sql diunduh ke HP, tablet, atau komputer ini. Gunakan menu simpan / bagikan sistem untuk menyimpan ke folder Downloads atau penyimpanan lain.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Catatan',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Membutuhkan koneksi ke server API dan pg_dump di server.\n'
                      '• File berisi data sensitif — simpan di tempat aman.\n'
                      '• Untuk backup otomatis ke cloud, gunakan menu Backup Drive.',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Card(
                color: cs.errorContainer.withValues(alpha: 0.4),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: cs.onErrorContainer),
                  ),
                ),
              ),
            ],
            if (_lastResult != null) ...[
              const SizedBox(height: 16),
              Card(
                color: cs.primaryContainer.withValues(alpha: 0.35),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Backup terakhir di perangkat ini',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('File: ${_lastResult!['file_name']}'),
                      Text(
                        'Ukuran: ${_formatBytes(_lastResult!['size_bytes'] as int)}',
                      ),
                      Text('Waktu: ${_lastResult!['saved_at']}'),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _backingUp ? null : _runBackup,
              icon: _backingUp
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download),
              label: Text(
                _backingUp ? 'Mengunduh backup…' : 'Backup & simpan lokal',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
