import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/utils/network_config.dart';

class GoodsTransferPage extends ConsumerStatefulWidget {
  const GoodsTransferPage({super.key});

  @override
  ConsumerState<GoodsTransferPage> createState() => _GoodsTransferPageState();
}

class _GoodsTransferPageState extends ConsumerState<GoodsTransferPage> {
  List<dynamic> _transferRequests = [];
  List<dynamic> _branches = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;

      // Load transfer requests
      final transfersResponse = await http.get(
        Uri.parse('$baseUrl/transfers?branch_id=${userState.branch}'),
        headers: {'Content-Type': 'application/json'},
      );

      // Load branches for dropdown
      final branchesResponse = await http.get(
        Uri.parse('$baseUrl/branches'),
        headers: {'Content-Type': 'application/json'},
      );

      if (transfersResponse.statusCode == 200 && branchesResponse.statusCode == 200) {
        final transfersData = jsonDecode(transfersResponse.body);
        final branchesData = jsonDecode(branchesResponse.body);

        setState(() {
          _transferRequests = transfersData;
          _branches = branchesData;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Gagal memuat data transfer';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kirim / Terima Barang'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateTransferDialog,
            tooltip: 'Kirim Barang',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
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
                        onPressed: _loadData,
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
                              'Permintaan Masuk',
                              _transferRequests.where((t) => t['to_branch_id'] == ref.read(userStateProvider).branch && t['status'] == 'pending').length,
                              Icons.arrow_downward,
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildSummaryCard(
                              'Permintaan Keluar',
                              _transferRequests.where((t) => t['from_branch_id'] == ref.read(userStateProvider).branch && t['status'] == 'pending').length,
                              Icons.arrow_upward,
                              Colors.orange,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Transfer Requests List
                      Text('Daftar Transfer', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 16),

                      if (_transferRequests.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('Belum ada permintaan transfer'),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _transferRequests.length,
                          itemBuilder: (context, index) {
                            final transfer = _transferRequests[index];
                            final isIncoming = transfer['to_branch_id'] == ref.read(userStateProvider).branch;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: Icon(
                                  isIncoming ? Icons.arrow_downward : Icons.arrow_upward,
                                  color: isIncoming ? Colors.blue : Colors.orange,
                                ),
                                title: Text('Transfer #${transfer['transfer_id']}'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${transfer['item_name']} (${transfer['quantity']} pcs)'),
                                    Text(
                                      isIncoming
                                          ? 'Dari: ${transfer['from_branch_name']}'
                                          : 'Ke: ${transfer['to_branch_name']}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      'Status: ${transfer['status']}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: transfer['status'] == 'completed' ? Colors.green :
                                               transfer['status'] == 'pending' ? Colors.orange : Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: isIncoming && transfer['status'] == 'pending'
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.check, color: Colors.green),
                                            onPressed: () => _approveTransfer(transfer['transfer_id']),
                                            tooltip: 'Terima',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.close, color: Colors.red),
                                            onPressed: () => _rejectTransfer(transfer['transfer_id']),
                                            tooltip: 'Tolak',
                                          ),
                                        ],
                                      )
                                    : transfer['status'] == 'pending'
                                        ? const Text('Menunggu', style: TextStyle(color: Colors.orange))
                                        : null,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateTransferDialog,
        tooltip: 'Kirim Barang Baru',
        child: const Icon(Icons.add),
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

  void _showCreateTransferDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateTransferDialog(branches: _branches),
    ).then((_) => _loadData());
  }

  Future<void> _approveTransfer(int transferId) async {
    try {
      final baseUrl = NetworkConfig.baseUrl;

      final response = await http.put(
        Uri.parse('$baseUrl/transfers/$transferId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': 'completed'}),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transfer berhasil diterima')),
          );
        }
        _loadData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal menerima transfer')),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $error')),
        );
      }
    }
  }

  Future<void> _rejectTransfer(int transferId) async {
    try {
      final baseUrl = NetworkConfig.baseUrl;

      final response = await http.put(
        Uri.parse('$baseUrl/transfers/$transferId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': 'rejected'}),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transfer berhasil ditolak')),
          );
        }
        _loadData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal menolak transfer')),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $error')),
        );
      }
    }
  }
}

class CreateTransferDialog extends StatefulWidget {
  final List<dynamic> branches;

  const CreateTransferDialog({super.key, required this.branches});

  @override
  State<CreateTransferDialog> createState() => _CreateTransferDialogState();
}

class _CreateTransferDialogState extends State<CreateTransferDialog> {
  final _formKey = GlobalKey<FormState>();
  int? _selectedBranchId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kirim Barang'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  labelText: 'Cabang Tujuan',
                  border: OutlineInputBorder(),
                ),
                initialValue: _selectedBranchId,
                items: widget.branches.map((branch) {
                  return DropdownMenuItem<int>(
                    value: branch['branch_id'],
                    child: Text(branch['name'] ?? 'Unknown Branch'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedBranchId = value;
                  });
                },
                validator: (value) => value == null ? 'Pilih cabang tujuan' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: _submitTransfer,
          child: const Text('Kirim'),
        ),
      ],
    );
  }

  Future<void> _submitTransfer() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final baseUrl = NetworkConfig.baseUrl;

      // Get current user branch as source
      final userState = context.findAncestorStateOfType<_GoodsTransferPageState>()?.ref.read(userStateProvider);

      final transferData = {
        'source_branch_id': userState?.branch,
        'destination_branch_id': _selectedBranchId,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      };

      final response = await http.post(
        Uri.parse('$baseUrl/transfers'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(transferData),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transfer berhasil dibuat')),
          );
        }
        // Refresh the transfer list
        if (mounted) {
          context.findAncestorStateOfType<_GoodsTransferPageState>()?._loadData();
          Navigator.of(context).pop();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal membuat transfer: ${response.statusCode}')),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $error')),
        );
      }
    }
  }
}
