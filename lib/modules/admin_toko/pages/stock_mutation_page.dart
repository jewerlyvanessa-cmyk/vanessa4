import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/modules/admin_toko/logic/stock_mutation_report_print.dart';
import 'package:vanessa3/modules/admin_toko/logic/stock_mutation_utils.dart';
import 'package:vanessa3/modules/admin_toko/widgets/stock_mutation_history_table.dart';
import 'package:vanessa3/modules/admin_toko/widgets/stock_mutation_summary_section.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/app_date_picker.dart';

class StockMutationPage extends ConsumerStatefulWidget {
  const StockMutationPage({super.key});

  @override
  ConsumerState<StockMutationPage> createState() => _StockMutationPageState();
}

class _StockMutationPageState extends ConsumerState<StockMutationPage> {
  List<dynamic> _mutations = [];
  bool _isLoading = true;
  String _error = '';
  String _selectedType = 'all';
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
      final query = <String, String>{
        'branch_id': userState.branch.toString(),
        'limit': '200',
      };
      if (_startDate != null) {
        query['start_date'] = StockMutationUtils.isoDate(_startDate!);
      }
      if (_endDate != null) {
        query['end_date'] = StockMutationUtils.isoDate(_endDate!);
      }

      final response = await ApiClient.get('/stock-mutations', query: query);

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
          (m) => StockMutationUtils.matchesFilter(
            Map<String, dynamic>.from(m as Map),
            _selectedType,
          ),
        )
        .toList();
  }

  int _countByFilter(String filterKey) {
    return _mutations
        .where(
          (m) => StockMutationUtils.matchesFilter(
            Map<String, dynamic>.from(m as Map),
            filterKey,
          ),
        )
        .length;
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

    final bid = ref.read(userStateProvider).branch;
    await printStockMutationReport(
      rows: rows,
      branchId: bid,
      periodLabel: StockMutationUtils.dateRangeLabel(_startDate, _endDate),
      filterLabel: StockMutationUtils.filterLabel(_selectedType),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              PopupMenuItem(value: 'transfer_out', child: Text('Transfer keluar')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(StockMutationUtils.filterLabel(_selectedType)),
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
                    StockMutationSummarySection(
                      totalCount: _mutations.length,
                      inCount: _countByFilter('in'),
                      outCount: _countByFilter('out'),
                      transferInCount: _countByFilter('transfer_in'),
                      transferOutCount: _countByFilter('transfer_out'),
                      selectedType: _selectedType,
                      onFilterSelected: (v) => setState(() => _selectedType = v),
                      filteredCount: _filteredMutations.length,
                      periodLabel: StockMutationUtils.dateRangeLabel(
                        _startDate,
                        _endDate,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: StockMutationHistoryTable(
                          mutations: _filteredMutations,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
