import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/workshop_dashboard_provider.dart';
import 'package:vanessa3/providers/workshop_service_incoming_provider.dart';
import 'package:vanessa3/shared_widgets/workshop_order_document_sheet.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/workshop_order_batch_group.dart';

/// Service/custom dari toko: menunggu persetujuan admin workshop → antrian pekerjaan (`sent-to-workshop`).
class ServiceIncomingPage extends ConsumerStatefulWidget {
  const ServiceIncomingPage({super.key});

  @override
  ConsumerState<ServiceIncomingPage> createState() => _ServiceIncomingPageState();
}

class _ServiceIncomingPageState extends ConsumerState<ServiceIncomingPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  List<WorkshopOrderDocumentBatch> get _batches => groupWorkshopOrdersByDocument(
        _rows,
        flow: 'workshop_incoming',
        flowLabel: 'Persetujuan service dari toko',
        counterpartyBranch: (o) =>
            (o['pickup_branch_id'] ?? o['branch_id'] ?? '').toString(),
      );

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

  Future<void> _openApproveSheet(WorkshopOrderDocumentBatch batch) async {
    final branch = ref.read(userStateProvider).branch;
    final branchId = int.tryParse(branch);
    if (branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cabang tidak valid')),
      );
      return;
    }

    await showWorkshopOrderDocumentSheet(
      context: context,
      batch: batch,
      actionKind: WorkshopDocumentActionKind.approveIncoming,
      branchId: branchId,
      branchIdStr: branch,
      extraSubtitle:
          'Setelah disetujui, order masuk antrian pekerjaan workshop.',
      onCompleted: () async {
        await _load();
        ref.read(workshopServiceIncomingCountProvider.notifier).refresh();
        ref.read(workshopDashboardProvider.notifier).refresh();
      },
    );
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
                'Order dari toko yang dikirim bersamaan ditampilkan satu dokumen. '
                'Centang tiap order yang sudah dicek fisik sebelum menyetujui.',
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
    final batches = _batches;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Persetujuan service dari toko'),
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
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: batches.isEmpty
                            ? ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(top: 48),
                                children: const [
                                  Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Text(
                                        'Tidak ada order menunggu persetujuan workshop',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      8,
                                      12,
                                      12,
                                    ),
                                    child: workshopOrderDocumentDataTable(
                                      context: context,
                                      batches: batches,
                                      minWidth: math.max(
                                        constraints.maxWidth,
                                        720,
                                      ),
                                      actionLabel: 'Cek & setuju',
                                      showAction: (_) => true,
                                      onOpenDocument: _openApproveSheet,
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
}
