import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/utils/network_config.dart';

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

  @override
  void initState() {
    super.initState();
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

      final response = await http.get(
        Uri.parse('$baseUrl/stock-mutations?branch_id=${userState.branch}'),
        headers: {'Content-Type': 'application/json'},
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
    return _mutations.where((m) => m['type'] == _selectedType).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mutasi Stok'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => setState(() => _selectedType = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('Semua')),
              const PopupMenuItem(value: 'in', child: Text('Masuk')),
              const PopupMenuItem(value: 'out', child: Text('Keluar')),
              const PopupMenuItem(value: 'transfer', child: Text('Transfer')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(_getTypeLabel(_selectedType)),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
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
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary Cards
                      Row(
                        children: [
                          Expanded(
                            child: _buildSummaryCard(
                              'Total Mutasi',
                              _mutations.length,
                              Icons.swap_horiz,
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildSummaryCard(
                              'Stok Masuk',
                              _mutations.where((m) => m['type'] == 'in').length,
                              Icons.arrow_downward,
                              Colors.green,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child: _buildSummaryCard(
                              'Stok Keluar',
                              _mutations.where((m) => m['type'] == 'out').length,
                              Icons.arrow_upward,
                              Colors.red,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildSummaryCard(
                              'Transfer',
                              _mutations.where((m) => m['type'] == 'transfer').length,
                              Icons.compare_arrows,
                              Colors.orange,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Mutations List
                      Text('Riwayat Mutasi (${_filteredMutations.length})', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 16),

                      if (_filteredMutations.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('Tidak ada data mutasi'),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _filteredMutations.length,
                          itemBuilder: (context, index) {
                            final mutation = _filteredMutations[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: _getMutationIcon(mutation['type']),
                                title: Text('${mutation['item_name']}'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Jumlah: ${mutation['quantity']} pcs'),
                                    Text(
                                      'Tanggal: ${DateFormat('dd/MM/yyyy HH:mm', 'id_ID').format(DateTime.parse(mutation['created_at']))}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    if (mutation['notes'] != null && mutation['notes'].isNotEmpty)
                                      Text(
                                        'Catatan: ${mutation['notes']}',
                                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                                      ),
                                  ],
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getTypeColor(mutation['type']),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _getTypeLabel(mutation['type']),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSummaryCard(String title, int count, IconData icon, Color color) {
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

  Icon _getMutationIcon(String type) {
    switch (type) {
      case 'in':
        return const Icon(Icons.arrow_downward, color: Colors.green);
      case 'out':
        return const Icon(Icons.arrow_upward, color: Colors.red);
      case 'transfer':
        return const Icon(Icons.compare_arrows, color: Colors.orange);
      default:
        return const Icon(Icons.swap_horiz, color: Colors.blue);
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'in':
        return Colors.green;
      case 'out':
        return Colors.red;
      case 'transfer':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'in':
        return 'Masuk';
      case 'out':
        return 'Keluar';
      case 'transfer':
        return 'Transfer';
      case 'all':
        return 'Semua';
      default:
        return 'Lainnya';
    }
  }
}
