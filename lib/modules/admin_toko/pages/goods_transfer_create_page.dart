import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/responsive_form_row.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

/// Form kirim barang antar cabang (dulu dialog di [GoodsTransferPage]).
class GoodsTransferCreatePage extends ConsumerStatefulWidget {
  const GoodsTransferCreatePage({
    super.key,
    required this.branches,
    required this.fromBranchId,
  });

  final List<dynamic> branches;
  final dynamic fromBranchId;

  @override
  ConsumerState<GoodsTransferCreatePage> createState() =>
      _GoodsTransferCreatePageState();
}

class _GoodsTransferCreatePageState
    extends ConsumerState<GoodsTransferCreatePage> {
  final _formKey = GlobalKey<FormState>();
  int? _selectedBranchId;
  String _selectedSourceType = 'stok';
  final _notesController = TextEditingController();
  final _courierController = TextEditingController();
  final _lines = <_TransferLine>[_TransferLine()];
  bool _submitting = false;
  bool _isLoadingItems = false;
  String _itemsError = '';
  List<Map<String, dynamic>> _availableItems = [];

  @override
  void initState() {
    super.initState();
    _loadAvailableItems();
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

  List<Map<String, dynamic>> get _destinationBranches {
    final from = widget.fromBranchId?.toString();
    return widget.branches
        .where((b) {
          final id = b['branch_id']?.toString();
          return id != null && id != from;
        })
        .map((b) => Map<String, dynamic>.from(b as Map))
        .toList();
  }

  Future<void> _loadAvailableItems() async {
    setState(() {
      _isLoadingItems = true;
      _itemsError = '';
      _availableItems = [];
      for (final l in _lines) {
        l.selectedItem = null;
        l.autocompleteTextController?.clear();
      }
    });

    try {
      final status = _selectedSourceType == 'buyback' ? 'buyback' : 'ready';
      final uri = Uri.parse(
        '${NetworkConfig.baseUrl}/items?branch_id=${widget.fromBranchId}&status=$status&in_stock_only=1&limit=200',
      );
      final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
      if (resp.statusCode != 200) {
        setState(() {
          _itemsError = 'Gagal memuat item ($status): ${resp.statusCode}';
          _isLoadingItems = false;
        });
        return;
      }

      final decoded = jsonDecode(resp.body);
      final list = decoded is List ? decoded : <dynamic>[];
      final mapped = list
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .where((it) {
            final q = it['quantity'];
            final qty = q is int ? q : int.tryParse(q?.toString() ?? '') ?? 0;
            return qty > 0;
          })
          .toList();

      if (!mounted) return;
      setState(() {
        _availableItems = mapped;
        _isLoadingItems = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _itemsError = 'Error: $e';
        _isLoadingItems = false;
      });
    }
  }

  void _setSourceType(String type) {
    if (_selectedSourceType == type) return;
    setState(() => _selectedSourceType = type);
    _loadAvailableItems();
  }

  static String _itemLabel(Map<String, dynamic> it) {
    final code = (it['item_code'] ?? it['kode_produk'] ?? '').toString();
    final name = (it['name'] ?? it['item_name'] ?? '').toString();
    if (code.isNotEmpty && name.isNotEmpty) return '$code - $name';
    return name.isNotEmpty ? name : code;
  }

  static String _itemNameForApi(Map<String, dynamic> it) {
    final name = (it['name'] ?? it['item_name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    return _itemLabel(it);
  }

  int _stockQty(Map<String, dynamic>? it) {
    if (it == null) return 0;
    final q = it['quantity'];
    if (q is int) return q;
    return int.tryParse(q?.toString() ?? '') ?? 0;
  }

  Future<bool> _createTransfer({
    required int toBranchId,
    required String itemName,
    required int quantity,
    required String courier,
    required String notes,
  }) async {
    final userState = ref.read(userStateProvider);
    final resp = await http.post(
      Uri.parse('${NetworkConfig.baseUrl}/transfers'),
      headers: NetworkConfig.defaultHeaders,
      body: jsonEncode({
        'from_branch_id': widget.fromBranchId,
        'to_branch_id': toBranchId,
        'item_name': itemName,
        'quantity': quantity,
        'source_type': _selectedSourceType,
        'courier': courier,
        'notes': notes.isEmpty ? null : notes,
        'created_by': userState.userId,
      }),
    );
    return resp.statusCode == 201 || resp.statusCode == 200;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final dest = _selectedBranchId;
    if (dest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih cabang tujuan')),
      );
      return;
    }

    final courier = _courierController.text.trim();
    if (courier.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kurir wajib diisi')),
      );
      return;
    }

    final values = <_TransferLineValue>[];
    for (final line in _lines) {
      final item = line.selectedItem;
      if (item == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pastikan semua baris item terisi')),
        );
        return;
      }
      final qty = int.tryParse(line.qtyController.text.trim()) ?? 0;
      if (qty <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Qty harus lebih dari 0')),
        );
        return;
      }
      final stock = _stockQty(item);
      if (qty > stock) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Qty melebihi stok ($stock)')),
        );
        return;
      }
      values.add(
        _TransferLineValue(itemName: _itemNameForApi(item), qty: qty),
      );
    }

    setState(() => _submitting = true);
    final notes = _notesController.text.trim();
    var okCount = 0;
    for (final v in values) {
      final ok = await _createTransfer(
        toBranchId: dest,
        itemName: v.itemName,
        quantity: v.qty,
        courier: courier,
        notes: notes,
      );
      if (ok) {
        okCount++;
      } else {
        break;
      }
    }

    if (!mounted) return;
    setState(() => _submitting = false);

    if (okCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal membuat transfer')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          okCount == values.length
              ? 'Transfer berhasil dibuat ($okCount item)'
              : 'Sebagian transfer gagal ($okCount/${values.length} berhasil)',
        ),
      ),
    );
    Navigator.pop(context, true);
  }

  Widget _sourceButtons(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sumber barang',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            final stack = c.maxWidth < 400;
            final stok = _SourceChoiceButton(
              label: 'Dari stok',
              icon: Icons.inventory_2_outlined,
              selected: _selectedSourceType == 'stok',
              onTap: () => _setSourceType('stok'),
            );
            final buyback = _SourceChoiceButton(
              label: 'Dari buyback',
              icon: Icons.swap_horiz_outlined,
              selected: _selectedSourceType == 'buyback',
              onTap: () => _setSourceType('buyback'),
            );
            if (stack) {
              return Column(
                children: [
                  stok,
                  const SizedBox(height: 10),
                  buyback,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: stok),
                const SizedBox(width: 10),
                Expanded(child: buyback),
              ],
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          _selectedSourceType == 'buyback'
              ? 'Menampilkan item status buyback.'
              : 'Menampilkan item stok ready.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildItemRow(int idx, _TransferLine line) {
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
                  key: ValueKey('line-$idx-$_selectedSourceType'),
                  displayStringForOption: _itemLabel,
                  optionsBuilder: (value) {
                    final q = value.text.trim().toLowerCase();
                    if (q.isEmpty) return _availableItems.take(30);
                    return _availableItems
                        .where(
                          (it) => _itemLabel(it).toLowerCase().contains(q),
                        )
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
                    return TextFormField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        hintText: 'Ketik item',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        helperText: line.selectedItem == null
                            ? 'Ketik untuk cari item'
                            : 'Stok: ${_stockQty(line.selectedItem)}',
                      ),
                      validator: (_) {
                        if (line.selectedItem == null) {
                          return 'Pilih item';
                        }
                        return null;
                      },
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
                child: TextFormField(
                  controller: line.qtyController,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: '1',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null || n <= 0) return '>';
                    final stock = _stockQty(line.selectedItem);
                    if (line.selectedItem != null && n > stock) {
                      return 'max $stock';
                    }
                    return null;
                  },
                ),
              ),
              IconButton(
                tooltip: 'Hapus baris',
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
          if (idx != _lines.length - 1) const Divider(height: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinations = _destinationBranches;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Kirim Barang'),
      ),
      body: Form(
        key: _formKey,
        child: Column(
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
                    DropdownButtonFormField<int>(
                      key: ValueKey('dest_$_selectedBranchId'),
                      initialValue: _selectedBranchId,
                      isExpanded: true,
                      menuMaxHeight: 320,
                      decoration: const InputDecoration(
                        labelText: 'Cabang Tujuan',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      hint: const Text('Pilih cabang'),
                      items: destinations.map((b) {
                        final rawId = b['branch_id'];
                        final id = rawId is int
                            ? rawId
                            : int.tryParse(rawId?.toString() ?? '');
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(
                            (b['name'] ?? 'Cabang $id').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      selectedItemBuilder: (context) {
                        return destinations.map((b) {
                          return Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              (b['name'] ?? b['branch_id'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList();
                      },
                      onChanged: destinations.isEmpty
                          ? null
                          : (v) => setState(() => _selectedBranchId = v),
                      validator: (v) =>
                          v == null ? 'Pilih cabang tujuan' : null,
                    ),
                    const SizedBox(height: 16),
                    _sourceButtons(context),
                    const SizedBox(height: 16),
                    if (_itemsError.isNotEmpty)
                      Text(_itemsError, style: TextStyle(color: cs.error))
                    else if (_isLoadingItems)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Daftar Item',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
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
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.6),
                          ),
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
                                    child: Center(child: Text('Qty')),
                                  ),
                                  SizedBox(width: 48),
                                ],
                              ),
                            ),
                            const Divider(height: 10),
                            ..._lines.asMap().entries.map(
                                  (e) => _buildItemRow(e.key, e.value),
                                ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Catatan (opsional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _courierController,
                      decoration: const InputDecoration(
                        labelText: 'Kurir',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Kurir wajib diisi';
                        }
                        return null;
                      },
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
                    onPressed: _submitting || _isLoadingItems ? null : _submit,
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
        ),
      ),
    );
  }
}

class _SourceChoiceButton extends StatelessWidget {
  const _SourceChoiceButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: AppTypography.bodySmall,
                  color: selected ? cs.onPrimaryContainer : cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransferLine {
  final TextEditingController qtyController = TextEditingController(text: '1');
  Map<String, dynamic>? selectedItem;
  TextEditingController? autocompleteTextController;

  void dispose() {
    qtyController.dispose();
  }
}

class _TransferLineValue {
  final String itemName;
  final int qty;
  const _TransferLineValue({required this.itemName, required this.qty});
}
