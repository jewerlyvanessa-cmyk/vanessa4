import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

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
      case 'admin_warehouse':
        return Colors.brown;
      case 'stockist':
        return Colors.blueGrey;
      case 'tukang':
        return Colors.red;
      case 'manajer':
        return Colors.teal;
      case 'owner':
        return Colors.amber;
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
      case 'admin_warehouse':
        return 'Admin Warehouse';
      case 'stockist':
        return 'Stockist';
      case 'tukang':
        return 'Tukang';
      case 'manajer':
        return 'Manajer';
      case 'owner':
        return 'Owner';
      case 'superadmin':
        return 'Super Admin';
      default:
        return (role ?? '').toString().isEmpty ? 'Unknown' : role!;
    }
  }

  Widget _summaryCard(
    BuildContext context,
    int count,
    IconData icon,
    Color color,
  ) {
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const Spacer(),
            Text(
              count.toString(),
              style: tt.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
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
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 600;
                    final pad = narrow ? 12.0 : 16.0;
                    const desktopTableW = 880.0;
                    final panelW = constraints.maxWidth;
                    final BoxConstraints tableBoxConstraints;
                    if (narrow) {
                      tableBoxConstraints =
                          BoxConstraints.tightFor(width: panelW - pad * 2);
                    } else if (panelW - pad * 2 >= desktopTableW) {
                      tableBoxConstraints =
                          BoxConstraints.tightFor(width: desktopTableW);
                    } else {
                      tableBoxConstraints =
                          const BoxConstraints(minWidth: desktopTableW);
                    }
                    final cs = Theme.of(context).colorScheme;

void showDetailSheet(_UserGroup group) {
                      final username =
                          (group.user['username'] ?? 'N/A').toString();
                      showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        isScrollControlled: true,
                        builder: (ctx) {
                          return SafeArea(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              child: ListView(
                                shrinkWrap: true,
                                children: [
                                  Text(
                                    username,
                                    style: Theme.of(ctx)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Penugasan per cabang',
                                    style: Theme.of(ctx).textTheme.titleSmall,
                                  ),
                                  const Divider(height: 24),
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
                            ),
                          );
                        },
                      );
                    }

                    final rows = <DataRow>[];
                    for (var i = 0; i < groups.length; i++) {
                      final group = groups[i];
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
                      final statusLabel = status == 'active'
                          ? 'Aktif'
                          : (status.isEmpty ? 'N/A' : 'Tidak aktif');
                      final roleText = roles.isEmpty
                          ? 'N/A'
                          : roles.map(_roleLabel).join(', ');

                      final detailCell = DataCell(
                        IconButton(
                          tooltip: 'Detail penugasan',
                          icon: const Icon(Icons.info_outline),
                          onPressed: () => showDetailSheet(group),
                        ),
                      );

                      rows.add(
                        DataRow(
                          color: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.hovered)) {
                              return cs.primary.withValues(alpha: 0.06);
                            }
                            return i.isOdd
                                ? cs.surfaceContainerHighest
                                    .withValues(alpha: 0.45)
                                : null;
                          }),
                          cells: narrow
                              ? [
                                  DataCell(
                                    Text(
                                      username,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      statusLabel,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  detailCell,
                                ]
                              : [
                                  DataCell(
                                    Text(
                                      username,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(statusLabel)),
                                  DataCell(
                                    Text(
                                      roleText,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  detailCell,
                                ],
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(pad, pad, pad, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              narrow
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        IntrinsicHeight(
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Expanded(
                                                child: _summaryCard(
                                                  context,
                                                  _countUniqueUsers(allRows),
                                                  Icons.people,
                                                  Colors.blue,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: _summaryCard(
                                                  context,
                                                  _countUniqueUsersByStatus(
                                                    allRows,
                                                    'active',
                                                  ),
                                                  Icons.check_circle,
                                                  Colors.green,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        IntrinsicHeight(
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Expanded(
                                                child: _summaryCard(
                                                  context,
                                                  _countUniqueUsersByStatus(
                                                    allRows,
                                                    'inactive',
                                                  ),
                                                  Icons.cancel,
                                                  Colors.red,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: _summaryCard(
                                                  context,
                                                  allRows
                                                      .map(
                                                        (r) =>
                                                            (r['role'] ?? '')
                                                                .toString(),
                                                      )
                                                      .where(
                                                        (r) =>
                                                            r.trim().isNotEmpty,
                                                      )
                                                      .toSet()
                                                      .length,
                                                  Icons.badge,
                                                  Colors.purple,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    )
                                  : IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            child: _summaryCard(
                                              context,
                                              _countUniqueUsers(allRows),
                                              Icons.people,
                                              Colors.blue,
                                            ),
                                          ),
                                          SizedBox(width: narrow ? 8 : 16),
                                          Expanded(
                                            child: _summaryCard(
                                              context,
                                              _countUniqueUsersByStatus(
                                                allRows,
                                                'active',
                                              ),
                                              Icons.check_circle,
                                              Colors.green,
                                            ),
                                          ),
                                          SizedBox(width: narrow ? 8 : 16),
                                          Expanded(
                                            child: _summaryCard(
                                              context,
                                              _countUniqueUsersByStatus(
                                                allRows,
                                                'inactive',
                                              ),
                                              Icons.cancel,
                                              Colors.red,
                                            ),
                                          ),
                                          SizedBox(width: narrow ? 8 : 16),
                                          Expanded(
                                            child: _summaryCard(
                                              context,
                                              allRows
                                                  .map(
                                                    (r) => (r['role'] ?? '')
                                                        .toString(),
                                                  )
                                                  .where(
                                                    (r) => r.trim().isNotEmpty,
                                                  )
                                                  .toSet()
                                                  .length,
                                              Icons.badge,
                                              Colors.purple,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                              const SizedBox(height: 12),
                              Text(
                                'Daftar user (${_countUniqueUsers(allRows)})',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(pad, 0, pad, 8),
                            child: groups.isEmpty
                                ? const Center(
                                    child: Text('Belum ada data user'),
                                  )
                                : Material(
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
                                              constraints: tableBoxConstraints,
                                              child: DataTable(
                                                headingRowColor:
                                                    WidgetStateProperty.all(
                                                  cs.surfaceContainerHigh,
                                                ),
dataRowMinHeight:
                                                    narrow ? 40 : 44,
                                                dataRowMaxHeight:
                                                    narrow ? 52 : 60,
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
                                                            'Username',
                                                          ),
                                                        ),
                                                        DataColumn(
                                                          label: dataTableColumnLabel(
                                                            'Status',
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
                                                          label:
                                                              dataTableColumnLabel('Status'),
                                                        ),
                                                        DataColumn(
                                                          label: dataTableColumnLabel('Role'),
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
                                  ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }
}

class _UserGroup {
  final Map<String, dynamic> user;
  final List<Map<String, dynamic>> assignments;
  const _UserGroup({required this.user, required this.assignments});
}

