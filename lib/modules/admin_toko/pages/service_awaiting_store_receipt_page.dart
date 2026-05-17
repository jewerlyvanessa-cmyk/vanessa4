import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/providers/store_workshop_receipt_count_provider.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/order_status_ui.dart';

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
      final baseUrl = NetworkConfig.baseUrl;
      final res = await http.get(
        Uri.parse(
          '$baseUrl/api/orders/service-awaiting-store-receipt?branch_id=${Uri.encodeQueryComponent(branch)}',
        ),
        headers: NetworkConfig.defaultHeaders,
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

  Future<void> _confirmReceive(Map<String, dynamic> row) async {
    final userState = ref.read(userStateProvider);
    final orderId = int.tryParse((row['order_id'] ?? '').toString());
    if (orderId == null) return;
    try {
      await ApiService.confirmWorkshopStoreReceipt(
        orderId: orderId,
        branchId: userState.branch,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Order #$orderId diterima — CS dapat memproses di menu Ambil',
          ),
        ),
      );
      ref.read(storeWorkshopReceiptCountProvider.notifier).refresh();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _rows.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Tidak ada kiriman workshop yang menunggu konfirmasi terima di toko.\n\n'
                  'Muncul setelah admin workshop menekan «Kirim ke Toko». '
                  'Setelah Anda «Terima», order tampil di menu Ambil CS.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final row = _rows[i];
                final oid = (row['order_id'] ?? '—').toString();
                final cust = (row['customer_name'] ?? '—').toString();
                final item = (row['item_name'] ?? '—').toString();
                final st = (row['status'] ?? '').toString();
                return Card(
                  child: ListTile(
                    title: Text('#$oid · $cust', maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '$item\n${OrderStatusUi.label(st)}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: FilledButton(
                      onPressed: () => _confirmReceive(row),
                      child: const Text('Terima'),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
