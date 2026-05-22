import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/branch_logo_pdf.dart';
import 'package:vanessa3/utils/app_date_picker.dart';
import 'package:vanessa3/utils/network_config.dart';

int _stockMutationQty(Map<String, dynamic> m) {
  return int.tryParse(m['quantity']?.toString() ?? '') ?? 0;
}

String _stockMutationTypeLabel(Map<String, dynamic> m) {
  final type = (m['type'] ?? '').toString();
  final ref = (m['reference_type'] ?? '').toString();
  final qty = _stockMutationQty(m);
  final orderType =
      (m['order_type'] ?? '').toString().trim().toLowerCase();

  if (type == 'transfer') {
    return qty >= 0 ? 'Transfer masuk' : 'Transfer keluar';
  }
  if (type == 'in') {
    if (ref == 'item_create') return 'Stok baru';
    if (ref == 'restock') return 'Restok';
    if (ref == 'order' && orderType == 'buyback') return 'Buyback';
    return 'Stok masuk';
  }
  if (type == 'out') {
    if (ref == 'order') return 'Penjualan';
    return 'Stok keluar';
  }
  if (type == 'adjustment') return 'Koreksi';
  return 'Lainnya';
}

Color _stockMutationTypeColor(Map<String, dynamic> m) {
  final type = (m['type'] ?? '').toString();
  final qty = _stockMutationQty(m);
  if (type == 'transfer') {
    return qty >= 0 ? Colors.blue : Colors.orange;
  }
  switch (type) {
    case 'in':
      return Colors.green;
    case 'out':
      return Colors.red;
    case 'adjustment':
      return Colors.blueGrey;
    default:
      return Colors.blue;
  }
}

Icon _stockMutationIcon(Map<String, dynamic> m) {
  final color = _stockMutationTypeColor(m);
  final qty = _stockMutationQty(m);
  final type = (m['type'] ?? '').toString();
  if (type == 'transfer') {
    return Icon(
      qty >= 0 ? Icons.arrow_downward : Icons.arrow_upward,
      color: color,
      size: 20,
    );
  }
  switch (type) {
    case 'in':
      return Icon(Icons.arrow_downward, color: color, size: 20);
    case 'out':
      return Icon(Icons.arrow_upward, color: color, size: 20);
    default:
      return Icon(Icons.swap_horiz, color: color, size: 20);
  }
}

String _humanizeBranchIdsInNotes(String note, Map<String, dynamic> m) {
  var s = note;
  final fromId = m['transfer_from_branch_id']?.toString().trim();
  final toId = m['transfer_to_branch_id']?.toString().trim();
  final fromName =
      (m['transfer_from_branch_name'] ?? '').toString().trim();
  final toName = (m['transfer_to_branch_name'] ?? '').toString().trim();
  if (fromId != null && fromId.isNotEmpty && fromName.isNotEmpty) {
    s = s.replaceAll(
      RegExp('branch\\s*$fromId', caseSensitive: false),
      fromName,
    );
  }
  if (toId != null && toId.isNotEmpty && toName.isNotEmpty) {
    s = s.replaceAll(
      RegExp('branch\\s*$toId', caseSensitive: false),
      toName,
    );
  }
  return s;
}

String _stockMutationDescription(Map<String, dynamic> m) {
  final ref = (m['reference_type'] ?? '').toString();
  final qty = _stockMutationQty(m);
  final from =
      (m['transfer_from_branch_name'] ?? '').toString().trim();
  final to = (m['transfer_to_branch_name'] ?? '').toString().trim();
  final orderNo = (m['order_number'] ?? '').toString().trim();
  final orderType =
      (m['order_type'] ?? '').toString().trim().toLowerCase();

  if (ref == 'transfer') {
    if (qty >= 0) {
      if (from.isNotEmpty) return 'Diterima dari $from';
      return 'Barang diterima dari cabang lain';
    }
    if (to.isNotEmpty) return 'Dikirim ke $to';
    return 'Barang dikirim ke cabang lain';
  }
  if (ref == 'item_create') return 'Input stok baru di etalase';
  if (ref == 'restock') return 'Penambahan / restok manual';
  if (ref == 'order') {
    if (orderType == 'buyback') {
      if (orderNo.isNotEmpty) return 'Buyback lunas · $orderNo';
      return 'Buyback lunas';
    }
    if (orderNo.isNotEmpty) return 'Penjualan · $orderNo';
    return 'Pengurangan stok dari order';
  }

  final note = (m['notes'] ?? '').toString().trim();
  if (note.isNotEmpty) return _humanizeBranchIdsInNotes(note, m);
  return '—';
}

