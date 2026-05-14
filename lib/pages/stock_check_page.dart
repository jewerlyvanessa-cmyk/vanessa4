import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/modules/stockist/widgets/stock_inventory_grouped_table.dart'
    show showStockHistorySheet, stockBranchDisplayName;
import 'package:vanessa3/shared_widgets/stock_status_filter_summary_header.dart'
    show stockItemStatusLabel;
import 'package:vanessa3/modules/stockist/stock_lookup_by_code.dart';
import 'package:vanessa3/widgets/qr_scan_route.dart';

class StockCheckPage extends ConsumerStatefulWidget {
  const StockCheckPage({super.key});

  @override
  ConsumerState<StockCheckPage> createState() => _StockCheckPageState();
}

class _StockCheckPageState extends ConsumerState<StockCheckPage> {
  final _codeCtrl = TextEditingController();
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
      final user = ref.read(userStateProvider);
      final branchId = user.branch.toString().trim();
      final list2 = await fetchStockItemsByCode(code: code, branchId: branchId);

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

  /// Layar scan standar aplikasi (`pushQrScanPage`), sama seperti kasir / CS / stockist lain.
  Future<void> _openStandardScan() async {
    if (_loading) return;
    final raw = await pushQrScanPage(context, title: 'Scan QR — Cek stok');
    if (!mounted || raw == null || raw.trim().isEmpty) return;
    final code = raw.trim();
    setState(() => _codeCtrl.text = code);
    await _lookup(code);
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
                    onPressed: _loading ? null : _openStandardScan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan lagi'),
                  ),
                ),
              ],
            ),
            if (status.isNotEmpty &&
                (status.toLowerCase() != status ||
                    status.toLowerCase() !=
                        stockItemStatusLabel(status).toLowerCase())) ...[
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
              });
            },
            icon: const Icon(Icons.clear_all),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          FilledButton.icon(
            onPressed: _loading ? null : _openStandardScan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Pindai QR / barcode'),
          ),
          const SizedBox(height: 8),
          Text(
            'Memakai layar scan standar aplikasi (sama seperti kasir / menu lain). '
            'Anda juga bisa mengetik kode di bawah.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Masukkan kode item (barcode / QR)',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Pindai QR',
                    onPressed: _loading ? null : _openStandardScan,
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                  IconButton(
                    tooltip: 'Cek',
                    onPressed: _loading ? null : () => _lookup(_codeCtrl.text),
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ],
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
              'Pindai QR/barcode atau ketik kode untuk melihat data item.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
        ],
      ),
    );
  }
}
