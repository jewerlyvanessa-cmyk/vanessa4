import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/utils/network_config.dart';

/// Backup database penuh (pg_dump) ke Google Drive via API server.
class BackupGoogleDrivePage extends StatefulWidget {
  const BackupGoogleDrivePage({super.key});

  @override
  State<BackupGoogleDrivePage> createState() => _BackupGoogleDrivePageState();
}

class _BackupGoogleDrivePageState extends State<BackupGoogleDrivePage> {
  bool _loadingStatus = true;
  bool _backingUp = false;
  String? _error;
  bool _configured = false;
  bool _googleApisInstalled = false;
  bool _folderSet = false;
  bool _serviceAccountSet = false;
  String? _serviceAccountEmail;
  Map<String, dynamic>? _lastResult;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loadingStatus = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get('/api/admin/backup/google-drive/status');
      if (res.statusCode != 200) {
        setState(() {
          _error = 'Gagal memuat status (${res.statusCode})';
          _loadingStatus = false;
        });
        return;
      }
      final m = jsonDecode(res.body);
      if (m is! Map) throw Exception('Respons tidak valid');
      setState(() {
        _configured = m['configured'] == true;
        // API lama tidak mengirim googleapis_installed; jika configured=true, anggap OK.
        _googleApisInstalled = m.containsKey('googleapis_installed')
            ? m['googleapis_installed'] == true
            : _configured;
        _folderSet = m['folder_id_set'] == true;
        _serviceAccountSet = m['service_account_set'] == true;
        _serviceAccountEmail = m['service_account_email']?.toString();
        _loadingStatus = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loadingStatus = false;
      });
    }
  }

  Future<void> _runBackup() async {
    setState(() {
      _backingUp = true;
      _error = null;
      _lastResult = null;
    });
    try {
      final uri = Uri.parse(
        '${NetworkConfig.baseUrl}/api/admin/backup/google-drive',
      );
      final res = await http
          .post(
            uri,
            headers: NetworkConfig.defaultHeaders,
            body: jsonEncode(<String, dynamic>{}),
          )
          .timeout(const Duration(minutes: 10));

      if (res.statusCode == 503) {
        final m = jsonDecode(res.body);
        final msg = m is Map ? (m['error'] ?? 'Google Drive belum dikonfigurasi') : res.body;
        setState(() {
          _error = msg.toString();
          _backingUp = false;
        });
        await _loadStatus();
        return;
      }
      if (res.statusCode != 200) {
        setState(() {
          _error = 'Backup gagal (${res.statusCode}): ${res.body}';
          _backingUp = false;
        });
        return;
      }
      final m = jsonDecode(res.body);
      if (m is! Map) throw Exception('Respons tidak valid');
      setState(() {
        _lastResult = Map<String, dynamic>.from(m);
        _backingUp = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backup berhasil diunggah ke Google Drive'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _error = '$e';
        _backingUp = false;
      });
    }
  }

  String _formatBytes(dynamic v) {
    final n = num.tryParse(v?.toString() ?? '') ?? 0;
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup ke Google Drive'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang status',
            onPressed: _loadingStatus || _backingUp ? null : _loadStatus,
          ),
        ],
      ),
      body: _loadingStatus
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
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
                              Icons.cloud_upload,
                              color: cs.primary,
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Backup database',
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
                          'Membuat dump PostgreSQL (seluruh database) lalu mengunggah ke folder Google Drive yang dikonfigurasi di server.',
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
                          'Status konfigurasi server',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        _statusRow(
                          'Google Drive API',
                          _googleApisInstalled,
                        ),
                        _statusRow(
                          'Folder ID',
                          _folderSet,
                        ),
                        _statusRow(
                          'Service account',
                          _serviceAccountSet,
                        ),
                        if (_serviceAccountEmail != null &&
                            _serviceAccountEmail!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Email service account (share folder Drive ke email ini):',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            _serviceAccountEmail!,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (!_configured) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Administrator server harus mengisi GOOGLE_DRIVE_FOLDER_ID dan kredensial service account di backend/.env, lalu restart API.',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.error,
                            ),
                          ),
                        ],
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
                            'Backup terakhir',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text('File: ${_lastResult!['file_name'] ?? '—'}'),
                          Text(
                            'Ukuran: ${_formatBytes(_lastResult!['size_bytes'])}',
                          ),
                          if (_lastResult!['web_view_link'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: SelectableText(
                                _lastResult!['web_view_link'].toString(),
                                style: TextStyle(color: cs.primary),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: !_configured || _backingUp ? null : _runBackup,
                  icon: _backingUp
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.backup),
                  label: Text(
                    _backingUp ? 'Membackup & mengunggah…' : 'Backup sekarang',
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statusRow(String label, bool ok) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.cancel,
            color: ok ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(ok ? 'OK' : 'Belum'),
        ],
      ),
    );
  }
}
