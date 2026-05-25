import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';

import '../../../core/network/api_client.dart';
import 'user_management_page.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

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
      case 'owner':
        return 'Owner';
      case 'admin_workshop':
        return 'Admin Workshop';
      case 'stockist':
        return 'Stockist';
      case 'admin_warehouse':
        return 'Admin Warehouse';
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

  int? _parseUserId(Map<String, dynamic> u) {
    final raw = u['user_id'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  Future<void> _logoutUserFromApp(int userId, String username) async {
    final label = username.isEmpty ? 'User #$userId' : username;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Melogoutkan user'),
        content: Text(
          'Logout $label dari aplikasi?\n\n'
          'Semua perangkat/tab yang terhubung (Live) akan keluar dan harus login lagi.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Logout user')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final res = await ApiClient.post(
        '/api/admin/active-sessions/$userId/kick',
        body: jsonEncode(<String, dynamic>{}),
      );
      if (res.statusCode != 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${res.body}')),
        );
        return;
      }
      final decoded = jsonDecode(res.body);
      final closed = decoded is Map ? decoded['closed'] : null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'User dilogoutkan (${closed ?? '?'} koneksi).',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal melogoutkan user: $e')),
      );
    }
  }

  Future<void> _deactivateUserAccount(int userId, String username) async {
    final me = ref.read(userStateProvider).userId;
    if (me == userId) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gunakan manajemen user untuk mengubah akun Anda sendiri.')),
      );
      return;
    }
    final label = username.isEmpty ? 'User #$userId' : username;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nonaktifkan akun'),
        content: Text(
          'Nonaktifkan akun $label?\n\n'
          'User tidak bisa login sampai diaktifkan kembali. '
          'Jika masih terhubung Live, sebaiknya dilogoutkan dulu dari menu ini.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Nonaktifkan'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final res = await ApiClient.patch(
        '/users/$userId/status',
        body: jsonEncode(<String, dynamic>{'status': 'inactive'}),
      );
      if (res.statusCode != 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${res.body}')),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Akun dinonaktifkan.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menonaktifkan: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = ref.watch(userStateProvider).userId;

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
                                'Semua user yang sedang terhubung (WebSocket aktif) di seluruh cabang — tidak difilter cabang login Anda.',
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
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: _users.isEmpty
                            ? const Center(
                                child: Text(
                                  'Tidak ada sesi aktif.\nPastikan pengguna sudah login dan koneksi Live menyala.',
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final narrow = constraints.maxWidth < 640;
                                  final cs = Theme.of(context).colorScheme;
const desktopW = 900.0;
                                  final panelW = constraints.maxWidth;
                                  final BoxConstraints box;
                                  if (narrow) {
                                    box = BoxConstraints.tightFor(width: panelW);
                                  } else if (panelW >= desktopW) {
                                    box = BoxConstraints.tightFor(width: desktopW);
                                  } else {
                                    box = const BoxConstraints(minWidth: desktopW);
                                  }

                                  final rows = <DataRow>[];
                                  for (var i = 0; i < _users.length; i++) {
                                    final u = _users[i];
                                    final username =
                                        (u['username'] ?? '').toString();
                                    final role = _roleLabel(
                                      u['role_active']?.toString(),
                                    );
                                    final branch = (u['branch_display'] ??
                                            u['branch_id'] ??
                                            '')
                                        .toString();
                                    final sessions = int.tryParse(
                                          u['sessions']?.toString() ?? '',
                                        ) ??
                                        1;
                                    final uid = _parseUserId(u);
                                    final isSelf =
                                        myUserId != null && uid == myUserId;
                                    final titleText = username.isEmpty
                                        ? 'User #${u['user_id']}'
                                        : username;

                                    final menu = uid == null
                                        ? const DataCell(SizedBox.shrink())
                                        : DataCell(
                                            Align(
                                              alignment:
                                                  Alignment.centerRight,
                                              child: PopupMenuButton<String>(
                                                icon: const Icon(
                                                  Icons.more_vert,
                                                ),
                                                tooltip: 'Tindakan',
                                                onSelected: (value) async {
                                                  if (value == 'logout') {
                                                    await _logoutUserFromApp(
                                                      uid,
                                                      username,
                                                    );
                                                  } else if (value ==
                                                      'deactivate') {
                                                    await _deactivateUserAccount(
                                                      uid,
                                                      username,
                                                    );
                                                  } else if (value == 'users') {
                                                    if (!context.mounted) {
                                                      return;
                                                    }
                                                    await Navigator.push<void>(
                                                      context,
                                                      MaterialPageRoute<void>(
                                                        builder: (ctx) =>
                                                            const UserManagementPage(),
                                                      ),
                                                    );
                                                  }
                                                },
                                                itemBuilder: (ctx) => [
                                                  if (!isSelf)
                                                    const PopupMenuItem(
                                                      value: 'logout',
                                                      child: Text(
                                                        'Melogoutkan user',
                                                      ),
                                                    ),
                                                  if (!isSelf)
                                                    const PopupMenuItem(
                                                      value: 'deactivate',
                                                      child: Text(
                                                        'Nonaktifkan akun',
                                                      ),
                                                    ),
                                                  const PopupMenuItem(
                                                    value: 'users',
                                                    child: Text(
                                                      'Buka manajemen user',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );

                                    rows.add(
                                      DataRow(
                                        color:
                                            WidgetStateProperty.resolveWith(
                                                (states) {
                                          if (states.contains(
                                            WidgetState.hovered,
                                          )) {
                                            return cs.primary
                                                .withValues(alpha: 0.06);
                                          }
                                          return i.isOdd
                                              ? cs.surfaceContainerHighest
                                                  .withValues(alpha: 0.45)
                                              : null;
                                        }),
                                        cells: narrow
                                            ? [
                                                DataCell(
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Text(
                                                        titleText,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                      Text(
                                                        '$role · ${branch.isEmpty ? '—' : branch}',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: cs
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    sessions > 1
                                                        ? '$sessions sesi'
                                                        : '1',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          sessions > 1
                                                              ? FontWeight.w600
                                                              : null,
                                                      color: sessions > 1
                                                          ? cs.primary
                                                          : null,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                                menu,
                                              ]
                                            : [
                                                DataCell(
                                                  Text(
                                                    titleText,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                                DataCell(Text(role)),
                                                DataCell(
                                                  Text(
                                                    branch.isEmpty ? '—' : branch,
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    _sinceLabel(
                                                      u['connected_since']
                                                          ?.toString(),
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: cs
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    '$sessions',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          sessions > 1
                                                              ? FontWeight.w700
                                                              : null,
                                                      color: sessions > 1
                                                          ? cs.primary
                                                          : null,
                                                    ),
                                                  ),
                                                ),
                                                menu,
                                              ],
                                      ),
                                    );
                                  }

                                  return Material(
                                    elevation: 0,
                                    color: cs.surfaceContainerLow
                                        .withValues(alpha: 0.65),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: cs.outlineVariant
                                            .withValues(alpha: 0.45),
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Scrollbar(
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.vertical,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Align(
                                            alignment: Alignment.topLeft,
                                            child: ConstrainedBox(
                                              constraints: box,
                                              child: DataTable(
                                                headingRowColor:
                                                    WidgetStateProperty.all(
                                                  cs.surfaceContainerHigh,
                                                ),
dataRowMinHeight:
                                                    narrow ? 48 : 44,
                                                dataRowMaxHeight:
                                                    narrow ? 56 : 56,
                                                columnSpacing:
                                                    narrow ? 8 : 14,
                                                horizontalMargin:
                                                    narrow ? 8 : 12,
                                                showCheckboxColumn: false,
                                                dividerThickness: 0.5,
                                                columns: narrow
                                                    ? [
                                                        DataColumn(
                                                          label: dataTableColumnLabel(
                                                            'User',
                                                          ),
                                                        ),
                                                        DataColumn(
                                                          label: dataTableColumnLabel(
                                                            'Sesi',
                                                          ),
                                                        ),
                                                        const DataColumn(
                                                          label: SizedBox(
                                                            width: 44,
                                                          ),
                                                        ),
                                                      ]
                                                    : [
                                                        DataColumn(
                                                          label:
                                                              dataTableColumnLabel('Username'),
                                                        ),
                                                        DataColumn(
                                                          label: dataTableColumnLabel('Role'),
                                                        ),
                                                        DataColumn(
                                                          label:
                                                              dataTableColumnLabel('Cabang'),
                                                        ),
                                                        DataColumn(
                                                          label: dataTableColumnLabel(
                                                            'Terhubung',
                                                          ),
                                                        ),
                                                        DataColumn(
                                                          label: dataTableColumnLabel('Sesi'),
                                                        ),
                                                        const DataColumn(
                                                          label: SizedBox(
                                                            width: 48,
                                                          ),
                                                        ),
                                                      ],
                                                rows: rows,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
