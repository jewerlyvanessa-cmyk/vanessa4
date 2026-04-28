import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/utils/network_config.dart';

class StockistReportsPage extends ConsumerStatefulWidget {
  const StockistReportsPage({super.key});

  @override
  ConsumerState<StockistReportsPage> createState() =>
      _StockistReportsPageState();
}

class _StockistReportsPageState extends ConsumerState<StockistReportsPage> {
  bool _isLoading = true;
  String? _error;
  bool _isLoadingBranches = false;

  List<Map<String, dynamic>> _transfers = const [];
  List<Map<String, dynamic>> _items = const [];
  List<Map<String, dynamic>> _availableBranches = const [];

  // Filters
  late DateTime _fromDate;
  late DateTime _toDate;
  String? _selectedBranchId;
  bool _dirtyFilters = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final from = now.subtract(const Duration(days: 30));
    _fromDate = DateTime(from.year, from.month, from.day);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensureBranchesLoaded();
      await _load();
    });
  }

  Future<void> _ensureBranchesLoaded() async {
    if (_availableBranches.isNotEmpty) return;

    final user = ref.read(userStateProvider);
    if (user.branches.isNotEmpty) {
      setState(() {
        _availableBranches = user.branches;
        _selectedBranchId ??= user.branch.isNotEmpty
            ? user.branch
            : (user.branches[0]['branch_id']?.toString() ?? '');
      });
      return;
    }

    setState(() => _isLoadingBranches = true);
    try {
      final baseUrl = NetworkConfig.baseUrl;
      final uri = Uri.parse('$baseUrl/branches');
      final res = await http.get(uri, headers: NetworkConfig.defaultHeaders);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final branches = (json is List ? json : const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        setState(() {
          _availableBranches = branches;
          _selectedBranchId ??= user.branch.isNotEmpty
              ? user.branch
              : (branches.isNotEmpty
                  ? (branches[0]['branch_id']?.toString() ?? '')
                  : '');
        });
      }
    } catch (_) {
      // ignore; fallback UI will show empty list
    } finally {
      if (mounted) setState(() => _isLoadingBranches = false);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
    );

    if (picked == null) return;
    setState(() {
      _fromDate =
          DateTime(picked.start.year, picked.start.month, picked.start.day);
      _toDate = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
        23,
        59,
        59,
      );
      _dirtyFilters = true;
    });
  }

  Future<void> _applyFilters() async {
    setState(() => _dirtyFilters = false);
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = ref.read(userStateProvider);
      final selectedBranchId = (_selectedBranchId?.isNotEmpty == true)
          ? _selectedBranchId!
          : (user.branch.isNotEmpty
              ? user.branch
              : (_availableBranches.isNotEmpty
                  ? (_availableBranches[0]['branch_id']?.toString() ?? '1')
                  : (user.branches.isNotEmpty
                      ? (user.branches[0]['branch_id']?.toString() ?? '1')
                      : '1')));

      // Ensure dropdown has a value after first load
      _selectedBranchId ??= selectedBranchId;
      final baseUrl = NetworkConfig.baseUrl;

      final transfersUri =
          Uri.parse('$baseUrl/transfers?branch_id=$selectedBranchId');
      final itemsUri =
          Uri.parse('$baseUrl/items?branch_id=$selectedBranchId&limit=200');

      final transfersFuture =
          http.get(transfersUri, headers: NetworkConfig.defaultHeaders);
      final itemsFuture = http.get(itemsUri, headers: NetworkConfig.defaultHeaders);

      final transfersRes = await transfersFuture;
      final itemsRes = await itemsFuture;

      if (transfersRes.statusCode != 200 || itemsRes.statusCode != 200) {
        setState(() {
          _error =
              'Gagal memuat laporan (transfers: ${transfersRes.statusCode}, items: ${itemsRes.statusCode})';
          _isLoading = false;
        });
        return;
      }

      final transfersJson = jsonDecode(transfersRes.body);
      final itemsJson = jsonDecode(itemsRes.body);

      final transfers = (transfersJson is List ? transfersJson : const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final items = (itemsJson is List ? itemsJson : const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      setState(() {
        _transfers = transfers;
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  int _asInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userStateProvider);
    final branches = _availableBranches.isNotEmpty ? _availableBranches : user.branches;
    final selectedBranchId = (_selectedBranchId?.isNotEmpty == true)
        ? _selectedBranchId!
        : (user.branch.isNotEmpty ? user.branch : '');

    final dateFmt = DateFormat('dd MMM yyyy', 'id_ID');

    final filteredTransfers = _transfers.where((t) {
      final dt = _parseDate(t['created_at']);
      if (dt == null) return true;
      return !dt.isBefore(_fromDate) && !dt.isAfter(_toDate);
    }).toList();

    final completedTransfers = filteredTransfers
        .where((t) => (t['status'] ?? '').toString() == 'completed')
        .toList();

    final outgoingQty = completedTransfers.fold<int>(0, (sum, t) {
      final from = t['from_branch_id']?.toString();
      final qty = _asInt(t['quantity']);
      return sum + (from == selectedBranchId ? qty : 0);
    });

    final totalItemRows = _items.length;
    // total qty (all) not shown currently; keep only the pieces we show

    final itemsAvailable =
        _items.where((i) => _asInt(i['quantity']) >= 1).toList();
    final itemsCritical = _items.where((i) => _asInt(i['quantity']) < 1).toList();
    final availableRows = itemsAvailable.length;
    final availableQty = itemsAvailable.fold<int>(
      0,
      (sum, i) => sum + _asInt(i['quantity']),
    );
    final criticalRows = itemsCritical.length;

    // Outgoing transfers grouped by destination branch
    final outgoingTransfers = completedTransfers.where((t) {
      final from = t['from_branch_id']?.toString();
      return from == selectedBranchId;
    }).toList();
    final outgoingCount = outgoingTransfers.length;
    final outgoingByDest = <String, int>{};
    for (final t in outgoingTransfers) {
      final to = (t['to_branch_name'] ?? t['to_branch_id'] ?? '-').toString();
      final qty = _asInt(t['quantity']);
      outgoingByDest[to] = (outgoingByDest[to] ?? 0) + qty;
    }
    final topOutgoingDest = outgoingByDest.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final selectedBranchName = branches
        .cast<Map<String, dynamic>>()
        .where((b) => b['branch_id']?.toString() == selectedBranchId)
        .map((b) => (b['name'] ?? 'Cabang $selectedBranchId').toString())
        .cast<String?>()
        .firstWhere((x) => x != null, orElse: () => null) ??
        (selectedBranchId.isEmpty ? '-' : 'Cabang $selectedBranchId');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Stockist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Pilih periode',
            onPressed: _pickDateRange,
          ),
          if (_dirtyFilters)
            TextButton(
              onPressed: _applyFilters,
              child: const Text(
                'Terapkan',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 44,
                        ),
                        const SizedBox(height: 12),
                        Text('Error: $_error', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _InfoRangeCard(
                      title: 'Periode',
                      subtitle:
                          '${dateFmt.format(_fromDate)} - ${dateFmt.format(_toDate)}',
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Branch',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue:
                                  selectedBranchId.isEmpty ? null : selectedBranchId,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              hint: const Text('Pilih branch'),
                              items: branches
                                  .map(
                                    (b) => DropdownMenuItem<String>(
                                      value: b['branch_id']?.toString() ?? '',
                                      child: Text(
                                        (b['name'] ??
                                                'Cabang ${b['branch_id']?.toString() ?? ''}')
                                            .toString(),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                setState(() => _selectedBranchId = v);
                                _dirtyFilters = true;
                              },
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Terpilih: $selectedBranchName (ID: $selectedBranchId)',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (_isLoadingBranches)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  children: [
                                    const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Memuat daftar branch...',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SummaryCard(
                      title: 'Stock tersedia',
                      items: [
                        _SummaryItem(label: 'Branch', value: selectedBranchName),
                        _SummaryItem(label: 'Item tersedia', value: '$availableRows'),
                        _SummaryItem(label: 'Total qty', value: '$availableQty'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SummaryCard(
                      title: 'Stock kritis (qty < 1)',
                      items: [
                        _SummaryItem(label: 'Branch', value: selectedBranchName),
                        _SummaryItem(label: 'Item kritis', value: '$criticalRows'),
                        _SummaryItem(label: 'Total item', value: '$totalItemRows'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SummaryCard(
                      title: 'Kirim ke branch (Completed)',
                      items: [
                        _SummaryItem(label: 'Jumlah transfer', value: '$outgoingCount'),
                        _SummaryItem(label: 'Total qty keluar', value: '$outgoingQty'),
                        _SummaryItem(
                          label: 'Tujuan teratas',
                          value: topOutgoingDest.isEmpty
                              ? '-'
                              : '${topOutgoingDest.first.key} (${topOutgoingDest.first.value})',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _TransfersPreview(
                      title: 'Kirim ke branch terbaru',
                      transfers: outgoingTransfers.take(10).toList(),
                    ),
                  ],
                ),
    );
  }
}

class _InfoRangeCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _InfoRangeCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final List<_SummaryItem> items;

  const _SummaryCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: items
                  .map(
                    (i) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            i.label,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            i.value,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem {
  final String label;
  final String value;
  const _SummaryItem({required this.label, required this.value});
}

class _TransfersPreview extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> transfers;

  const _TransfersPreview({required this.title, required this.transfers});

  String _fmtDate(dynamic v) {
    try {
      return DateFormat('dd/MM HH:mm', 'id_ID')
          .format(DateTime.parse(v.toString()).toLocal());
    } catch (_) {
      return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            if (transfers.isEmpty)
              const Text('Tidak ada data transfer pada periode ini')
            else
              ...transfers.map((t) {
                final item = (t['item_name'] ?? '-').toString();
                final qty = (t['quantity'] ?? 0).toString();
                final status = (t['status'] ?? '-').toString();
                final from = (t['from_branch_name'] ??
                        t['from_branch_id'] ??
                        '-')
                    .toString();
                final to =
                    (t['to_branch_name'] ?? t['to_branch_id'] ?? '-').toString();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    child: Text(qty, style: const TextStyle(fontSize: 12)),
                  ),
                  title:
                      Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('$from → $to • ${_fmtDate(t['created_at'])}'),
                  trailing: Text(
                    status,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color:
                          status == 'completed' ? Colors.green : Colors.orange,
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

