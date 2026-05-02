import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/main.dart';
import 'package:vanessa3/utils/network_config.dart';

class ManagerUsersPage extends ConsumerStatefulWidget {
  const ManagerUsersPage({super.key});

  @override
  ConsumerState<ManagerUsersPage> createState() => _ManagerUsersPageState();
}

class _ManagerUsersPageState extends ConsumerState<ManagerUsersPage> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userState = ref.read(userStateProvider);
      final branchId = (userState.branch).toString();
      final uri = Uri.parse('${NetworkConfig.baseUrl}/employees')
          .replace(queryParameters: {'branch_id': branchId});

      final res = await http.get(uri, headers: NetworkConfig.defaultHeaders);
      if (res.statusCode != 200) {
        setState(() {
          _error = 'Gagal memuat data user (${res.statusCode})';
          _isLoading = false;
        });
        return;
      }

      final data = jsonDecode(res.body);
      setState(() {
        _rows = (data is List) ? List<dynamic>.from(data) : <dynamic>[];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _asMaps(List<dynamic> list) {
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  String _userKeyForRow(Map<String, dynamic> row) {
    final userId =
        (row['user_id'] ?? row['id'] ?? row['userId'] ?? '').toString().trim();
    if (userId.isNotEmpty) return 'id:$userId';
    final username =
        (row['username'] ?? row['name'] ?? '').toString().trim().toLowerCase();
    return 'u:$username';
  }

  int _countUniqueUsers(Iterable<Map<String, dynamic>> rows) {
    final keys = rows.map(_userKeyForRow).where((k) => k != 'u:').toSet();
    return keys.length;
  }

  int _countUniqueUsersByStatus(List<Map<String, dynamic>> rows, String status) {
    final keys = <String>{};
    for (final row in rows) {
      final rowStatus = (row['status'] ?? '').toString();
      if (rowStatus == status) keys.add(_userKeyForRow(row));
    }
    keys.remove('u:');
    return keys.length;
  }

  List<_UserGroup> _groupByUser(List<Map<String, dynamic>> rows) {
    final Map<String, List<Map<String, dynamic>>> byUser = {};
    for (final row in rows) {
      final key = _userKeyForRow(row);
      byUser.putIfAbsent(key, () => []);
      byUser[key]!.add(row);
    }

    final groups = byUser.entries.map((e) {
      final items = e.value;
      items.sort((a, b) {
        final au = (a['username'] ?? '').toString().length;
        final bu = (b['username'] ?? '').toString().length;
        return bu.compareTo(au);
      });
      return _UserGroup(user: items.first, assignments: items);
    }).toList();

    groups.sort((a, b) {
      final an = (a.user['username'] ?? '').toString().toLowerCase();
      final bn = (b.user['username'] ?? '').toString().toLowerCase();
      return an.compareTo(bn);
    });
    return groups;
  }

  Color _roleColor(String? role) {
    switch (role) {
      case 'cs':
        return Colors.blue;
      case 'kasir':
        return Colors.green;
      case 'admin_toko':
        return Colors.orange;
      case 'admin_workshop':
        return Colors.purple;
      case 'tukang':
        return Colors.red;
      case 'manajer':
        return Colors.teal;
      case 'superadmin':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'cs':
        return 'Customer Service';
      case 'kasir':
        return 'Kasir';
      case 'admin_toko':
        return 'Admin Toko';
      case 'admin_workshop':
        return 'Admin Workshop';
      case 'tukang':
        return 'Tukang';
      case 'manajer':
        return 'Manajer';
      case 'superadmin':
        return 'Super Admin';
      default:
        return (role ?? '').toString().isEmpty ? 'Unknown' : role!;
    }
  }

  Widget _summaryCard(
    String title,
    int count,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allRows = _asMaps(_rows);
    final groups = _groupByUser(allRows);

    return Scaffold(
      appBar: AppBar(
        title: const Text('User'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _load,
                        child: const Text('Coba Lagi'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _summaryCard(
                              'Total User',
                              _countUniqueUsers(allRows),
                              Icons.people,
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _summaryCard(
                              'Aktif',
                              _countUniqueUsersByStatus(allRows, 'active'),
                              Icons.check_circle,
                              Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _summaryCard(
                              'Tidak Aktif',
                              _countUniqueUsersByStatus(allRows, 'inactive'),
                              Icons.cancel,
                              Colors.red,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _summaryCard(
                              'Role (unik)',
                              allRows
                                  .map((r) => (r['role'] ?? '').toString())
                                  .where((r) => r.trim().isNotEmpty)
                                  .toSet()
                                  .length,
                              Icons.badge,
                              Colors.purple,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Daftar User (${_countUniqueUsers(allRows)})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      if (allRows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('Belum ada data user')),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: groups.length,
                          itemBuilder: (context, index) {
                            final group = groups[index];
                            final user = group.user;
                            final username =
                                (user['username'] ?? 'N/A').toString();
                            final status = (user['status'] ?? '').toString();

                            final roles = group.assignments
                                .map(
                                  (a) => (a['role'] ?? '').toString().trim(),
                                )
                                .where((r) => r.isNotEmpty)
                                .toSet()
                                .toList()
                              ..sort();
                            final primaryRole =
                                roles.isNotEmpty ? roles.first : null;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ExpansionTile(
                                leading: CircleAvatar(
                                  backgroundColor: _roleColor(primaryRole),
                                  child: Text(
                                    username.isNotEmpty
                                        ? username.substring(0, 1).toUpperCase()
                                        : '?',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                title: Text(username),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Status: ${status == 'active' ? 'Aktif' : (status.isEmpty ? 'N/A' : 'Tidak Aktif')}',
                                    ),
                                    Text(
                                      'Role: ${roles.isEmpty ? 'N/A' : roles.map(_roleLabel).join(', ')}',
                                    ),
                                  ],
                                ),
                                children: [
                                  const Divider(height: 1),
                                  ...group.assignments.map((a) {
                                    final role = (a['role'] ?? '').toString();
                                    final branch =
                                        (a['branch_name'] ?? '').toString();
                                    return ListTile(
                                      leading: Icon(
                                        Icons.badge,
                                        color: _roleColor(role),
                                      ),
                                      title: Text(_roleLabel(role)),
                                      subtitle: Text(
                                        branch.isNotEmpty
                                            ? 'Cabang: $branch'
                                            : 'Cabang: -',
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _UserGroup {
  final Map<String, dynamic> user;
  final List<Map<String, dynamic>> assignments;
  const _UserGroup({required this.user, required this.assignments});
}

