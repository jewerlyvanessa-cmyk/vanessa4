import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/utils/branch_types.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/order_status_ui.dart';
import 'package:vanessa3/utils/workshop_order_batch_api.dart';

/// Order service/custom `awaiting_warehouse` — gudang kirim ke cabang workshop.
class WarehouseServiceDispatchPage extends ConsumerStatefulWidget {
  const WarehouseServiceDispatchPage({super.key});

  @override
  ConsumerState<WarehouseServiceDispatchPage> createState() =>
      _WarehouseServiceDispatchPageState();
}

class _WarehouseServiceDispatchPageState
    extends ConsumerState<WarehouseServiceDispatchPage> {
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _workshopBranches = [];
  int? _targetWorkshopId;
  bool _loading = true;
  String? _error;
  final Set<int> _selected = {};
  bool _submitting = false;

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
      final baseUrl = NetworkConfig.baseUrl;
      final branchesUri = Uri.parse('$baseUrl/branches').replace(
        queryParameters: {'branch_type': 'workshop'},
      );
      final queueUri =
          Uri.parse('$baseUrl/api/workshop/warehouse-service-queue');

      final results = await Future.wait([
        http.get(branchesUri, headers: NetworkConfig.defaultHeaders),
        http.get(queueUri, headers: NetworkConfig.defaultHeaders),
      ]);

      if (results[0].statusCode != 200) {
        setState(() {
          _error = 'Gagal memuat cabang workshop (${results[0].statusCode})';
          _loading = false;
        });
        return;
      }
      if (results[1].statusCode != 200) {
        setState(() {
          _error = 'Gagal memuat antrian service (${results[1].statusCode})';
          _loading = false;
        });
        return;
      }

      final branchesData = jsonDecode(results[0].body);
      final queueData = jsonDecode(results[1].body);
      final workshops = filterBranchesForTypeScope(
        branchesData is List ? branchesData : const [],
        'workshop',
      );
      final orders = (queueData is List ? queueData : const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (!mounted) return;
      setState(() {
        _workshopBranches = workshops;
        _orders = orders;
        if (_targetWorkshopId == null && workshops.length == 1) {
          final id = workshops.first['branch_id'];
          _targetWorkshopId = id is int
              ? id
              : int.tryParse(id?.toString() ?? '');
        }
        _selected.removeWhere(
          (id) => !orders.any(
            (o) => int.tryParse(o['order_id']?.toString() ?? '') == id,
          ),
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _dispatchSelected() async {
    final workshopId = _targetWorkshopId;
    if (workshopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih cabang workshop tujuan')),
      );
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Centang minimal satu order')),
      );
      return;
    }

    setState(() => _submitting = true);
    final result = await putWorkshopOrderStatuses(
      orderIds: _selected,
      status: 'sent-to-workshop',
      branchId: workshopId,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (result.okCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.allOk
                ? '${result.okCount} order dikirim ke workshop'
                : '${result.okCount} berhasil, ${result.failed.length} gagal',
          ),
        ),
      );
      await _load();
      setState(() => _selected.clear());
    } else if (result.failed.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.failed.first.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Service / Custom ke Workshop'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Order dari toko yang sudah masuk antrian gudang '
                                '(status menunggu gudang). Pilih workshop tujuan lalu kirim.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<int>(
                                key: ValueKey(_targetWorkshopId),
                                initialValue: _targetWorkshopId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Workshop tujuan',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: _workshopBranches.map((b) {
                                  final rawId = b['branch_id'];
                                  final id = rawId is int
                                      ? rawId
                                      : int.tryParse(rawId?.toString() ?? '');
                                  return DropdownMenuItem<int>(
                                    value: id,
                                    child: Text(
                                      (b['name'] ?? 'Workshop $id').toString(),
                                    ),
                                  );
                                }).toList(),
                                onChanged: _workshopBranches.isEmpty
                                    ? null
                                    : (v) =>
                                        setState(() => _targetWorkshopId = v),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _orders.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Tidak ada pekerjaan service/custom '
                                  'yang menunggu kirim dari gudang.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                                itemCount: _orders.length,
                                itemBuilder: (context, i) {
                                  final o = _orders[i];
                                  final oid = int.tryParse(
                                    o['order_id']?.toString() ?? '',
                                  );
                                  final checked =
                                      oid != null && _selected.contains(oid);
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: CheckboxListTile(
                                      value: checked,
                                      onChanged: oid == null
                                          ? null
                                          : (v) {
                                              setState(() {
                                                if (v == true) {
                                                  _selected.add(oid);
                                                } else {
                                                  _selected.remove(oid);
                                                }
                                              });
                                            },
                                      title: Text(
                                        '#${o['order_number'] ?? o['order_id']} · '
                                        '${(o['order_type'] ?? '').toString().toUpperCase()}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            o['customer_name']?.toString() ??
                                                '-',
                                          ),
                                          if ((o['item_name'] ?? '')
                                              .toString()
                                              .isNotEmpty)
                                            Text(o['item_name'].toString()),
                                          Text(
                                            'Toko: ${o['store_branch_name'] ?? o['branch_id'] ?? '-'}',
                                          ),
                                          Text(
                                            OrderStatusUi.label(
                                              o['status']?.toString(),
                                            ),
                                            style: TextStyle(
                                              color: cs.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      secondary: Icon(
                                        (o['order_type'] ?? '') == 'custom'
                                            ? Icons.design_services_outlined
                                            : Icons.build_circle_outlined,
                                        color: cs.tertiary,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
      bottomNavigationBar: _orders.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _submitting || _selected.isEmpty
                      ? null
                      : _dispatchSelected,
                  icon: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.local_shipping_outlined),
                  label: Text(
                    _submitting
                        ? 'Mengirim…'
                        : 'Kirim ke workshop (${_selected.length})',
                  ),
                ),
              ),
            ),
    );
  }
}
