import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/modules/stockist/stock_lookup_by_code.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/stock_item_qr_print.dart';
import 'package:vanessa3/widgets/qr_scan_route.dart';

/// Cetak ulang label QR: ketik kode, pindai QR, pilih dari daftar stok, antrian + cetak massal.
class StockReprintQrPage extends ConsumerStatefulWidget {
  const StockReprintQrPage({super.key});

  @override
  ConsumerState<StockReprintQrPage> createState() => _StockReprintQrPageState();
}

class _StockReprintQrPageState extends ConsumerState<StockReprintQrPage> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  bool _printingBulk = false;
  String _error = '';
  List<Map<String, dynamic>> _items = const [];
  /// Urutan stabil: key → item (untuk cetak massal).
  final Map<String, Map<String, dynamic>> _queue = {};

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  String _stableItemKey(Map<String, dynamic> item) {
    final id = item['item_id'];
    if (id != null) return 'id:${id.toString()}';
    final c = (item['item_code'] ?? item['kode_produk'] ?? '').toString().trim();
    if (c.isNotEmpty) return 'c:$c';
    return 'h:${item.hashCode}';
  }

  String _kode(Map<String, dynamic> i) =>
      (i['item_code'] ?? i['kode_produk'] ?? '-').toString();

  void _mergeIntoQueue(Iterable<Map<String, dynamic>> items) {
    setState(() {
      for (final m in items) {
        final k = _stableItemKey(m);
        _queue[k] = Map<String, dynamic>.from(m);
      }
    });
  }

  void _removeFromQueue(String key) {
    setState(() => _queue.remove(key));
  }

  void _clearQueue() => setState(_queue.clear);

  String? _requireBranchId() {
    final branchId = ref.read(userStateProvider).branch.trim();
    if (branchId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih cabang aktif terlebih dahulu.')),
      );
      return null;
    }
    return branchId;
  }

  Future<void> _lookup() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan kode atau pindai QR.')),
      );
      return;
    }
    if (_requireBranchId() == null) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = '';
      _items = const [];
    });

    try {
      final raw = await fetchStockItemsByCode(
        code: code,
        branchId: ref.read(userStateProvider).branch.trim(),
        limit: 50,
      );
      final list =
          raw.where((it) => stockItemIsReadyForLabelReprint(it)).toList();
      if (!mounted) return;
      setState(() {
        _items = list;
        _error = list.isEmpty
            ? (raw.isEmpty
                ? 'Item tidak ditemukan untuk: $code'
                : 'Item ditemukan tetapi bukan stok ready (qty > 0).')
            : '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal mengambil data: $e';
        _loading = false;
      });
    }
  }

  Future<void> _scan() async {
    final raw = await pushQrScanPage(context, title: 'Pindai QR stok');
    if (!mounted || raw == null || raw.trim().isEmpty) return;
    setState(() => _codeCtrl.text = raw.trim());
    await _lookup();
  }

  Future<void> _openStockPicker() async {
    final bid = _requireBranchId();
    if (bid == null) return;

    final picked = await Navigator.of(context).push<List<Map<String, dynamic>>?>(
      MaterialPageRoute(
        builder: (context) => _StockInventoryPickerPage(branchId: bid),
      ),
    );
    if (!mounted || picked == null || picked.isEmpty) return;
    _mergeIntoQueue(picked);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${picked.length} item ditambahkan ke antrian.')),
    );
  }

  Future<void> _printItem(Map<String, dynamic> item) async {
    await promptPrintStockItemLabel(context, item: item);
  }

  Future<void> _printBulk() async {
    if (_queue.isEmpty) return;
    setState(() => _printingBulk = true);
    try {
      await promptPrintStockItemsLabelBulk(
        context,
        items: _queue.values.toList(),
      );
    } finally {
      if (mounted) setState(() => _printingBulk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cetak ulang label stok'),
        actions: [
          IconButton(
            tooltip: 'Bersihkan pencarian',
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
      bottomNavigationBar: _queue.isEmpty
          ? null
          : SafeArea(
              child: Material(
                elevation: 10,
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Antrian: ${_queue.length} item',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      TextButton(
                        onPressed: _printingBulk ? null : _clearQueue,
                        child: const Text('Kosongkan'),
                      ),
                      const SizedBox(width: 4),
                      FilledButton.icon(
                        onPressed: _printingBulk ? null : _printBulk,
                        icon: _printingBulk
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.print),
                        label: Text(_printingBulk ? '…' : 'Cetak massal'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'Sumber item: ketik kode / pindai QR, atau pilih dari daftar stok ready cabang aktif. '
            'Tambahkan ke antrian lalu «Cetak massal» untuk satu PDF banyak label '
            '(80×12 mm; QR, barcode, atau keduanya). «Cetak» pada satu baris untuk satu item.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _loading ? null : _openStockPicker,
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Pilih dari stok ready'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.tag),
              hintText: 'Kode item / kode produk',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                tooltip: 'Pindai QR',
                onPressed: _loading ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _lookup(),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _loading ? null : _lookup,
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(_loading ? 'Mencari…' : 'Cari item'),
          ),
          if (_loading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _error,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Hasil (${_items.length})',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _mergeIntoQueue(_items),
                  icon: const Icon(Icons.playlist_add, size: 20),
                  label: const Text('Tambah semua ke antrian'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._items.map((item) => _ResultCard(
                  item: item,
                  kode: _kode(item),
                  inQueue: _queue.containsKey(_stableItemKey(item)),
                  onAddQueue: () => _mergeIntoQueue([item]),
                  onRemoveQueue: () => _removeFromQueue(_stableItemKey(item)),
                  onPrintOne: () => _printItem(item),
                )),
          ],
          if (_queue.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Antrian cetak',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            ..._queue.entries.map(
              (e) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  title: Text(
                    _kode(e.value),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    (e.value['name'] ?? '-').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Hapus dari antrian',
                    icon: const Icon(Icons.close),
                    onPressed: () => _removeFromQueue(e.key),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.item,
    required this.kode,
    required this.inQueue,
    required this.onAddQueue,
    required this.onRemoveQueue,
    required this.onPrintOne,
  });

  final Map<String, dynamic> item;
  final String kode;
  final bool inQueue;
  final VoidCallback onAddQueue;
  final VoidCallback onRemoveQueue;
  final VoidCallback onPrintOne;

  @override
  Widget build(BuildContext context) {
    final name = (item['name'] ?? '-').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              kode,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (inQueue)
                  OutlinedButton.icon(
                    onPressed: onRemoveQueue,
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    label: const Text('Keluarkan'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: onAddQueue,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Antrian'),
                  ),
                FilledButton.icon(
                  onPressed: onPrintOne,
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text('Cetak'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Pilih banyak item dari inventaris cabang, dikembalikan ke halaman cetak QR.
class _StockInventoryPickerPage extends StatefulWidget {
  const _StockInventoryPickerPage({required this.branchId});

  final String branchId;

  @override
  State<_StockInventoryPickerPage> createState() =>
      _StockInventoryPickerPageState();
}

class _StockInventoryPickerPageState extends State<_StockInventoryPickerPage> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _all = const [];
  final Set<String> _selectedKeys = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _key(Map<String, dynamic> item) {
    final id = item['item_id'];
    if (id != null) return 'id:${id.toString()}';
    final c = (item['item_code'] ?? item['kode_produk'] ?? '').toString().trim();
    if (c.isNotEmpty) return 'c:$c';
    return 'h:${item.hashCode}';
  }

  String _kode(Map<String, dynamic> i) =>
      (i['item_code'] ?? i['kode_produk'] ?? '-').toString();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final list = await fetchStockInventoryItems(
        branchId: widget.branchId,
        status: 'ready',
      );
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat stok: $e';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((it) {
      final code = _kode(it).toLowerCase();
      final name = (it['name'] ?? '').toString().toLowerCase();
      return code.contains(q) || name.contains(q);
    }).toList();
  }

  void _toggle(String key, bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedKeys.add(key);
      } else {
        _selectedKeys.remove(key);
      }
    });
  }

  void _selectAllVisible(bool select) {
    setState(() {
      if (select) {
        for (final it in _filtered) {
          _selectedKeys.add(_key(it));
        }
      } else {
        for (final it in _filtered) {
          _selectedKeys.remove(_key(it));
        }
      }
    });
  }

  void _confirm() {
    final out = <Map<String, dynamic>>[];
    for (final it in _all) {
      if (_selectedKeys.contains(_key(it))) {
        out.add(Map<String, dynamic>.from(it));
      }
    }
    Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih stok ready'),
        actions: [
          if (!_loading && _error.isEmpty && _filtered.isNotEmpty)
            TextButton(
              onPressed: () => _selectAllVisible(
                _filtered.any((it) => !_selectedKeys.contains(_key(it))),
              ),
              child: Text(
                _filtered.every((it) => _selectedKeys.contains(_key(it)))
                    ? 'Batal pilih'
                    : 'Pilih tampilan',
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Hanya stok status Ready dengan qty > 0.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Saring kode / nama',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error.isNotEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text(
                        _all.isEmpty
                            ? 'Tidak ada stok ready di cabang ini.'
                            : 'Tidak ada stok ready yang cocok dengan pencarian.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) {
                        final it = _filtered[i];
                        final k = _key(it);
                        final code = _kode(it);
                        final name = (it['name'] ?? '-').toString();
                        return CheckboxListTile(
                          value: _selectedKeys.contains(k),
                          onChanged: (v) => _toggle(k, v),
                          title: Text(
                            code,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Batal'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _selectedKeys.isEmpty ? null : _confirm,
                    icon: const Icon(Icons.add),
                    label: Text('Tambah ke antrian (${_selectedKeys.length})'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
