import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/providers/websocket_provider.dart';

import '../../../core/network/api_client.dart';

class ActiveUserSessionsPage extends ConsumerStatefulWidget {
  const ActiveUserSessionsPage({super.key});

  @override
  ConsumerState<ActiveUserSessionsPage> createState() =>
      _ActiveUserSessionsPageState();
}

class _ActiveUserSessionsPageState extends ConsumerState<ActiveUserSessionsPage> {
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _users = [];
  int _totalConnections = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final us = ref.read(userStateProvider);
      ref
          .read(webSocketProvider.notifier)
          .ensureConnected(authToken: us.authToken);
      _load();
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted) _load();
      });
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await ApiClient.get('/api/admin/active-sessions');
      if (res.statusCode != 200) {
        setState(() {
          _error = 'Gagal memuat (HTTP ${res.statusCode})';
          _loading = false;
        });
        return;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        setState(() {
          _error = 'Format respons tidak valid';
          _loading = false;
        });
        return;
      }
      final list = decoded['users'];
      setState(() {
        _users = list is List
            ? list
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : [];
        final tc = decoded['total_connections'];
        _totalConnections = tc is int
            ? tc
            : int.tryParse(tc?.toString() ?? '') ??
                _users.fold<int>(
                  0,
                  (s, u) =>
                      s + (int.tryParse(u['sessions']?.toString() ?? '1') ?? 1),
                );
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _roleLabel(String? role) {
    switch ((role ?? '').trim().toLowerCase()) {
      case 'superadmin':
        return 'Super Admin';
      case 'admin_toko':
        return 'Admin Toko';
      case 'kasir':
        return 'Kasir';
      case 'cs':
        return 'Customer Service';
      case 'tukang':
        return 'Tukang';
      case 'manajer':
        return 'Manajer';
      case 'admin_workshop':
        return 'Admin Workshop';
      case 'stockist':
        return 'Stockist';
      default:
        return role == null || role.isEmpty ? '—' : role;
    }
  }

  String _sinceLabel(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(dt);
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Login Aktif'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ringkasan',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'User unik: ${_users.length} · Total koneksi WebSocket: $_totalConnections',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Daftar ini memuat pengguna yang sedang terhubung ke server (app terbuka, WebSocket aktif, token valid).',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[700],
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _users.isEmpty
                          ? const Center(
                              child: Text(
                                'Tidak ada sesi aktif.\nPastikan pengguna sudah login dan koneksi Live menyala.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _users.length,
                              itemBuilder: (context, i) {
                                final u = _users[i];
                                final username =
                                    (u['username'] ?? '').toString();
                                final role =
                                    _roleLabel(u['role_active']?.toString());
                                final branch =
                                    (u['branch_id'] ?? '').toString();
                                final sessions =
                                    int.tryParse(u['sessions']?.toString() ?? '') ?? 1;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.person),
                                    ),
                                    title: Text(
                                      username.isEmpty ? 'User #${u['user_id']}' : username,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Text('Role aktif: $role'),
                                        Text('Cabang (ID): ${branch.isEmpty ? '—' : branch}'),
                                        Text(
                                          'Terhubung sejak: ${_sinceLabel(u['connected_since']?.toString())}',
                                        ),
                                        if (sessions > 1)
                                          Text(
                                            'Sesi: $sessions perangkat/tab',
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.primary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
