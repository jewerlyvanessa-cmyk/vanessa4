import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../utils/network_config.dart';

class BranchManagementPage extends ConsumerStatefulWidget {
  const BranchManagementPage({super.key});

  @override
  ConsumerState<BranchManagementPage> createState() => _BranchManagementPageState();
}

class _BranchManagementPageState extends ConsumerState<BranchManagementPage> {
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _filteredBranches = [];
  bool _isLoading = true;
  String _error = '';
  String _searchQuery = '';
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final response = await http.get(
        Uri.parse('${NetworkConfig.baseUrl}/branches'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData is List) {
          setState(() {
            _branches = List<Map<String, dynamic>>.from(responseData);
            _isLoading = false;
          });
        } else {
          setState(() {
            _error = 'Format data cabang tidak valid';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _error = 'Gagal memuat data cabang (${response.statusCode})';
          _isLoading = false;
        });
      }
      _applyFilters();
    } catch (error) {
      debugPrint('Error loading branches: $error');
      String errorMessage = 'Gagal memuat data cabang. ';
      if (error.toString().contains('Connection refused') || error.toString().contains('Failed host lookup')) {
        errorMessage += 'Pastikan server backend sedang berjalan.';
      } else {
        errorMessage += 'Error: ${error.toString()}';
      }
      setState(() {
        _error = errorMessage;
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    _filteredBranches = _branches.where((branch) {
      final matchesSearch = _searchQuery.isEmpty ||
          branch['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
          branch['code'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (branch['alias']?.toString().toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);

      final matchesStatus = _statusFilter == null || branch['status'] == _statusFilter;

      return matchesSearch && matchesStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Cabang'),
      ),
      body: Column(
        children: [
          // Search and Filter Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Cari cabang...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                      _applyFilters();
                    });
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: _statusFilter,
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Semua Status')),
                          DropdownMenuItem(value: 'active', child: Text('Aktif')),
                          DropdownMenuItem(value: 'inactive', child: Text('Tidak Aktif')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _statusFilter = value;
                            _applyFilters();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _loadBranches,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error, size: 64, color: Theme.of(context).colorScheme.error),
                            const SizedBox(height: 16),
                            Text(_error, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadBranches,
                              child: const Text('Coba Lagi'),
                            ),
                          ],
                        ),
                      )
                    : _filteredBranches.isEmpty
                        ? const Center(
                            child: Text('Tidak ada data cabang'),
                          )
                        : ListView.builder(
                            itemCount: _filteredBranches.length,
                            itemBuilder: (context, index) {
                              final branch = _filteredBranches[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: ExpansionTile(
                                  title: Text(
                                    branch['name'] ?? 'Unknown',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text('${branch['code']} - ${branch['alias'] ?? 'No alias'}'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: branch['status'] == 'active' 
                                            ? Theme.of(context).colorScheme.primary 
                                            : Theme.of(context).colorScheme.error,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          branch['status'] == 'active' ? 'Aktif' : 'Tidak Aktif',
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onPrimary, 
                                            fontSize: 12
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Edit functionality coming soon')),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Alamat: ${branch['address'] ?? 'N/A'}'),
                                          Text('Telepon: ${branch['phone_number'] ?? 'N/A'}'),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              ElevatedButton.icon(
                                                onPressed: () {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('Users functionality coming soon')),
                                                  );
                                                },
                                                icon: const Icon(Icons.people),
                                                label: const Text('Lihat Users'),
                                              ),
                                              const SizedBox(width: 8),
                                              ElevatedButton.icon(
                                                onPressed: () {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('Statistics functionality coming soon')),
                                                  );
                                                },
                                                icon: const Icon(Icons.bar_chart),
                                                label: const Text('Statistik'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Add branch functionality coming soon')),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
