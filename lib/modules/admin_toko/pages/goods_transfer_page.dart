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
        headers: NetworkConfig.defaultHeaders,
      );

      // Load branches for dropdown
      final branchesResponse = await http.get(
        Uri.parse('$baseUrl/branches'),
        headers: NetworkConfig.defaultHeaders,
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
        final transfersHint = transfersResponse.statusCode == 200
            ? 'OK'
            : '${transfersResponse.statusCode} ${transfersResponse.body}';
        final branchesHint = branchesResponse.statusCode == 200
            ? 'OK'
            : '${branchesResponse.statusCode} ${branchesResponse.body}';
        setState(() {
          _error = 'Gagal memuat data.\ntransfers: $transfersHint\nbranches: $branchesHint';
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
    final currentBranchId = ref.read(userStateProvider).branch;
    final currentBranchIdStr = currentBranchId.toString();

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
                              _transferRequests
                                  .where((t) =>
                                      t['to_branch_id']?.toString() == currentBranchIdStr &&
                                      t['status'] == 'pending')
                                  .length,
                              Icons.arrow_downward,
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildSummaryCard(
                              'Permintaan Keluar',
                              _transferRequests
                                  .where((t) =>
                                      t['from_branch_id']?.toString() == currentBranchIdStr &&
                                      t['status'] == 'pending')
                                  .length,
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
                            final isIncoming =
                                transfer['to_branch_id']?.toString() == currentBranchIdStr;
                            final transferIdRaw = transfer['transfer_id'];
                            final transferId = transferIdRaw is int
                                ? transferIdRaw
                                : int.tryParse(transferIdRaw?.toString() ?? '');

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
                                    if (isIncoming &&
                                        (transfer['status'] == 'completed' ||
                                            transfer['status'] == 'rejected'))
                                      Text(
                                        transfer['status'] == 'completed'
                                            ? 'Diterima oleh: ${(transfer['approved_by_name'] ?? '-').toString()}'
                                            : 'Ditolak oleh: ${(transfer['approved_by_name'] ?? '-').toString()}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                  ],
                                ),
                                trailing: isIncoming && transfer['status'] == 'pending'
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.check, color: Colors.green),
                                            onPressed: transferId == null ? null : () => _approveTransfer(transferId),
                                            tooltip: 'Terima',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.close, color: Colors.red),
                                            onPressed: transferId == null ? null : () => _rejectTransfer(transferId),
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
    final fromBranchId = ref.read(userStateProvider).branch;
    showDialog(
      context: context,
      builder: (context) => CreateTransferDialog(
        branches: _branches,
        fromBranchId: fromBranchId,
      ),
    ).then((_) => _loadData());
  }

  Future<void> _approveTransfer(int transferId) async {
    try {
      final baseUrl = NetworkConfig.baseUrl;
      final userState = ref.read(userStateProvider);

      final response = await http.put(
        Uri.parse('$baseUrl/transfers/$transferId'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({
          'status': 'completed',
          'approved_by': userState.userId,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transfer berhasil diterima')),
          );
        }
        _loadData();
      } else {
        String msg = 'Gagal menerima transfer';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map && (decoded['detail'] != null || decoded['error'] != null)) {
            msg = '${decoded['error'] ?? msg}${decoded['detail'] != null ? '\n${decoded['detail']}' : ''}';
          } else {
            msg = '$msg (${response.statusCode})';
          }
        } catch (_) {
          msg = '$msg (${response.statusCode}): ${response.body}';
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
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
      final userState = ref.read(userStateProvider);

      final response = await http.put(
        Uri.parse('$baseUrl/transfers/$transferId'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({
          'status': 'rejected',
          'approved_by': userState.userId,
        }),
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
  final dynamic fromBranchId;

  const CreateTransferDialog({
    super.key,
    required this.branches,
    required this.fromBranchId,
  });

  @override
  State<CreateTransferDialog> createState() => _CreateTransferDialogState();
}

class _CreateTransferDialogState extends State<CreateTransferDialog> {
  final _formKey = GlobalKey<FormState>();
  int? _selectedBranchId;
  String _selectedSourceType = 'stok';
  Map<String, dynamic>? _selectedItem;
  final TextEditingController _quantityController = TextEditingController(text: '1');
  final TextEditingController _notesController = TextEditingController();
  bool _isLoadingItems = false;
  String _itemsError = '';
  List<Map<String, dynamic>> _availableItems = [];

  @override
  void initState() {
    super.initState();
    _loadAvailableItems();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableItems() async {
    setState(() {
      _isLoadingItems = true;
      _itemsError = '';
      _availableItems = [];
      _selectedItem = null;
    });

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final status = _selectedSourceType == 'buyback' ? 'buyback' : 'ready';
      final uri = Uri.parse(
        '$baseUrl/items?branch_id=${widget.fromBranchId}&status=$status&limit=200',
      );
      final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
      if (resp.statusCode != 200) {
        setState(() {
          _itemsError = 'Gagal memuat item ($status): ${resp.statusCode}';
          _isLoadingItems = false;
        });
        return;
      }

      final decoded = jsonDecode(resp.body);
      final list = (decoded is List) ? decoded : <dynamic>[];
      final mapped = list
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .where((it) {
            final q = it['quantity'];
            final qty = q is int ? q : int.tryParse(q?.toString() ?? '') ?? 0;
            return qty > 0;
          })
          .toList();

      setState(() {
        _availableItems = mapped;
        _isLoadingItems = false;
      });
    } catch (e) {
      setState(() {
        _itemsError = 'Error: $e';
        _isLoadingItems = false;
      });
    }
  }

  String _itemLabel(Map<String, dynamic> it) {
    final code = (it['item_code'] ?? it['kode_produk'] ?? '').toString();
    final name = (it['name'] ?? '').toString();
    if (code.isNotEmpty && name.isNotEmpty) return '$code - $name';
    return name.isNotEmpty ? name : code;
  }

  int _selectedItemStock() {
    final q = _selectedItem?['quantity'];
    if (q is int) return q;
    return int.tryParse(q?.toString() ?? '') ?? 0;
  }

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
                  final rawId = branch['branch_id'];
                  final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
                  return DropdownMenuItem<int>(
                    value: id,
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
              const SizedBox(height: 12),
              if (_itemsError.isNotEmpty)
                Text(_itemsError, style: const TextStyle(color: Colors.red)),
              if (_isLoadingItems)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                ),
              if (!_isLoadingItems && _itemsError.isEmpty)
                Autocomplete<Map<String, dynamic>>(
                  displayStringForOption: (it) => _itemLabel(it),
                  optionsBuilder: (value) {
                    final q = value.text.trim().toLowerCase();
                    if (q.isEmpty) return _availableItems.take(30);
                    return _availableItems.where((it) {
                      final label = _itemLabel(it).toLowerCase();
                      return label.contains(q);
                    }).take(30);
                  },
                  onSelected: (it) {
                    setState(() => _selectedItem = it);
                  },
                  fieldViewBuilder: (
                    context,
                    textEditingController,
                    focusNode,
                    onFieldSubmitted,
                  ) {
                    return TextFormField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: _selectedSourceType == 'buyback'
                            ? 'Item (buyback)'
                            : 'Item (stok)',
                        helperText: _selectedItem == null
                            ? 'Ketik untuk cari item'
                            : 'Stok tersedia: ${_selectedItemStock()}',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (_) {
                        if (_selectedItem == null) return 'Pilih item dari daftar';
                        return null;
                      },
                      onChanged: (_) {
                        if (_selectedItem != null) {
                          setState(() => _selectedItem = null);
                        }
                      },
                    );
                  },
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantity (pcs)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final v = int.tryParse((value ?? '').trim());
                  if (v == null || v <= 0) return 'Quantity harus angka > 0';
                  if (_selectedItem != null && v > _selectedItemStock()) {
                    return 'Qty melebihi stok (${_selectedItemStock()})';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedSourceType,
                decoration: const InputDecoration(
                  labelText: 'Sumber barang',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'stok', child: Text('Dari stok')),
                  DropdownMenuItem(value: 'buyback', child: Text('Dari buyback')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _selectedSourceType = v);
                  _loadAvailableItems();
                },
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

      final transferData = {
        'from_branch_id': widget.fromBranchId,
        'to_branch_id': _selectedBranchId,
        'item_name': (_selectedItem?['name'] ?? '').toString().trim(),
        'quantity': int.parse(_quantityController.text.trim()),
        'source_type': _selectedSourceType,
        'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      };

      final response = await http.post(
        Uri.parse('$baseUrl/transfers'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode(transferData),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transfer berhasil dibuat')),
          );
        }
        if (mounted) {
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
