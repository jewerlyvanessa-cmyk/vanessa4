import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/providers/websocket_provider.dart';

class TechnicianManagementPage extends ConsumerStatefulWidget {
  const TechnicianManagementPage({super.key});

  @override
  ConsumerState<TechnicianManagementPage> createState() =>
      _TechnicianManagementPageState();
}

class _TechnicianManagementPageState
    extends ConsumerState<TechnicianManagementPage> {
  List<dynamic> _technicians = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadTechnicians();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Note: ref.listen should be used in build method, not here
  }

  Future<void> _loadTechnicians() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;

      final response = await http.get(
        Uri.parse('$baseUrl/technicians?branch_id=${userState.branch}'),
        headers: NetworkConfig.defaultHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _technicians = data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Gagal memuat data teknisi';
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

  @override
  Widget build(BuildContext context) {
    // Listen to real-time technician updates
    ref.listen(realTimeOrderUpdatesProvider, (previous, next) {
      next.whenData((update) {
        if (update['type'] == 'technician_update' ||
            update['type'] == 'technician_assignment' ||
            update['type'] == 'workshop_update') {
          // Refresh technician data when relevant updates occur
          _loadTechnicians();
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Teknisi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTechnicians,
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
                    onPressed: _loadTechnicians,
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
                          'Total Teknisi',
                          _technicians.length,
                          Icons.engineering,
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildSummaryCard(
                          'Aktif',
                          _technicians
                              .where((t) => t['status'] == 'active')
                              .length,
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
                        child: _buildSummaryCard(
                          'Sibuk',
                          _technicians
                              .where((t) => t['status'] == 'busy')
                              .length,
                          Icons.schedule,
                          Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildSummaryCard(
                          'Tersedia',
                          _technicians
                              .where((t) => t['status'] == 'available')
                              .length,
                          Icons.check_circle_outline,
                          Colors.green,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Technicians List
                  Text(
                    'Daftar Teknisi (${_technicians.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),

                  if (_technicians.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('Belum ada data teknisi'),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _technicians.length,
                      itemBuilder: (context, index) {
                        final technician = _technicians[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _getStatusColor(
                                technician['status'],
                              ),
                              child: Icon(
                                Icons.engineering,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(technician['name'] ?? 'N/A'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Spesialisasi: ${technician['specialization'] ?? 'Umum'}',
                                ),
                                Text(
                                  'Status: ${_getStatusLabel(technician['status'])}',
                                  style: TextStyle(
                                    color: _getStatusColor(
                                      technician['status'],
                                    ),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (action) =>
                                  _handleTechnicianAction(technician, action),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'view_workload',
                                  child: Text('Lihat Beban Kerja'),
                                ),
                                const PopupMenuItem(
                                  value: 'assign_order',
                                  child: Text('Assign Order'),
                                ),
                              ],
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

  Widget _buildSummaryCard(
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
            Icon(icon, size: 32, color: color),
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

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'available':
        return Colors.green;
      case 'busy':
        return Colors.orange;
      case 'offline':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'available':
        return 'Tersedia';
      case 'busy':
        return 'Sibuk';
      case 'offline':
        return 'Offline';
      default:
        return 'Unknown';
    }
  }

  void _handleTechnicianAction(dynamic technician, String action) {
    switch (action) {
      case 'view_workload':
        // Navigate to workload view
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Melihat beban kerja ${technician['name']}')),
        );
        break;
      case 'assign_order':
        // Navigate to order assignment
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Assign order ke ${technician['name']}')),
        );
        break;
    }
  }
}
