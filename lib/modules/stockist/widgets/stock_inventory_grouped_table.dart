import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/stock_item_qr_print.dart';

/// Nama cabang dari daftar [branches] (userState.branches) untuk teks riwayat stok.
String? stockBranchDisplayName({
  required List<dynamic> branches,
  required String branchId,
}) {
  final bid = branchId.trim();
  if (bid.isEmpty) return null;
  for (final b in branches) {
    if (b is! Map) continue;
    final m = Map<String, dynamic>.from(b);
    if (m['branch_id']?.toString() == bid) {
      final n = (m['name'] ?? '').toString().trim();
      if (n.isNotEmpty) return n;
    }
  }
  return null;
}

Color stockInventoryStatusColor(String status) {
  switch (status) {
    case 'ready':
      return Colors.green;
    case 'reserved':
      return Colors.orange;
    case 'sold':
      return Colors.red;
    case 'buyback':
      return Colors.blue;
    case 'on-service':
      return Colors.purple;
    case 'on-custom':
      return Colors.indigo;
    default:
      return Colors.grey;
  }
}

String stockItemJenisLabel(Map<String, dynamic> item) {
  final j = (item['jenis'] ?? '').toString().trim();
  return j.isEmpty ? 'Tanpa jenis' : j;
}

/// Urut kelompok by label jenis; dalam kelompok urut by kode barang.
List<MapEntry<String, List<Map<String, dynamic>>>> groupStockItemsByJenis(
  List<dynamic> raw,
) {
  final byJenis = <String, List<Map<String, dynamic>>>{};
  for (final it in raw) {
    if (it is! Map) continue;
    final map = Map<String, dynamic>.from(it);
    final key = stockItemJenisLabel(map);
    byJenis.putIfAbsent(key, () => []).add(map);
  }
  for (final list in byJenis.values) {
    list.sort((a, b) {
      final ka = (a['item_code'] ?? a['kode_produk'] ?? '').toString();
      final kb = (b['item_code'] ?? b['kode_produk'] ?? '').toString();
      final c = ka.toLowerCase().compareTo(kb.toLowerCase());
      if (c != 0) return c;
      return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
    });
  }
  final keys = byJenis.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [for (final k in keys) MapEntry(k, byJenis[k]!)];
}

Future<bool> _postItemRestock({
  required BuildContext context,
  required String branchId,
  required dynamic itemId,
  required int deltaQty,
}) async {
  try {
    final baseUrl = NetworkConfig.baseUrl;
    final resp = await http.post(
      Uri.parse('$baseUrl/items/$itemId/restock'),
      headers: NetworkConfig.defaultHeaders,
      body: jsonEncode(<String, dynamic>{
        'delta_quantity': deltaQty,
        'branch_id': branchId,
      }),
    );

    if (!context.mounted) return false;

    if (resp.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restock berhasil')),
      );
      return true;
    }

    String backendMsg = resp.body;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map && decoded['error'] != null) {
        backendMsg = decoded['error'].toString();
      } else if (decoded is Map && decoded['detail'] != null) {
        backendMsg = decoded['detail'].toString();
      }
    } catch (_) {}

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Gagal restock (${resp.statusCode}): $backendMsg'),
      ),
    );
    return false;
  } catch (e) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e')),
    );
    return false;
  }
}

Future<void> showStockRestockDialog(
  BuildContext context, {
  required Map<String, dynamic> item,
  required String branchId,
  required Future<void> Function() reloadList,
}) async {
  final formKey = GlobalKey<FormState>();
  final qtyController = TextEditingController(text: '1');

  final itemId = item['item_id'];
  final kode = (item['item_code'] ?? item['kode_produk'] ?? '').toString();
  final name = (item['name'] ?? '-').toString();

  if (itemId == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Item ID tidak ditemukan')),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      var isSaving = false;
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Restock'),
            content: SizedBox(
              width: 420,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kode.isNotEmpty ? '$kode • $name' : name,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: qtyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Qty tambah',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) {
                        final parsed = int.tryParse((v ?? '').trim());
                        if (parsed == null || parsed <= 0) return 'Invalid';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (formKey.currentState?.validate() != true) return;
                        setDialogState(() => isSaving = true);
                        final deltaQty = int.parse(qtyController.text.trim());
                        final ok = await _postItemRestock(
                          context: context,
                          branchId: branchId,
                          itemId: itemId,
                          deltaQty: deltaQty,
                        );
                        if (!dialogContext.mounted) return;
                        if (ok) {
                          await reloadList();
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          if (context.mounted) {
                            await promptPrintStockItemQr(
                              context,
                              item: Map<String, dynamic>.from(item),
                            );
                          }
                          return;
                        }
                        setDialogState(() => isSaving = false);
                      },
                child: isSaving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Simpan'),
              ),
            ],
          );
        },
      );
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    qtyController.dispose();
  });
}

