import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/modules/stockist/widgets/stock_inventory_grouped_table.dart'
    show showStockHistorySheet, stockBranchDisplayName;
import 'package:vanessa3/shared_widgets/stock_status_filter_summary_header.dart'
    show stockItemStatusLabel;
import 'package:vanessa3/utils/network_config.dart';

import 'package:mobile_scanner/mobile_scanner.dart'
    if (dart.library.html) '../utils/mobile_scanner_stub.dart';

class StockCheckPage extends ConsumerStatefulWidget {
  const StockCheckPage({super.key});

  @override
  ConsumerState<StockCheckPage> createState() => _StockCheckPageState();
}

class _StockCheckPageState extends ConsumerState<StockCheckPage> {
  final _codeCtrl = TextEditingController();
  bool _scannerEnabled = true;
  bool _loading = false;
  String _error = '';
  List<Map<String, dynamic>> _items = const [];

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  String _branchLabelForId(String branchId) {
    final bid = branchId.trim();
    if (bid.isEmpty) return '-';
    final branches = ref.read(userStateProvider).branches;
    for (final b in branches) {
      final id = (b['branch_id'] ?? '').toString();
      if (id != bid) continue;
      final alias = (b['alias'] ?? '').toString().trim();
        if (alias.isNotEmpty) return alias;
      final name = (b['name'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    }
    return bid;
  }

  Future<void> _lookup(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) return;

    setState(() {
      _loading = true;
      _error = '';
      _items = const [];
    });

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final user = ref.read(userStateProvider);
      final branchId = user.branch.toString().trim();

      Uri uri = Uri.parse('$baseUrl/items').replace(
        queryParameters: <String, String>{
          if (branchId.isNotEmpty) 'branch_id': branchId,
          'item_code': code,
          'limit': '10',
        },
      );

      var resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        final list = (decoded is List ? decoded : const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (list.isNotEmpty) {
          setState(() {
            _items = list;
            _loading = false;
          });
          return;
        }
      }

      // Fallback: try search (kode / nama / id).
      uri = Uri.parse('$baseUrl/items').replace(
        queryParameters: <String, String>{
          if (branchId.isNotEmpty) 'branch_id': branchId,
          'search': code,
          'limit': '10',
        },
      );
      resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final decoded2 = jsonDecode(resp.body);
      final list2 = (decoded2 is List ? decoded2 : const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      setState(() {
        _items = list2;
        _error = list2.isEmpty ? 'Item tidak ditemukan untuk kode: $code' : '';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Gagal cek stok: $e';
        _loading = false;
      });
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_scannerEnabled) return;
    final raw = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    final code = (raw ?? '').toString().trim();
    if (code.isEmpty) return;

    setState(() {
      _scannerEnabled = false;
      _codeCtrl.text = code;
    });
    _lookup(code);
  }

  Widget _scannerPanel(ColorScheme cs) {
    if (kIsWeb) {
      return _webScannerStub(cs);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: MobileScanner(
              onDetect: _onDetect,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.75),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 10,
            top: 10,
            child: FilledButton.tonalIcon(
              onPressed: () {
                setState(() => _scannerEnabled = !_scannerEnabled);
              },
              icon: Icon(_scannerEnabled ? Icons.pause : Icons.play_arrow),
              label: Text(_scannerEnabled ? 'Pause' : 'Scan'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _webScannerStub(ColorScheme cs) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: const AspectRatio(
        aspectRatio: 1,
        child: Center(
          child: Text('Scanner tidak tersedia di web.\nGunakan input manual.'),
        ),
      ),
    );
  }

  Widget _itemCard(BuildContext context, Map<String, dynamic> item) {
    final cs = Theme.of(context).colorScheme;
    final kode = (item['item_code'] ?? item['kode_produk'] ?? '').toString();
    final name = (item['name'] ?? '-').toString();
    final status = (item['status'] ?? '').toString();
    final qty = item['quantity'];
    final weight = item['weight'];
    final material = (item['material'] ?? '').toString();
    final purity = (item['purity'] ?? '').toString();
    final branchId = (item['branch_id'] ?? '').toString();
    final bidLabel = _branchLabelForId(branchId);
    final itemId = item['item_id'];

    final canHistory = branchId.trim().isNotEmpty && itemId != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    kode.isNotEmpty ? kode : '-',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                Chip(
                  label: Text(
                    status.isEmpty ? '-' : stockItemStatusLabel(status),
                    style: const TextStyle(fontSize: 11),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _kvPill(context, 'Cabang', bidLabel),
                _kvPill(context, 'Qty', (qty ?? '-').toString()),
                _kvPill(context, 'Berat', weight == null ? '-' : '$weight g'),
                if (material.trim().isNotEmpty)
                  _kvPill(context, 'Material', material),
                if (purity.trim().isNotEmpty) _kvPill(context, 'Kadar', purity),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canHistory
                        ? () async {
                            await showStockHistorySheet(
                              context,
                              item: Map<String, dynamic>.from(item),
                              branchId: branchId,
                              branchDisplayName: stockBranchDisplayName(
                                branches: ref.read(userStateProvider).branches,
                                branchId: branchId,
                              ),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.history),
                    label: const Text('Riwayat'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      setState(() => _scannerEnabled = true);
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan lagi'),
                  ),
                ),
              ],
            ),
            if (status.isNotEmpty &&
                (status.toLowerCase() != status ||
                    status.toLowerCase() != stockItemStatusLabel(status).toLowerCase())) ...[
              const SizedBox(height: 8),
              Text(
                'Status: $status',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kvPill(BuildContext context, String k, String v) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          '$k: $v',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cek Stok'),
        actions: [
          IconButton(
            tooltip: 'Clear',
            onPressed: () {
              setState(() {
                _codeCtrl.clear();
                _items = const [];
                _error = '';
                _scannerEnabled = true;
              });
            },
            icon: const Icon(Icons.clear_all),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          _scannerPanel(cs),
          const SizedBox(height: 12),
          TextField(
            controller: _codeCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Masukkan kode item (barcode / QR)',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                tooltip: 'Cek',
                icon: const Icon(Icons.arrow_forward),
                onPressed: _loading ? null : () => _lookup(_codeCtrl.text),
              ),
            ),
            onSubmitted: (v) => _lookup(v),
          ),
          const SizedBox(height: 10),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _error,
              style: TextStyle(color: cs.error, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 10),
          if (_items.isNotEmpty)
            ..._items.map((it) => _itemCard(context, it))
          else if (!_loading && _error.isEmpty)
            Text(
              'Scan barcode/QR atau ketik kode untuk melihat data item.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
        ],
      ),
    );
  }
}

