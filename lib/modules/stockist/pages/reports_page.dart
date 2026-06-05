import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/core/state/user_state.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/app_date_picker.dart';
import 'package:vanessa3/utils/stockist_input_report_print.dart';

/// Mode laporan input stok.
enum StockInputReportMode {
  /// Stockist: hanya item yang Anda input di cabang aktif.
  personal,
  /// Admin warehouse: semua input stok pada cabang warehouse aktif.
  activeBranch,
}

/// Laporan input stok per **cabang aktif** (`user.branch`).
/// - [StockInputReportMode.personal]: `mine=1` (hanya Anda).
/// - [StockInputReportMode.activeBranch]: semua penginput di cabang aktif.
class StockistReportsPage extends ConsumerStatefulWidget {
  const StockistReportsPage({
    super.key,
    this.mode = StockInputReportMode.personal,
  });

  final StockInputReportMode mode;

  @override
  ConsumerState<StockistReportsPage> createState() =>
      _StockistReportsPageState();
}

class _StockistReportsPageState extends ConsumerState<StockistReportsPage> {
  bool _isLoading = true;
  String? _error;
  bool _missingUserId = false;
  bool _missingBranch = false;

  List<Map<String, dynamic>> _items = const [];

  late DateTime _fromDate;
  late DateTime _toDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, now.day);
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _pickDateRange() async {
    final picked = await showAppDateRangePicker(
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
    });
    await _load();
  }

  String _isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _missingBranch = false;
    });

    final user = ref.read(userStateProvider);
    final uid = user.userId;
    if (uid == null) {
      setState(() {
        _missingUserId = true;
        _items = const [];
        _isLoading = false;
      });
      return;
    }
    _missingUserId = false;

    final activeBranchId = user.branch.trim();
    if (activeBranchId.isEmpty) {
      setState(() {
        _missingBranch = true;
        _items = const [];
        _isLoading = false;
      });
      return;
    }

    try {
      final queryParams = <String, String>{
        'branch_id': activeBranchId,
        'start_date': _isoDate(_fromDate),
        'end_date': _isoDate(_toDate),
        'limit': '500',
      };
      if (widget.mode == StockInputReportMode.personal) {
        queryParams['mine'] = '1';
      }
      final itemsRes = await ApiClient.get('/items', query: queryParams);

      if (itemsRes.statusCode != 200) {
        String msg = 'Gagal memuat data (${itemsRes.statusCode})';
        try {
          final errBody = jsonDecode(itemsRes.body);
          if (errBody is Map && errBody['error'] != null) {
            msg = errBody['error'].toString();
          }
        } catch (_) {}
        setState(() {
          _error = msg;
          _isLoading = false;
        });
        return;
      }

      final itemsJson = jsonDecode(itemsRes.body);
      final items = (itemsJson is List ? itemsJson : const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      setState(() {
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

  int _asInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

  String _activeBranchLabel(UserState user) {
    final id = user.branch.trim();
    if (id.isEmpty) return '-';
    for (final b in user.branches) {
      if (b['branch_id']?.toString() == id) {
        return (b['name'] ?? 'Cabang $id').toString();
      }
    }
    return 'Cabang $id';
  }

  String _periodSubtitle() {
    final fromD = DateTime(_fromDate.year, _fromDate.month, _fromDate.day);
    final toD = DateTime(_toDate.year, _toDate.month, _toDate.day);
    final df = DateFormat('dd MMM yyyy', 'id_ID');
    if (fromD == toD) {
      return 'Hari ini, ${df.format(fromD)}';
    }
    return '${df.format(fromD)} – ${df.format(toD)}';
  }

  Future<void> _printReport() async {
    final user = ref.read(userStateProvider);
    if (user.userId == null || user.branch.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak dapat mencetak — sesi atau cabang tidak lengkap.')),
      );
      return;
    }

    final itemsInPeriod = _items;
    final sku = itemsInPeriod.length;
    final qty = itemsInPeriod.fold<int>(0, (s, i) => s + _asInt(i['quantity']));

    final inputByLabel = widget.mode == StockInputReportMode.personal
        ? user.username
        : 'Semua pengguna (cabang aktif)';

    await printStockistInputReportPdf(
      context,
      fromDate: _fromDate,
      toDate: _toDate,
      branchLabel: _activeBranchLabel(user),
      branchIdForLogo: user.branch.trim(),
      username: inputByLabel,
      skuCount: sku,
      totalQty: qty,
      items: itemsInPeriod,
      showCreatedByColumn: widget.mode == StockInputReportMode.activeBranch,
    );
  }

  String _filterSubtitle(UserState user) {
    final branchLine = 'Cabang aktif: ${_activeBranchLabel(user)}';
    if (widget.mode == StockInputReportMode.personal) {
      return [
        branchLine,
        if (user.username.isNotEmpty) 'Penginput: ${user.username}',
        'Hanya item yang Anda input pada cabang ini',
      ].join('\n');
    }
    return [
      branchLine,
      'Semua item yang di-input pada cabang warehouse aktif',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userStateProvider);
    ref.listen(userStateProvider, (UserState? prev, UserState next) {
      if (prev?.branch != next.branch || prev?.userId != next.userId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load();
        });
      }
    });

    final dtFmt = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');

    final itemsInPeriod = _items;

    final skuCount = itemsInPeriod.length;
    final totalQty =
        itemsInPeriod.fold<int>(0, (s, i) => s + _asInt(i['quantity']));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Input Stok'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Cetak laporan',
            onPressed: _isLoading ||
                    _error != null ||
                    _missingUserId ||
                    _missingBranch
                ? null
                : _printReport,
          ),
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Pilih periode',
            onPressed: _pickDateRange,
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
                    if (_missingUserId) ...[
                      Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Theme.of(context).colorScheme.onErrorContainer,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Sesi tidak menyimpan ID pengguna. Silakan logout dan login ulang.',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_missingBranch) ...[
                      Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.store_mall_directory_outlined,
                                color: Theme.of(context).colorScheme.onErrorContainer,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Belum ada cabang aktif. Pilih cabang di header atau ganti peran/cabang, lalu buka lagi laporan ini.',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _InfoRangeCard(
                      title: 'Periode',
                      subtitle: _periodSubtitle(),
                    ),
                    const SizedBox(height: 8),
                    _InfoRangeCard(
                      title: 'Filter',
                      subtitle: _filterSubtitle(user),
                    ),
                    const SizedBox(height: 12),
                    _SummaryCard(
                      title: 'Laporan Input Stok',
                      items: [
                        _SummaryItem(label: 'Jumlah SKU', value: '$skuCount'),
                        _SummaryItem(label: 'Total qty', value: '$totalQty'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _MyItemsTable(
                      title: 'Daftar item',
                      items: itemsInPeriod,
                      dateFmt: dtFmt,
                      showCreatedBy: widget.mode == StockInputReportMode.activeBranch,
                    ),
                  ],
                ),
    );
  }
}

