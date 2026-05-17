import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/responsive_form_row.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/responsive_layout.dart';
import 'package:vanessa3/utils/surat_jalan_print.dart';
import 'package:vanessa3/widgets/qr_scan_route.dart';

/// Form kirim barang warehouse → toko (dulu dialog di [KirimKeTokoPage]).
class KirimKeTokoCreatePage extends ConsumerStatefulWidget {
  const KirimKeTokoCreatePage({super.key, required this.branches});

  final List<dynamic> branches;

  @override
  ConsumerState<KirimKeTokoCreatePage> createState() =>
      _KirimKeTokoCreatePageState();
}

class _KirimKeTokoCreatePageState extends ConsumerState<KirimKeTokoCreatePage> {
  String? _toBranchId;
  final _notesController = TextEditingController();
  final _courierController = TextEditingController();
  final _lines = <_TransferLine>[_TransferLine()];
  bool _submitting = false;

  late final Future<List<Map<String, dynamic>>> _warehouseItemsFuture;

  @override
  void initState() {
    super.initState();
    _warehouseItemsFuture = _loadWarehouseItems();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _courierController.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> get _availableBranches {
    final userBranch = ref.read(userStateProvider).branch.toString();
    return widget.branches.where((b) {
      final id = b['branch_id']?.toString();
      return id != null && id != userBranch;
    }).map((b) => Map<String, dynamic>.from(b as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> _loadWarehouseItems() async {
    final warehouseId = ref.read(userStateProvider).branch.toString();
    final baseUrl = NetworkConfig.baseUrl;

    Future<List<Map<String, dynamic>>> fetch(String url) async {
      final resp = await http.get(
        Uri.parse(url),
        headers: NetworkConfig.defaultHeaders,
      );
      if (resp.statusCode != 200) {
        throw Exception(
          'Gagal memuat stok (branch $warehouseId) (${resp.statusCode})',
        );
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }

    final withStockType = await fetch(
      '$baseUrl/items?branch_id=$warehouseId&stock_type=inventory&limit=200',
    );
    if (withStockType.isNotEmpty) return withStockType;
    return fetch('$baseUrl/items?branch_id=$warehouseId&limit=200');
  }

  static String _itemLabel(Map<String, dynamic> it) {
    final code = (it['item_code'] ?? it['kode_produk'] ?? '').toString();
    final name = (it['name'] ?? it['item_name'] ?? '').toString();
    if (code.isNotEmpty && name.isNotEmpty) return '$code - $name';
    return name.isNotEmpty ? name : code;
  }

  Future<Map<String, dynamic>?> _createTransfer({
    required String toBranchId,
    required String itemName,
    required int quantity,
    required String courier,
    String notes = '',
  }) async {
    final userState = ref.read(userStateProvider);
    final baseUrl = NetworkConfig.baseUrl;

    final resp = await http.post(
      Uri.parse('$baseUrl/transfers'),
      headers: NetworkConfig.defaultHeaders,
      body: jsonEncode({
        'from_branch_id': userState.branch,
        'to_branch_id': toBranchId,
        'item_name': itemName,
        'quantity': quantity,
        'courier': courier,
        'notes': notes,
        'created_by': userState.userId,
      }),
    );

    if (resp.statusCode == 201) {
      final created = jsonDecode(resp.body);
      return created is Map ? Map<String, dynamic>.from(created) : <String, dynamic>{};
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal membuat transfer (${resp.statusCode}): ${resp.body}'),
        ),
      );
    }
    return null;
  }

  Future<void> _submit(List<Map<String, dynamic>> items) async {
    final dest = _toBranchId;
    if (dest == null || dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih cabang tujuan')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    final courier = _courierController.text.trim();
    if (courier.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kurir wajib diisi')),
      );
      return;
    }

    final values = <_TransferLineValue>[];
    for (final line in _lines) {
      final selected = line.selectedItem;
      final itemName =
          selected == null ? '' : _itemLabel(selected).trim();
      final qty = int.tryParse(line.qtyController.text.trim()) ?? 0;

      if (selected == null || itemName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pastikan semua item dipilih')),
        );
        return;
      }
      if (qty <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Qty harus lebih dari 0')),
        );
        return;
      }

      final stockQty = () {
        final q = selected['quantity'];
        if (q is int) return q;
        return int.tryParse(q?.toString() ?? '');
      }();
      if (stockQty != null && qty > stockQty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Qty melebihi stok tersedia ($stockQty)')),
        );
        return;
      }

      values.add(_TransferLineValue(itemName: itemName, qty: qty));
    }

    setState(() => _submitting = true);
    final created = <Map<String, dynamic>>[];
    for (final l in values) {
      final res = await _createTransfer(
        toBranchId: dest,
        itemName: l.itemName,
        quantity: l.qty,
        courier: courier,
        notes: _notesController.text.trim(),
      );
      if (res == null) break;
      created.add(res);
    }

    if (!mounted) return;
    setState(() => _submitting = false);

    if (created.isEmpty) return;

    final userState = ref.read(userStateProvider);
    final toName = _availableBranches
        .cast<Map<String, dynamic>>()
        .firstWhere(
          (b) => b['branch_id']?.toString() == dest,
          orElse: () => <String, dynamic>{},
        )['name']
        ?.toString();
    final fromName = userState.branches
        .cast<Map<String, dynamic>>()
        .where((b) => b['branch_id']?.toString() == userState.branch.toString())
        .map((b) => b['name']?.toString())
        .whereType<String>()
        .cast<String?>()
        .firstWhere((x) => x != null, orElse: () => null);

    await printSuratJalanTransfers(
      context,
      transfers: created,
      fromBranchName: fromName ?? 'Cabang ${userState.branch}',
      toBranchName: toName ?? 'Cabang $dest',
      fromBranchIdForLogo: userState.branch.toString().trim(),
      toBranchIdForLogo: dest.trim(),
      courier: courier,
      notes: _notesController.text.trim(),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transfer berhasil dibuat')),
    );
    Navigator.pop(context, true);
  }

