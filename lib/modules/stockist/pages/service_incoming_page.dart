import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/order_status_ui.dart';

/// Service/custom dari toko: status `awaiting_warehouse` — setujui agar masuk workshop (`sent-to-workshop`).
class ServiceIncomingPage extends ConsumerStatefulWidget {
  const ServiceIncomingPage({super.key});

  @override
  ConsumerState<ServiceIncomingPage> createState() => _ServiceIncomingPageState();
}

class _ServiceIncomingPageState extends ConsumerState<ServiceIncomingPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final branch = ref.read(userStateProvider).branch;
      final uri = Uri.parse(
        '${NetworkConfig.baseUrl}/api/workshop/service-incoming?branch_id=$branch',
      );
      final res = await http.get(uri, headers: NetworkConfig.defaultHeaders);
      if (res.statusCode != 200) {
        setState(() {
          _error = 'Gagal memuat (${res.statusCode})';
          _loading = false;
        });
        return;
      }
      final data = jsonDecode(res.body);
      final list = (data is List ? data : const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _approve(Map<String, dynamic> row) async {
    final oid = row['order_id']?.toString();
    if (oid == null || oid.isEmpty) return;
    final branch = ref.read(userStateProvider).branch;
    final branchId = int.tryParse(branch);
    if (branchId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cabang tidak valid')),
        );
      }
      return;
    }
    try {
      final res = await http.put(
        Uri.parse('${NetworkConfig.baseUrl}/workshop-orders/$oid/status'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({
          'branch_id': branchId,
          'status': 'sent-to-workshop',
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Order #$oid masuk antrian pekerjaan — buka menu Antrian pekerjaan (admin) atau Antrian kerja (teknisi).',
            ),
          ),
        );
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${res.body}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Widget _hintAfterApprove() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Setelah disetujui, order hilang dari daftar ini dan masuk daftar pekerjaan: '
                'di aplikasi admin bengkel buka menu «Antrian pekerjaan»; di aplikasi teknisi buka «Antrian kerja».',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service dari toko'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _hintAfterApprove(),
                Expanded(
                  child: _rows.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Tidak ada order menunggu persetujuan bengkel',
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _rows.length,
                          itemBuilder: (context, i) {
                            final row = _rows[i];
                            final st = (row['status'] ?? '').toString();
                            return Card(
                              child: ListTile(
                                title: Text(
                                  '#${row['order_id']} · ${row['item_name'] ?? '—'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${row['customer_name'] ?? ''} · ${OrderStatusUi.label(st)}',
                                ),
                                trailing: FilledButton(
                                  onPressed: () => _approve(row),
                                  child: const Text('Setuju'),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