class _MyItemsTable extends StatelessWidget {
  const _MyItemsTable({
    required this.title,
    required this.items,
    required this.dateFmt,
    this.showCreatedBy = false,
  });

  final String title;
  final List<Map<String, dynamic>> items;
  final DateFormat dateFmt;
  final bool showCreatedBy;

  String _code(Map<String, dynamic> i) =>
      (i['kode_produk'] ?? i['item_code'] ?? '-').toString();

  String _fmt(dynamic v) {
    try {
      return dateFmt.format(DateTime.parse(v.toString()).toLocal());
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
            if (items.isEmpty)
              Text(
                showCreatedBy
                    ? 'Tidak ada input stok pada cabang aktif untuk periode ini.'
                    : 'Tidak ada item yang tercatat dibuat oleh Anda pada periode ini.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  horizontalMargin: 10,
                  columnSpacing: 18,
                  headingRowHeight: 34,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 52,
                  dividerThickness: 0.5,
                  dataTextStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.15,
                      ),
                  headingTextStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                  columns: [
                    const DataColumn(label: Text('Kode')),
                    const DataColumn(label: Text('Nama')),
                    const DataColumn(label: Text('Qty')),
                    const DataColumn(label: Text('Status')),
                    if (showCreatedBy) const DataColumn(label: Text('Penginput')),
                    const DataColumn(label: Text('Dibuat')),
                  ],
                  rows: items.map((i) {
                    final qty = int.tryParse(
                          (i['quantity'] ?? i['qty'] ?? '0').toString(),
                        ) ??
                        0;
                    final createdBy = (i['item_created_by_name'] ??
                            i['created_by_name'] ??
                            i['username'] ??
                            '-')
                        .toString();
                    return DataRow(
                      cells: [
                        DataCell(Text(_code(i))),
                        DataCell(
                          Text(
                            (i['name'] ?? '-').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DataCell(Text('$qty')),
                        DataCell(Text((i['status'] ?? '-').toString())),
                        if (showCreatedBy) DataCell(Text(createdBy)),
                        DataCell(Text(_fmt(i['created_at']))),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRangeCard extends StatelessWidget {
  const _InfoRangeCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

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
  const _SummaryCard({required this.title, required this.items});

  final String title;
  final List<_SummaryItem> items;

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
  const _SummaryItem({required this.label, required this.value});
  final String label;
  final String value;
}