  Future<void> _scanAndApplyItem(
    _TransferLine line,
    List<Map<String, dynamic>> items,
  ) async {
    final scanned = await pushQrScanPage(context);
    if (scanned == null || scanned.trim().isEmpty) return;

    final raw = scanned.trim();
    final candidate = raw
        .split('\n')
        .first
        .trim()
        .split(RegExp(r'\s*[-–]\s*'))
        .first
        .trim();
    final normalized = candidate.toLowerCase();

    Map<String, dynamic>? match;
    for (final it in items) {
      final code = (it['item_code'] ?? it['kode_produk'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (code.isNotEmpty && code == normalized) {
        match = it;
        break;
      }
    }

    match ??= items.cast<Map<String, dynamic>?>().firstWhere(
      (it) {
        if (it == null) return false;
        final label = _itemLabel(it).toLowerCase();
        return label == raw.toLowerCase() || label.contains(normalized);
      },
      orElse: () => null,
    );

    if (match == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Item tidak ditemukan di stok: $candidate')),
      );
      return;
    }

    setState(() {
      line.selectedItem = match;
      line.autocompleteTextController?.text = _itemLabel(match!);
    });
    line.autocompleteFocusNode?.unfocus();
  }

  Widget _buildItemRow(
    int idx,
    _TransferLine line,
    List<Map<String, dynamic>> items,
  ) {
    final selected = line.selectedItem;
    int? stockQty() {
      final q = selected?['quantity'];
      if (q is int) return q;
      return int.tryParse(q?.toString() ?? '');
    }

    return Padding(
      padding: EdgeInsets.only(bottom: idx == _lines.length - 1 ? 0 : 10),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text('${idx + 1}.'),
                ),
              ),
              Expanded(
                child: Autocomplete<Map<String, dynamic>>(
                  displayStringForOption: _itemLabel,
                  optionsBuilder: (value) {
                    final q = value.text.trim().toLowerCase();
                    if (q.isEmpty) return items.take(30);
                    return items
                        .where((it) => _itemLabel(it).toLowerCase().contains(q))
                        .take(30);
                  },
                  onSelected: (it) {
                    setState(() {
                      line.selectedItem = it;
                      line.autocompleteTextController?.text = _itemLabel(it);
                    });
                  },
                  fieldViewBuilder: (
                    context,
                    textEditingController,
                    focusNode,
                    onFieldSubmitted,
                  ) {
                    line.autocompleteTextController = textEditingController;
                    line.autocompleteFocusNode = focusNode;
                    return TextField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        hintText: 'Ketik item',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          tooltip: 'Scan QR',
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: () => _scanAndApplyItem(line, items),
                        ),
                      ),
                      onChanged: (_) {
                        if (line.selectedItem != null) {
                          setState(() => line.selectedItem = null);
                        }
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 74,
                child: TextField(
                  controller: line.qtyController,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: '1',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Hapus item',
                onPressed: _lines.length <= 1
                    ? null
                    : () {
                        setState(() {
                          line.dispose();
                          _lines.removeAt(idx);
                        });
                      },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (selected != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Stok tersedia: ${stockQty() ?? '-'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          if (idx != _lines.length - 1) const Divider(height: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final available = _availableBranches;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Kirim ke Toko'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _warehouseItemsFuture,
        builder: (context, snapshot) {
          final isLoading = snapshot.connectionState == ConnectionState.waiting;
          final items = snapshot.data ?? <Map<String, dynamic>>[];
          final error =
              snapshot.hasError ? snapshot.error.toString() : null;

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: ResponsiveLayout.pagePadding(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        key: ValueKey<String>('to_branch_$_toBranchId'),
                        initialValue: _toBranchId,
                        isExpanded: true,
                        menuMaxHeight: 320,
                        decoration: const InputDecoration(
                          labelText: 'Tujuan (Cabang)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        hint: const Text('Pilih cabang'),
                        items: available.map((b) {
                          final id = b['branch_id'].toString();
                          final name = (b['name'] ?? id).toString();
                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        selectedItemBuilder: (context) {
                          return available.map((b) {
                            final name =
                                (b['name'] ?? b['branch_id'] ?? '').toString();
                            return Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList();
                        },
                        onChanged: available.isEmpty
                            ? null
                            : (v) => setState(() => _toBranchId = v),
                      ),
                      const SizedBox(height: 16),
                      if (error != null)
                        Text(error, style: const TextStyle(color: Colors.red))
                      else if (isLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else ...[
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Daftar Item',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setState(() => _lines.add(_TransferLine()));
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Tambah item'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                          child: Column(
                            children: [
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Row(
                                  children: [
                                    SizedBox(width: 28, child: Text('#')),
                                    Expanded(child: Text('Item')),
                                    SizedBox(
                                      width: 74,
                                      child: Align(
                                        alignment: Alignment.center,
                                        child: Text('Qty'),
                                      ),
                                    ),
                                    SizedBox(width: 48),
                                  ],
                                ),
                              ),
                              const Divider(height: 10),
                              ..._lines.asMap().entries.map(
                                    (e) => _buildItemRow(e.key, e.value, items),
                                  ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'Catatan (opsional)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        minLines: 1,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _courierController,
                        decoration: const InputDecoration(
                          labelText: 'Kurir',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: ResponsiveLayout.pagePadding(context).copyWith(top: 8),
                  child: ResponsiveDualActions(
                    secondary: OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Batal'),
                    ),
                    primary: FilledButton(
                      onPressed: _submitting || isLoading || error != null
                          ? null
                          : () => _submit(items),
                      child: _submitting
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Kirim'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TransferLine {
  final TextEditingController qtyController = TextEditingController(text: '1');
  Map<String, dynamic>? selectedItem;
  TextEditingController? autocompleteTextController;
  FocusNode? autocompleteFocusNode;

  void dispose() {
    qtyController.dispose();
  }
}

class _TransferLineValue {
  final String itemName;
  final int qty;
  const _TransferLineValue({required this.itemName, required this.qty});
}