Future<void> showStockHistorySheet(
  BuildContext context, {
  required Map<String, dynamic> item,
  required String branchId,
  String? branchDisplayName,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.sizeOf(ctx).height * 0.68,
      child: StockHistoryBottomSheet(
        item: item,
        branchId: branchId,
        branchDisplayName: branchDisplayName,
      ),
    ),
  );
}

/// Tabel stok per kelompok `jenis`, ringkas di layar sempit (< 600px lebar).
///
/// Mode **stockist** (default): menu restock + riwayat — wajib [branchIdForMutations] dan [onReload].
/// Mode **baca saja** ([showStockistActions] = false): kolom terakhir tombol detail lewat [onOpenItemDetail].
/// Jika [showReadOnlyHistory] true, menu juga menampilkan **Riwayat stok** (wajib [branchIdForMutations]).
/// [branchDisplayNameForHistory] opsional: nama cabang untuk kartu "Data awal" di bottom sheet riwayat.
class StockInventoryGroupedTable extends StatelessWidget {
  // ignore: prefer_const_constructors_in_immutables — nullable branch/onReload untuk mode baca saja
  StockInventoryGroupedTable({
    super.key,
    required this.filteredItems,
    this.branchIdForMutations,
    this.onReload,
    this.showStockistActions = true,
    this.showReadOnlyHistory = false,
    this.branchDisplayNameForHistory,
    this.onOpenItemDetail,
  });

  final List<dynamic> filteredItems;
  final String? branchIdForMutations;
  final Future<void> Function()? onReload;
  final bool showStockistActions;
  /// Admin / baca saja: tampilkan aksi riwayat mutasi (perlu [branchIdForMutations]).
  final bool showReadOnlyHistory;
  /// Nama cabang aktif (warehouse / cabang) untuk teks di riwayat stok.
  final String? branchDisplayNameForHistory;
  final void Function(Map<String, dynamic> item)? onOpenItemDetail;

