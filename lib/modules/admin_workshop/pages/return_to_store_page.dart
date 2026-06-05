import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/shared_widgets/workshop_order_document_sheet.dart';
import 'package:vanessa3/utils/workshop_order_batch_group.dart';

class ReturnToStorePage extends ConsumerStatefulWidget {
  const ReturnToStorePage({super.key});

  @override
  ConsumerState<ReturnToStorePage> createState() => _ReturnToStorePageState();
}

class _ReturnToStorePageState extends ConsumerState<ReturnToStorePage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

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
      final us = ref.read(userStateProvider);
      final branch = us.branch.trim();
      if (branch.isEmpty) {
        setState(() {
          _error = 'Cabang belum dipilih';
          _loading = false;
        });
        return;
      }

      // status=completed -> backend mengembalikan done_workshop + ready_for_pickup
      final resp = await ApiClient.get(
        '/workshop-orders',
        query: {
          'branch_id': branch,
          'status': 'completed',
        },
      );
      if (resp.statusCode != 200) {
        setState(() {
          _error = 'Gagal memuat (HTTP ${resp.statusCode})';
          _loading = false;
        });
        return;
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! List) {
        setState(() {
          _error = 'Format data tidak valid';
          _loading = false;
        });
        return;
      }
      final list = decoded
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

  List<Map<String, dynamic>> _filter(String status) {
    return _rows
        .where(
          (r) => (r['status'] ?? '').toString().trim().toLowerCase() == status,
        )
        .toList();
  }

  Future<void> _openReturnSheet(WorkshopOrderDocumentBatch batch) async {
    final us = ref.read(userStateProvider);
    final branchId = int.tryParse(us.branch.trim());
    if (branchId == null) return;

    await showWorkshopOrderDocumentSheet(
      context: context,
      batch: batch,
      actionKind: WorkshopDocumentActionKind.returnToStore,
      branchId: branchId,
      branchIdStr: us.branch.trim(),
      extraSubtitle: 'Toko akan menerima di menu «Terima dari workshop».',
      onCompleted: _load,
    );
  }

  Widget _doneWorkshopBatchesTable(BuildContext context, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const Center(child: Text('Tidak ada order selesai workshop'));
    }
    final batches = groupWorkshopOrdersByDocument(
      rows,
      flow: 'return_store',
      flowLabel: 'Kirim ke toko',
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: workshopOrderDocumentDataTable(
            context: context,
            batches: batches,
            minWidth: constraints.maxWidth,
            actionLabel: 'Cek & kirim',
            showAction: (_) => true,
            onOpenDocument: _openReturnSheet,
          ),
        );
      },
    );
  }

  Widget _readyTable(BuildContext context, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const Center(child: Text('Tidak ada order siap diambil di toko'));
    }
    final batches = groupWorkshopOrdersByDocument(
      rows,
      flow: 'return_ready',
      flowLabel: 'Sudah dikirim ke toko',
    );

    return Padding(
      padding: const EdgeInsets.all(12),
      child: workshopOrderDocumentDataTable(
        context: context,
        batches: batches,
        minWidth: MediaQuery.sizeOf(context).width - 24,
        actionLabel: '—',
        showAction: (_) => false,
        onOpenDocument: (_) {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // auto refresh when workshop updates arrive
    ref.listen(realTimeOrderUpdatesProvider, (prev, next) {
      next.whenData((u) {
        if (u['type'] == 'order_update' ||
            u['type'] == 'workshop_update' ||
            u['type'] == 'workshop_assignment') {
          _load();
        }
      });
    });

    final done = _filter('done_workshop');
    final ready = _filter('ready_for_pickup');

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kirim ke Toko'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
          ],
          bottom: _loading || _error != null
              ? null
              : TabBar(
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.white,
                  dividerColor: Colors.white24,
                  tabs: [
                    Tab(text: 'Selesai (${done.length})'),
                    Tab(text: 'Siap diambil (${ready.length})'),
                  ],
                ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : TabBarView(
                children: [
                  _doneWorkshopBatchesTable(context, done),
                  _readyTable(context, ready),
                ],
              ),
      ),
    );
  }
}
