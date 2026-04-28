import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/main.dart';
import 'package:vanessa3/utils/network_config.dart';

class DariTokoPage extends ConsumerStatefulWidget {
  const DariTokoPage({super.key});

  @override
  ConsumerState<DariTokoPage> createState() => _DariTokoPageState();
}

class _DariTokoPageState extends ConsumerState<DariTokoPage> {
  List<dynamic> _transfers = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadTransfers();
  }

  Future<void> _loadTransfers() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;

      final resp = await http.get(
        Uri.parse(
          '$baseUrl/transfers?branch_id=${userState.branch}&type=incoming',
        ),
        headers: NetworkConfig.defaultHeaders,
      );

      if (resp.statusCode != 200) {
        setState(() {
          _error = 'Gagal memuat transfer masuk (${resp.statusCode})';
          _isLoading = false;
        });
        return;
      }

      final data = jsonDecode(resp.body);
      setState(() {
        _transfers = (data is List) ? data : <dynamic>[];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _updateTransferStatus(int transferId, String status) async {
    final userState = ref.read(userStateProvider);
    final baseUrl = NetworkConfig.baseUrl;

    try {
      final resp = await http.put(
        Uri.parse('$baseUrl/transfers/$transferId'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({
          'status': status,
          'approved_by': userState.userId,
        }),
      );

      if (!mounted) return;

      if (resp.statusCode == 200) {
        await _loadTransfers();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transfer #$transferId: $status')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal update transfer (${resp.statusCode}): ${resp.body}',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final incomingPending =
        _transfers.where((t) => t['status'] == 'pending').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dari Toko (Masuk)'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadTransfers,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _loadTransfers,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadTransfers,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.arrow_downward),
                          title: const Text('Menunggu diterima'),
                          trailing: Chip(label: Text('$incomingPending')),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_transfers.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(child: Text('Belum ada transfer masuk')),
                        )
                      else
                        ..._transfers.map((t) {
                          final transfer = t as Map<String, dynamic>;
                          final id = int.tryParse(
                            transfer['transfer_id'].toString(),
                          );
                          final status = (transfer['status'] ?? '-').toString();
                          final fromName =
                              (transfer['from_branch_name'] ?? '-').toString();
                          final itemName =
                              (transfer['item_name'] ?? transfer['nama_item'] ?? '-')
                                  .toString();
                          final qty = (transfer['quantity'] ?? transfer['qty'] ?? '-')
                              .toString();

                          final canAct = id != null && status == 'pending';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: const Icon(Icons.inventory_2_outlined),
                              title: Text('Transfer #${id ?? '-'}'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('$itemName • $qty • Dari: $fromName'),
                                  if (status == 'completed' || status == 'rejected')
                                    Text(
                                      status == 'completed'
                                          ? 'Diterima oleh: ${(transfer['approved_by_name'] ?? '-').toString()}'
                                          : 'Ditolak oleh: ${(transfer['approved_by_name'] ?? '-').toString()}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                ],
                              ),
                              trailing: canAct
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Terima',
                                          icon: const Icon(
                                            Icons.check,
                                            color: Colors.green,
                                          ),
                                          onPressed: () => _updateTransferStatus(
                                            id,
                                            'completed',
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Tolak',
                                          icon: const Icon(
                                            Icons.close,
                                            color: Colors.red,
                                          ),
                                          onPressed: () => _updateTransferStatus(
                                            id,
                                            'rejected',
                                          ),
                                        ),
                                      ],
                                    )
                                  : Chip(label: Text(status)),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