  Widget _tableHeaderCell(String label, {TextAlign align = TextAlign.left}) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(
          label,
          textAlign: align,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
    );
  }

  Widget _qtyCell(Map<String, dynamic> item) {
    final qtyRaw = item['quantity'] ?? item['qty'];
    final qty = (qtyRaw is num)
        ? qtyRaw.toString()
        : (qtyRaw?.toString().trim().isNotEmpty == true)
            ? qtyRaw.toString()
            : '1';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        qty,
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  Widget _trailingCell(BuildContext context, Map<String, dynamic> item) {
    if (showStockistActions) {
      final bid = branchIdForMutations ?? '';
      final reload = onReload ?? () async {};
      return Align(
        alignment: Alignment.center,
        child: PopupMenuButton<String>(
          tooltip: 'Aksi',
          padding: EdgeInsets.zero,
          iconSize: 22,
          onSelected: (value) async {
            if (value == 'restock') {
              await showStockRestockDialog(
                context,
                item: item,
                branchId: bid,
                reloadList: reload,
              );
            } else if (value == 'history') {
              await showStockHistorySheet(
                context,
                item: item,
                branchId: bid,
                branchDisplayName: branchDisplayNameForHistory,
              );
            } else if (value == 'print_qr') {
              if (!context.mounted) return;
              await promptPrintStockItemQr(
                context,
                item: Map<String, dynamic>.from(item),
              );
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'history',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.history),
                title: Text('Riwayat stok'),
              ),
            ),
            const PopupMenuItem(
              value: 'restock',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.add_box),
                title: Text('Restock'),
              ),
            ),
            const PopupMenuItem(
              value: 'print_qr',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.qr_code_2),
                title: Text('Cetak QR'),
              ),
            ),
          ],
        ),
      );
    }
    if (onOpenItemDetail != null) {
      final bid = branchIdForMutations ?? '';
      if (showReadOnlyHistory && bid.isNotEmpty) {
        return Align(
          alignment: Alignment.center,
          child: PopupMenuButton<String>(
            tooltip: 'Menu',
            padding: EdgeInsets.zero,
            iconSize: 22,
            onSelected: (value) async {
              if (value == 'detail') {
                onOpenItemDetail!(item);
              } else if (value == 'history') {
                await showStockHistorySheet(
                  context,
                  item: item,
                  branchId: bid,
                  branchDisplayName: branchDisplayNameForHistory,
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'detail',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline),
                  title: Text('Detail'),
                ),
              ),
              PopupMenuItem(
                value: 'history',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.history),
                  title: Text('Riwayat stok'),
                ),
              ),
            ],
          ),
        );
      }
      return Align(
        alignment: Alignment.center,
        child: IconButton(
          tooltip: 'Detail',
          icon: const Icon(Icons.info_outline, size: 22),
          onPressed: () => onOpenItemDetail!(item),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  TableRow _dataRow(BuildContext context, Map<String, dynamic> item, bool isCompact) {
    final kodeProduk =
        (item['kode_produk'] ?? item['item_code'] ?? '').toString();
    final name = (item['name'] ?? '-').toString();
    final status = (item['status'] ?? '-').toString();
    final weight = item['weight'];
    final weightText = weight == null
        ? '—'
        : (weight is num ? '${weight.toString()} g' : '$weight g');

    final borderColor = Theme.of(context).dividerColor;

    List<Widget> cells;
    if (isCompact) {
      cells = [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            kodeProduk.isEmpty ? '—' : kodeProduk,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        _qtyCell(item),
        _trailingCell(context, item),
      ];
    } else {
      cells = [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            kodeProduk.isEmpty ? '—' : kodeProduk,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(weightText, style: const TextStyle(fontSize: 13)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              label: Text(status, style: const TextStyle(fontSize: 11)),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: stockInventoryStatusColor(status)),
            ),
          ),
        ),
        _qtyCell(item),
        _trailingCell(context, item),
      ];
    }

    return TableRow(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      children: cells
          .map(
            (w) => TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: w,
            ),
          )
          .toList(),
    );
  }

  Widget _jenisGroupTable(BuildContext context, String jenisLabel, List<Map<String, dynamic>> rows) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 600;
    final scheme = Theme.of(context).colorScheme;
    final borderColor = Theme.of(context).dividerColor;

    final columnWidths = isCompact
        ? const <int, TableColumnWidth>{
            0: FlexColumnWidth(1.05),
            1: FlexColumnWidth(2.35),
            2: FlexColumnWidth(0.55),
            3: FixedColumnWidth(42),
          }
        : const <int, TableColumnWidth>{
            0: FlexColumnWidth(1),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(0.75),
            3: FlexColumnWidth(0.95),
            4: FlexColumnWidth(0.55),
            5: FixedColumnWidth(44),
          };

    final headerRow = TableRow(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: borderColor),
        ),
      ),
      children: isCompact
          ? [
              _tableHeaderCell('Kode'),
              _tableHeaderCell('Nama'),
              _tableHeaderCell('Qty', align: TextAlign.right),
              _tableHeaderCell(''),
            ]
          : [
              _tableHeaderCell('Kode'),
              _tableHeaderCell('Nama'),
              _tableHeaderCell('Berat'),
              _tableHeaderCell('Status'),
              _tableHeaderCell('Qty', align: TextAlign.right),
              _tableHeaderCell(''),
            ],
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: scheme.primaryContainer.withValues(alpha: 0.55),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                jenisLabel,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer,
                    ),
              ),
            ),
          ),
          Table(
            columnWidths: columnWidths,
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              headerRow,
              ...rows.map((item) => _dataRow(context, item, isCompact)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(
      !showStockistActions ||
          ((branchIdForMutations ?? '').isNotEmpty && onReload != null),
      'Stockist table requires branchIdForMutations and onReload',
    );
    assert(
      !showReadOnlyHistory || (branchIdForMutations ?? '').isNotEmpty,
      'showReadOnlyHistory requires branchIdForMutations',
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      children: [
        for (final group in groupStockItemsByJenis(filteredItems))
          _jenisGroupTable(context, group.key, group.value),
      ],
    );
  }
}

class StockHistoryBottomSheet extends StatefulWidget {
  const StockHistoryBottomSheet({
    super.key,
    required this.item,
    required this.branchId,
    this.branchDisplayName,
  });

  final Map<String, dynamic> item;
  final String branchId;
  /// Nama cabang untuk tampilan (mis. dari userState.branches).
  final String? branchDisplayName;

  @override
  State<StockHistoryBottomSheet> createState() =>
      _StockHistoryBottomSheetState();
}

class _StockHistoryBundle {
  const _StockHistoryBundle({
    required this.mutations,
    required this.statusHistory,
  });

