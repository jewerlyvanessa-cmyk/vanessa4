import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/providers/store_workshop_receipt_count_provider.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/workshop_order_document_sheet.dart';
import 'package:vanessa3/utils/workshop_order_batch_group.dart';

/// Order service/custom `ready_for_pickup` dari workshop — admin toko konfirmasi terima fisik
/// (metadata `store_receipt_confirmed_at`) agar muncul di menu Ambil CS.
class ServiceAwaitingStoreReceiptPage extends ConsumerStatefulWidget {
  const ServiceAwaitingStoreReceiptPage({super.key});

  @override
  ConsumerState<ServiceAwaitingStoreReceiptPage> createState() =>
      _ServiceAwaitingStoreReceiptPageState();
}

class _ServiceAwaitingStoreReceiptPageState
    extends ConsumerState<ServiceAwaitingStoreReceiptPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  List<WorkshopOrderDocumentBatch> get _batches => groupWorkshopOrdersByDocument(
        _rows,
        flow: 'store_receipt',
        flowLabel: 'Terima dari workshop',
        counterpartyBranch: (o) =>
            (o['branch_id'] ?? '').toString(),
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
      final userState = ref.read(userStateProvider);
      final branch = userState.branch.trim();
      if (branch.isEmpty) {
        setState(() {
          _error = 'Cabang belum dipilih. Buka profil / pilih cabang lalu coba lagi.';
          _loading = false;
        });
        return;
      }
      final res = await ApiClient.get(
        '/api/orders/service-awaiting-store-receipt',
        query: {'branch_id': branch},
      );
      if (res.statusCode != 200) {
        setState(() {
          _error = 'Gagal memuat data (HTTP ${res.statusCode}).';
          _loading = false;
        });
        return;
      }
      final data = jsonDecode(res.body);
      final list = <Map<String, dynamic>>[];
      if (data is List) {
        for (final e in data) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
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

  Future<void> _openReceiveSheet(WorkshopOrderDocumentBatch batch) async {
    final userState = ref.read(userStateProvider);
    final branchStr = userState.branch.trim();
    final branchId = int.tryParse(branchStr) ?? 0;
    if (branchId <= 0) return;

    await showWorkshopOrderDocumentSheet(
      context: context,
      batch: batch,
      actionKind: WorkshopDocumentActionKind.confirmStoreReceipt,
      branchId: branchId,
      branchIdStr: branchStr,
      extraSubtitle: 'Setelah diterima, order tampil di menu Ambil CS.',
      onCompleted: () async {
        ref.read(storeWorkshopReceiptCountProvider.notifier).refresh();
        await _load();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final batches = _batches;
    final pendingOrders = _rows.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terima dari workshop'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Muat ulang',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Card(
                        child: ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: const Text('Menunggu konfirmasi terima'),
                          subtitle: const Text(
                            'Satu dokumen = beberapa order dikirim workshop '
                            'pada waktu yang sama. Centang per order sebelum terima.',
                          ),
                          trailing: Chip(label: Text('$pendingOrders')),
                        ),
                      ),
                    ),
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
                                    child: Text(
                                      'Tidak ada kiriman workshop yang menunggu konfirmasi.\n\n'
                                      'Muncul setelah admin workshop menekan «Kirim ke Toko».',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      0,
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
                                      actionLabel: 'Cek & terima',
                                      showAction: (_) => true,
                                      onOpenDocument: _openReceiveSheet,
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