String _stockMutationFilterLabel(String filterKey) {
  switch (filterKey) {
    case 'all':
      return 'Semua';
    case 'in':
      return 'Penambahan stok';
    case 'out':
      return 'Pengurangan stok';
    case 'transfer_in':
      return 'Transfer masuk';
    case 'transfer_out':
      return 'Transfer keluar';
    default:
      return 'Semua';
  }
}

bool _stockMutationMatchesFilter(Map<String, dynamic> m, String filterKey) {
  final type = (m['type'] ?? '').toString();
  final qty = _stockMutationQty(m);
  switch (filterKey) {
    case 'all':
      return true;
    case 'in':
    case 'out':
      return type == filterKey;
    case 'transfer_in':
      return type == 'transfer' && qty >= 0;
    case 'transfer_out':
      return type == 'transfer' && qty < 0;
    default:
      return type == filterKey;
  }
}

class StockMutationPage extends ConsumerStatefulWidget {
  const StockMutationPage({super.key});

  @override
  ConsumerState<StockMutationPage> createState() => _StockMutationPageState();
}

class _StockMutationPageState extends ConsumerState<StockMutationPage> {
  List<dynamic> _mutations = [];
  bool _isLoading = true;
  String _error = '';
  String _selectedType = 'all'; // all, in, out, transfer
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = DateTime(now.year, now.month, now.day);
    _loadMutations();
  }

  Future<void> _loadMutations() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;
      final query = <String, String>{
        'branch_id': userState.branch.toString(),
        'limit': '200',
      };
      if (_startDate != null) {
        query['start_date'] = _isoDate(_startDate!);
      }
      if (_endDate != null) {
        query['end_date'] = _isoDate(_endDate!);
      }

      final response = await http.get(
        Uri.parse('$baseUrl/stock-mutations').replace(queryParameters: query),
        headers: NetworkConfig.defaultHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _mutations = data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Gagal memuat data mutasi stok';
          _isLoading = false;
        });
      }
    } catch (error) {
      setState(() {
        _error = 'Error: $error';
        _isLoading = false;
      });
    }
  }

  List<dynamic> get _filteredMutations {
    if (_selectedType == 'all') return _mutations;
    return _mutations
        .where(
          (m) => _stockMutationMatchesFilter(
            Map<String, dynamic>.from(m as Map),
            _selectedType,
          ),
        )
        .toList();
  }

  int _countByFilter(String filterKey) {
    return _mutations
        .where(
          (m) => _stockMutationMatchesFilter(
            Map<String, dynamic>.from(m as Map),
            filterKey,
          ),
        )
        .length;
  }

  String _isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  String _dateRangeLabel() {
    if (_startDate == null && _endDate == null) return 'Semua tanggal';
    final df = DateFormat('dd/MM/yyyy');
    if (_startDate != null &&
        _endDate != null &&
        _isoDate(_startDate!) == _isoDate(_endDate!)) {
      return df.format(_startDate!);
    }
    final a = _startDate != null ? df.format(_startDate!) : '-';
    final b = _endDate != null ? df.format(_endDate!) : '-';
    return '$a - $b';
  }

  Future<void> _pickSingleDayFilter() async {
    final now = DateTime.now();
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() {
      _startDate = DateTime(picked.year, picked.month, picked.day);
      _endDate = DateTime(picked.year, picked.month, picked.day);
    });
    await _loadMutations();
  }

  Future<void> _pickDateRangeFilter() async {
    final now = DateTime.now();
    final initialRange = (_startDate != null && _endDate != null)
        ? DateTimeRange(start: _startDate!, end: _endDate!)
        : DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now);
    final picked = await showAppDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 2),
      initialDateRange: initialRange,
    );
    if (picked == null) return;
    setState(() {
      _startDate = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    await _loadMutations();
  }

  Future<void> _printMutationReport() async {
    final rows = _filteredMutations;
    if (rows.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada data untuk dicetak')),
      );
      return;
    }

    final bid = ref.read(userStateProvider).branch.trim();
    final logoBytes = await loadBranchLogoRasterBytesForPdf(bid);

    final doc = pw.Document();
    final df = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');
    final periodLabel = _dateRangeLabel();
    final sorted =
        List<Map<String, dynamic>>.from(
          rows.map((e) => Map<String, dynamic>.from(e as Map)),
        )..sort((a, b) {
          final ta =
              DateTime.tryParse(a['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final tb =
              DateTime.tryParse(b['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return ta.compareTo(tb);
        });

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: pdfMultiPageHeaderLaporanCabang(
          title: 'LAPORAN MUTASI STOK',
          leftLogoBytes: logoBytes,
          subtitles: [
            PdfLaporanHeaderSubtitleLine('Periode: $periodLabel'),
            PdfLaporanHeaderSubtitleLine(
              'Filter: ${_stockMutationFilterLabel(_selectedType)}',
            ),
          ],
        ),
        build: (ctx) => [
          pw.TableHelper.fromTextArray(
            headers: const ['No', 'Waktu', 'Item', 'Jenis', 'Qty', 'Keterangan'],
            data: [
              for (var i = 0; i < sorted.length; i++)
                [
                  '${i + 1}',
                  () {
                    final d = DateTime.tryParse(
                      sorted[i]['created_at']?.toString() ?? '',
                    );
                    return d == null ? '-' : df.format(d.toLocal());
                  }(),
                  (sorted[i]['item_name'] ?? '-').toString(),
                  _stockMutationTypeLabel(sorted[i]),
                  (sorted[i]['quantity'] ?? '-').toString(),
                  _stockMutationDescription(sorted[i]),
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      name:
          'mutasi_stok_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
      onLayout: (_) async => doc.save(),
    );
  }

  String _formatMutationDateTime(dynamic raw) {
    if (raw == null) return '-';
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return raw.toString();
    final d = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }

  Widget _tableHeadCell(
    String label, {
    TextAlign align = TextAlign.left,
    bool compact = false,
  }) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 9 : 10,
        ),
        child: Text(
          label,
          textAlign: align,
          style: TextStyle(
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _tableBodyCell({
    required Widget child,
    required VoidCallback onTap,
    bool compact = false,
    Alignment align = Alignment.centerLeft,
  }) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: InkWell(
        onTap: onTap,
        child: Container(
          alignment: align,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 9 : 10,
          ),
          child: child,
        ),
      ),
    );
  }

  void _showMutationHistoryDetail(Map<String, dynamic> mutation) {
    final typeLabel = _stockMutationTypeLabel(mutation);
    final typeColor = _stockMutationTypeColor(mutation);
    final description = _stockMutationDescription(mutation);
    final qty = (mutation['quantity'] ?? '').toString();
    final createdAt = _formatMutationDateTime(mutation['created_at']);
    final itemName = (mutation['item_name'] ?? '-').toString();
    final branchName = (mutation['branch_name'] ?? '-').toString();
    final systemNote = (mutation['notes'] ?? '').toString().trim();
    final prevStock = (mutation['previous_stock'] ?? '-').toString();
    final currStock = (mutation['current_stock'] ?? '-').toString();
    final createdBy =
        (mutation['created_by_name'] ?? mutation['created_by'] ?? '-')
            .toString();
    final orderNo = (mutation['order_number'] ?? '').toString().trim();
    final customerName = (mutation['customer_name'] ?? '').toString().trim();
    final transferFlow = [
      mutation['transfer_from_branch_name']?.toString(),
      mutation['transfer_to_branch_name']?.toString(),
    ].whereType<String>().where((x) => x.trim().isNotEmpty).join(' → ');
    final humanizedSystemNote = systemNote.isNotEmpty
        ? _humanizeBranchIdsInNotes(systemNote, mutation)
        : '';
    final showSystemNote = humanizedSystemNote.isNotEmpty &&
        humanizedSystemNote != description;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Detail Riwayat Mutasi',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _detailRow('Item', itemName),
                  _detailRow('Jenis', typeLabel),
                  _detailRow('Keterangan', description),
                  _detailRow('Jumlah', '$qty pcs'),
                  _detailRow('Cabang', branchName),
                  _detailRow('Waktu', createdAt),
                  _detailRow('Stok Sebelum', prevStock),
                  _detailRow('Stok Sesudah', currStock),
                  _detailRow('Dibuat Oleh', createdBy),
                  if (orderNo.isNotEmpty) _detailRow('No. Order', orderNo),
                  if (customerName.isNotEmpty)
                    _detailRow('Pelanggan', customerName),
                  if (transferFlow.isNotEmpty)
                    _detailRow('Alur Transfer', transferFlow),
                  if (showSystemNote)
                    _detailRow('Catatan sistem', humanizedSystemNote),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: cs.surfaceContainerLow,
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      typeLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: typeColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final narrowScreen = screenW < 600;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mutasi Stok'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => setState(() => _selectedType = value),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'all', child: Text('Semua')),
              PopupMenuItem(value: 'in', child: Text('Penambahan stok')),
              PopupMenuItem(value: 'out', child: Text('Pengurangan stok')),
              PopupMenuItem(value: 'transfer_in', child: Text('Transfer masuk')),
              PopupMenuItem(
                value: 'transfer_out',
                child: Text('Transfer keluar'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(_stockMutationFilterLabel(_selectedType)),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Filter tanggal',
            onSelected: (value) async {
              if (value == 'single_day') {
                await _pickSingleDayFilter();
              } else if (value == 'date_range') {
                await _pickDateRangeFilter();
              } else if (value == 'clear_date') {
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                setState(() {
                  _startDate = today;
                  _endDate = today;
                });
                await _loadMutations();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'single_day', child: Text('Filter 1 Hari')),
              PopupMenuItem(
                value: 'date_range',
                child: Text('Filter Rentang Tanggal'),
              ),
              PopupMenuItem(
                value: 'clear_date',
                child: Text('Reset ke Hari Ini'),
              ),
            ],
            icon: const Icon(Icons.date_range),
          ),
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _printMutationReport,
            tooltip: 'Cetak laporan',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMutations,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadMutations,
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.all(narrowScreen ? 12 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildSummaryCard(
                              filterType: 'all',
                              'Total Mutasi',
                              _mutations.length,
                              Icons.swap_horiz,
                              Colors.blue,
                            ),
                          ),
                          SizedBox(width: narrowScreen ? 10 : 16),
                          Expanded(
                            child: _buildSummaryCard(
                              filterType: 'in',
                              'Penambahan stok',
                              _countByFilter('in'),
                              Icons.arrow_downward,
                              Colors.green,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: narrowScreen ? 10 : 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildSummaryCard(
                              filterType: 'out',
                              'Pengurangan stok',
                              _countByFilter('out'),
                              Icons.arrow_upward,
                              Colors.red,
                            ),
                          ),
                          SizedBox(width: narrowScreen ? 10 : 16),
                          Expanded(
                            child: _buildSummaryCard(
                              filterType: 'transfer_in',
                              'Transfer masuk',
                              _countByFilter('transfer_in'),
                              Icons.call_received,
                              Colors.blue,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: narrowScreen ? 10 : 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildSummaryCard(
                              filterType: 'transfer_out',
                              'Transfer keluar',
                              _countByFilter('transfer_out'),
                              Icons.call_made,
                              Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: narrowScreen ? 14 : 20),
                      Text(
                        'Riwayat Mutasi (${_filteredMutations.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Periode: ${_dateRangeLabel()}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _filteredMutations.isEmpty
                        ? const Center(child: Text('Tidak ada data mutasi'))
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 600;
                              final extraCompact = constraints.maxWidth < 420;
                              final cs = Theme.of(context).colorScheme;
                              final minW = narrow
                                  ? constraints.maxWidth
                                  : math.max(constraints.maxWidth, 800.0);
                              final showNotesColumn = !narrow;
                              final showTypeColumn = !narrow;
                              final borderColor = cs.outlineVariant.withValues(
                                alpha: 0.45,
                              );
                              final tableRows = <TableRow>[
                                TableRow(
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest,
                                    border: Border(
                                      bottom: BorderSide(color: borderColor),
                                    ),
                                  ),
                                  children: [
                                    _tableHeadCell(
                                      'Item',
                                      compact: extraCompact,
                                    ),
                                    _tableHeadCell(
                                      'Jumlah',
                                      align: TextAlign.right,
                                      compact: extraCompact,
                                    ),
                                    _tableHeadCell(
                                      'Tanggal',
                                      compact: extraCompact,
                                    ),
                                    if (showNotesColumn)
                                      _tableHeadCell(
                                        'Keterangan',
                                        compact: extraCompact,
                                      ),
                                    if (showTypeColumn)
                                      _tableHeadCell(
                                        'Tipe',
                                        compact: extraCompact,
                                      ),
                                  ],
                                ),
                              ];
                              for (
                                var i = 0;
                                i < _filteredMutations.length;
                                i++
                              ) {
                                final mutation = Map<String, dynamic>.from(
                                  _filteredMutations[i] as Map,
                                );
                                final typeLabel =
                                    _stockMutationTypeLabel(mutation);
                                final typeColor =
                                    _stockMutationTypeColor(mutation);
                                final description =
                                    _stockMutationDescription(mutation);
                                String dateStr = '—';
                                try {
                                  dateStr =
                                      DateFormat(
                                        'dd/MM/yyyy HH:mm',
                                        'id_ID',
                                      ).format(
                                        DateTime.parse(
                                          mutation['created_at']?.toString() ??
                                              '',
                                        ),
                                      );
                                } catch (_) {}
                                final descShort = description.length > 48
                                    ? '${description.substring(0, 45)}…'
                                    : description;
                                void onRowTap() {
                                  _showMutationHistoryDetail(mutation);
                                }

                                final baseTextStyle = TextStyle(
                                  fontSize: extraCompact ? 11.5 : 12.5,
                                );
                                tableRows.add(
                                  TableRow(
                                    decoration: BoxDecoration(
                                      color: i.isOdd
                                          ? cs.surfaceContainerHighest
                                                .withValues(alpha: 0.45)
                                          : null,
                                    ),
                                    children: [
                                      _tableBodyCell(
                                        compact: extraCompact,
                                        onTap: onRowTap,
                                        child: Row(
                                          children: [
                                            _stockMutationIcon(mutation),
                                            SizedBox(
                                              width: extraCompact ? 4 : 8,
                                            ),
                                            Expanded(
                                              child: Text(
                                                '${mutation['item_name'] ?? '—'}',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: baseTextStyle.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      _tableBodyCell(
                                        compact: extraCompact,
                                        onTap: onRowTap,
                                        align: Alignment.centerRight,
                                        child: Text(
                                          '${mutation['quantity'] ?? '—'} pcs',
                                          textAlign: TextAlign.right,
                                          style: baseTextStyle,
                                        ),
                                      ),
                                      _tableBodyCell(
                                        compact: extraCompact,
                                        onTap: onRowTap,
                                        child: Text(
                                          dateStr,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: baseTextStyle,
                                        ),
                                      ),
                                      if (showNotesColumn)
                                        _tableBodyCell(
                                          compact: extraCompact,
                                          onTap: onRowTap,
                                          child: Text(
                                            description == '—'
                                                ? '—'
                                                : descShort,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: baseTextStyle.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      if (showTypeColumn)
                                        _tableBodyCell(
                                          compact: extraCompact,
                                          onTap: onRowTap,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: extraCompact
                                                    ? 6
                                                    : 8,
                                                vertical: extraCompact ? 2 : 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: typeColor,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                typeLabel,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: extraCompact
                                                      ? 10
                                                      : 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }
                              final columnWidths = narrow
                                  ? const <int, TableColumnWidth>{
                                      0: FlexColumnWidth(2.4),
                                      1: FlexColumnWidth(1.0),
                                      2: FlexColumnWidth(1.7),
                                    }
                                  : const <int, TableColumnWidth>{
                                      0: FlexColumnWidth(2.0),
                                      1: FlexColumnWidth(1.0),
                                      2: FlexColumnWidth(1.5),
                                      3: FlexColumnWidth(2.0),
                                      4: FlexColumnWidth(1.0),
                                    };
                              return Card(
                                margin: EdgeInsets.zero,
                                clipBehavior: Clip.antiAlias,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: borderColor),
                                ),
                                child: Scrollbar(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minWidth: minW,
                                      ),
                                      child: Table(
                                        columnWidths: columnWidths,
                                        border: TableBorder(
                                          horizontalInside: BorderSide(
                                            color: borderColor,
                                          ),
                                        ),
                                        defaultVerticalAlignment:
                                            TableCellVerticalAlignment.middle,
                                        children: tableRows,
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

  Widget _buildSummaryCard(
    String title,
    int count,
    IconData icon,
    Color color, {
    required String filterType,
  }) {
    final screenW = MediaQuery.sizeOf(context).width;
    final narrow = screenW < 600;
    final extraCompact = screenW < 420;
    final isSelected = _selectedType == filterType;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? color : Colors.transparent,
          width: isSelected ? 1.6 : 0,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () => setState(() => _selectedType = filterType),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: extraCompact ? 8 : (narrow ? 10 : 16),
              horizontal: extraCompact ? 8 : (narrow ? 10 : 16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: extraCompact ? 30 : (narrow ? 34 : 38),
                  height: extraCompact ? 30 : (narrow ? 34 : 38),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isSelected ? 0.22 : 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: extraCompact ? 18 : (narrow ? 20 : 22),
                  ),
                ),
                SizedBox(width: extraCompact ? 8 : 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: extraCompact ? 11 : 12,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: extraCompact ? 6 : 10),
                Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: extraCompact ? 18 : (narrow ? 20 : 24),
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