  final List<Map<String, dynamic>> mutations;
  final List<Map<String, dynamic>> statusHistory;
}

class _StockHistoryBottomSheetState extends State<StockHistoryBottomSheet> {
  late Future<_StockHistoryBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  static String _fmt(dynamic ts) {
    if (ts == null) return '-';
    try {
      return DateFormat('dd MMM yyyy, HH:mm').format(
        DateTime.parse(ts.toString()).toLocal(),
      );
    } catch (_) {
      return ts.toString();
    }
  }

  Future<_StockHistoryBundle> _load() async {
    final id = widget.item['item_id'];
    if (id == null) {
      return const _StockHistoryBundle(mutations: [], statusHistory: []);
    }
    final base = NetworkConfig.baseUrl;
    final mutUri = Uri.parse(
      '$base/stock-mutations?branch_id=${widget.branchId}&item_id=$id&limit=200',
    );
    final mut = await http.get(mutUri, headers: NetworkConfig.defaultHeaders);
    if (mut.statusCode != 200) {
      throw Exception('Gagal memuat riwayat mutasi (${mut.statusCode})');
    }
    final mutDecoded = jsonDecode(mut.body);
    final mutations = mutDecoded is List
        ? mutDecoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
        : <Map<String, dynamic>>[];

    List<Map<String, dynamic>> statusHistory = [];
    try {
      final shUri = Uri.parse('$base/items/$id/status-history');
      final sh = await http.get(shUri, headers: NetworkConfig.defaultHeaders);
      if (sh.statusCode == 200) {
        final dec = jsonDecode(sh.body);
        if (dec is List) {
          statusHistory =
              dec.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (_) {}

    return _StockHistoryBundle(
      mutations: mutations,
      statusHistory: statusHistory,
    );
  }

  static String _typeLabel(String? t) {
    switch ((t ?? '').toLowerCase()) {
      case 'in':
        return 'Masuk';
      case 'out':
        return 'Keluar';
      case 'transfer':
        return 'Transfer';
      case 'adjustment':
        return 'Koreksi';
      default:
        return t?.isNotEmpty == true ? t! : '-';
    }
  }

  static String _mutationHeadline(Map<String, dynamic> row) {
    final type = _typeLabel(row['type']?.toString());
    final rt = (row['reference_type'] ?? '').toString().trim();
    if (rt == 'item_create') return '$type · Input / pembuatan stok';
    if (rt == 'restock') return '$type · Restok';
    if (rt == 'order') return '$type · Order / transaksi';
    if (rt == 'transfer') return '$type · Antar cabang';
    return '$type · qty ${row['quantity'] ?? '-'}';
  }

  static List<Widget> _mutationDetailLines(Map<String, dynamic> row) {
    final lines = <Widget>[];
    void addLine(String text) {
      if (text.trim().isEmpty) return;
      lines.add(
        Text(
          text,
          style: TextStyle(fontSize: 11, color: Colors.grey[700], height: 1.35),
        ),
      );
    }

    final ts = _fmt(row['created_at']);
    addLine('Waktu mutasi: $ts');

    final prev = row['previous_stock'];
    final cur = row['current_stock'];
    final qty = row['quantity'];
    if (prev != null || cur != null) {
      addLine('Stok: ${prev ?? '?'} → ${cur ?? '?'} (qty catat: $qty)');
    }

    final branch = (row['branch_name'] ?? '').toString().trim();
    if (branch.isNotEmpty) {
      addLine('Cabang: $branch');
    }

    final by = (row['created_by_name'] ?? '').toString().trim();
    final rt = (row['reference_type'] ?? '').toString().trim();

    if (rt == 'order') {
      final ot = (row['order_type'] ?? '').toString().trim();
      final on = (row['order_number'] ?? '').toString().trim();
      if (ot.isNotEmpty || on.isNotEmpty) {
        addLine('Order: ${ot.isNotEmpty ? ot : '-'}${on.isNotEmpty ? ' · $on' : ''}');
      }
      final ots = row['order_created_at'];
      if (ots != null) {
        addLine('Waktu order: ${_fmt(ots)}');
      }
      final cn = (row['customer_name'] ?? '').toString().trim();
      final cp = (row['customer_phone'] ?? '').toString().trim();
      if (cn.isNotEmpty) {
        addLine('Pelanggan: $cn${cp.isNotEmpty ? ' · $cp' : ''}');
      }
      final cashier = (row['order_user_name'] ?? '').toString().trim();
      if (cashier.isNotEmpty) {
        addLine('Kasir / input order: $cashier');
      }
      final oid = row['reference_id'];
      if (oid != null) {
        addLine('ID order: #$oid');
      }
    } else if (rt == 'transfer') {
      final fromN = (row['transfer_from_branch_name'] ?? '').toString().trim();
      final toN = (row['transfer_to_branch_name'] ?? '').toString().trim();
      if (fromN.isNotEmpty || toN.isNotEmpty) {
        addLine('Rute: $fromN → $toN');
      }
      final appr = (row['transfer_approved_by_username'] ?? '').toString().trim();
      if (appr.isNotEmpty) {
        addLine('Disetujui oleh: $appr');
      }
      final tid = row['reference_id'];
      if (tid != null) {
        addLine('ID transfer: #$tid');
      }
    } else if (rt == 'item_create' || rt == 'restock') {
      if (by.isNotEmpty) {
        addLine('Oleh: $by');
      }
    } else {
      if (by.isNotEmpty) {
        addLine('Oleh: $by');
      }
    }

    final notes = (row['notes'] ?? '').toString().trim();
    if (notes.isNotEmpty) {
      addLine('Catatan: $notes');
    }

    if (rt.isNotEmpty && rt != 'order' && rt != 'transfer') {
      addLine('Jenis referensi: $rt');
    }

    return lines;
  }

  Widget _originCard(BuildContext context) {
    final it = widget.item;
    final created = _fmt(it['created_at']);
    final updated = _fmt(it['updated_at']);
    final src = (it['source'] ?? '-').toString();
    final by = (it['item_created_by_name'] ?? '').toString().trim();
    final bid = (it['branch_id'] ?? widget.branchId).toString();
    final status = (it['status'] ?? '-').toString();
    final ownership = (it['ownership'] ?? '').toString().trim();
    final stockType = (it['stock_type'] ?? '').toString().trim();
    final bName = (widget.branchDisplayName ?? '').trim();
    final branchLine = bName.isNotEmpty
        ? 'Cabang: $bName (ID $bid)'
        : 'Cabang (ID): $bid';

    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Data awal (master item)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            Text('Pertama dicatat: $created', style: _originStyle),
            if (updated != created && it['updated_at'] != null)
              Text('Terakhir diubah (meta): $updated', style: _originStyle),
            Text('Sumber input: $src', style: _originStyle),
            if (by.isNotEmpty)
              Text('Diinput oleh: $by', style: _originStyle)
            else
              Text(
                'Diinput oleh: — (belum tercatat / data lama)',
                style: _originStyle,
              ),
            Text(branchLine, style: _originStyle),
            Text('Status saat ini: $status', style: _originStyle),
            if (ownership.isNotEmpty)
              Text('Kepemilikan: $ownership', style: _originStyle),
            if (stockType.isNotEmpty)
              Text('Tipe stok: $stockType', style: _originStyle),
          ],
        ),
      ),
    );
  }

  static TextStyle get _originStyle =>
      TextStyle(fontSize: 12, color: Colors.grey[800], height: 1.35);

  @override
  Widget build(BuildContext context) {
    final kode =
        (widget.item['kode_produk'] ?? widget.item['item_code'] ?? '')
            .toString();
    final name = (widget.item['name'] ?? '-').toString();
    final subtitle = kode.isNotEmpty ? '$kode · $name' : name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Riwayat stok',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Muat ulang',
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Tutup',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<_StockHistoryBundle>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                );
              }
              final bundle = snapshot.data ??
                  const _StockHistoryBundle(mutations: [], statusHistory: []);
              final rows = bundle.mutations;
              final st = bundle.statusHistory;

              return ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  _originCard(context),
                  if (st.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: Text(
                        'Perubahan status',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    ...st.map((h) {
                      final when = _fmt(h['created_at']);
                      final oldS = (h['old_status'] ?? '-').toString();
                      final newS = (h['new_status'] ?? '-').toString();
                      final actor =
                          (h['changed_by_name'] ?? '').toString().trim();
                      final note = (h['notes'] ?? '').toString().trim();
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: ListTile(
                          dense: true,
                          title: Text(
                            '$oldS → $newS',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                when,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[700],
                                ),
                              ),
                              if (actor.isNotEmpty)
                                Text(
                                  'Oleh: $actor',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              if (note.isNotEmpty)
                                Text(
                                  note,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Text(
                      'Mutasi quantity & referensi',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Belum ada mutasi tercatat (penjualan, transfer, restok akan muncul di sini).',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ...rows.map((row) {
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _mutationHeadline(row),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ..._mutationDetailLines(row),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
