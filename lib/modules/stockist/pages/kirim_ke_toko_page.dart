import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/widgets/qr_scan_route.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/surat_jalan_print.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

String _kurirLabelDariTransfer(Map<String, dynamic> t) {
  for (final k in <String>['courier', 'kurir']) {
    final v = t[k];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isNotEmpty) return s;
  }
  return '-';
}

class KirimKeTokoPage extends ConsumerStatefulWidget {
  const KirimKeTokoPage({super.key});

  @override
  ConsumerState<KirimKeTokoPage> createState() => _KirimKeTokoPageState();
}

class _KirimKeTokoPageState extends ConsumerState<KirimKeTokoPage> {
  List<dynamic> _transfers = [];
  List<dynamic> _branches = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<String?> _scanQrCode(BuildContext context) {
    return pushQrScanPage(context);
  }

  List<dynamic> _decodeJsonList(http.Response resp) {
    final decoded = jsonDecode(resp.body);
    if (decoded is! List) return <dynamic>[];
    return decoded;
  }

  /// GET /branches lalu GET /api/branches jika status bukan 200 (proxy, skema DB, dll).
  Future<http.Response> _fetchBranchesList(String baseUrl) async {
    final primary = await http.get(
      Uri.parse('$baseUrl/branches'),
      headers: NetworkConfig.defaultHeaders,
    );
    if (primary.statusCode == 200) return primary;
    final fallback = await http.get(
      Uri.parse('$baseUrl/api/branches'),
      headers: NetworkConfig.defaultHeaders,
    );
    if (fallback.statusCode == 200) return fallback;
    return primary;
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;

      final transfersResp = await http.get(
        Uri.parse(
          '$baseUrl/transfers?branch_id=${userState.branch}&type=outgoing',
        ),
        headers: NetworkConfig.defaultHeaders,
      );
      final branchesResp = await _fetchBranchesList(baseUrl);

      if (transfersResp.statusCode != 200) {
        setState(() {
          _error =
              'Gagal memuat transfer (${transfersResp.statusCode}). Cabang: ${branchesResp.statusCode}.';
          _isLoading = false;
        });
        return;
      }
      if (branchesResp.statusCode != 200) {
        setState(() {
          _error =
              'Gagal memuat daftar cabang (${branchesResp.statusCode}). Transfer: ${transfersResp.statusCode}.';
          _isLoading = false;
        });
        return;
      }

      final transfersData = jsonDecode(transfersResp.body);
      final branchesList = _decodeJsonList(branchesResp);
      setState(() {
        _transfers = (transfersData is List) ? transfersData : <dynamic>[];
        _branches = branchesList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
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

    try {
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

      if (!mounted) return null;
      if (resp.statusCode == 201) {
        final created = jsonDecode(resp.body);
        await _loadData();
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transfer berhasil dibuat')),
        );
        return created is Map
            ? Map<String, dynamic>.from(created)
            : <String, dynamic>{};
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal membuat transfer (${resp.statusCode}): ${resp.body}'),
          ),
        );
        return null;
      }
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _createTransfersBatch({
    required String toBranchId,
    required List<_TransferLineValue> lines,
    required String courier,
    String notes = '',
  }) async {
    final created = <Map<String, dynamic>>[];
    for (final l in lines) {
      final res = await _createTransfer(
        toBranchId: toBranchId,
        itemName: l.itemName,
        quantity: l.qty,
        courier: courier,
        notes: notes,
      );
      if (res == null) break;
      created.add(res);
    }
    return created;
  }

  void _showCreateTransferDialog() {
    final userState = ref.read(userStateProvider);
    String? toBranchId;
    final notesController = TextEditingController();
    final courierController = TextEditingController();
    final baseUrl = NetworkConfig.baseUrl;
    final lines = <_TransferLine>[
      _TransferLine(),
    ];

    final availableBranches = _branches.where((b) {
      final id = b['branch_id']?.toString();
      return id != null && id != userState.branch;
    }).toList();

    Future<List<Map<String, dynamic>>> loadWarehouseItems() async {
      final warehouseId = userState.branch.toString();

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

      // Prefer stock_type filter if backend supports it, but fallback gracefully.
      final withStockType = await fetch(
        '$baseUrl/items?branch_id=$warehouseId&stock_type=inventory&limit=200',
      );
      if (withStockType.isNotEmpty) return withStockType;

      // Fallback: load all items for the current branch.
      return fetch('$baseUrl/items?branch_id=$warehouseId&limit=200');
    }
    final warehouseItemsFuture = loadWarehouseItems();

    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: warehouseItemsFuture,
          builder: (context, snapshot) {
            final isLoading = snapshot.connectionState == ConnectionState.waiting;
            final items = snapshot.data ?? <Map<String, dynamic>>[];
            final error = snapshot.hasError ? snapshot.error.toString() : null;

            String itemLabel(Map<String, dynamic> it) {
              final code = (it['item_code'] ?? it['kode_produk'] ?? '').toString();
              final name = (it['name'] ?? it['item_name'] ?? '').toString();
              if (code.isNotEmpty && name.isNotEmpty) return '$code - $name';
              return name.isNotEmpty ? name : code;
            }

            return StatefulBuilder(
              builder: (context, setDialogState) {
                final mq = MediaQuery.sizeOf(context);
                final maxW = (mq.width - 48).clamp(280.0, 520.0);
                final maxH = mq.height * 0.72;
                return AlertDialog(
                  title: const Text('Kirim ke Toko'),
                  content: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButtonFormField<String>(
                            key: ValueKey(toBranchId ?? '__none__'),
                            initialValue: toBranchId,
                            isExpanded: true,
                            menuMaxHeight: 320,
                            decoration: const InputDecoration(
                              labelText: 'Tujuan (Cabang)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            hint: const Text('Pilih cabang'),
                            items: availableBranches.map((b) {
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
                              return availableBranches.map((b) {
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
                            onChanged: availableBranches.isEmpty
                                ? null
                                : (v) => setDialogState(() => toBranchId = v),
                          ),
                          const SizedBox(height: 12),
                          if (error != null)
                            Text(
                              error,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.red),
                            )
                          else if (isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: LinearProgressIndicator(),
                            )
                          else
                            Column(
                              children: [
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
                                        setDialogState(() => lines.add(_TransferLine()));
                                      },
                                      icon: const Icon(Icons.add),
                                      label: const Text('Tambah item'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
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
                                            SizedBox(width: 38),
                                          ],
                                        ),
                                      ),
                                      const Divider(height: 10),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          minHeight: 110,
                                          maxHeight: 300,
                                        ),
                                        child: SingleChildScrollView(
                                          child: Column(
                                            children: [
                                              ...lines.asMap().entries.map((entry) {
                                                final idx = entry.key;
                                                final line = entry.value;
                                                final selected = line.selectedItem;
                                                int? stockQty() {
                                                  final q = selected?['quantity'];
                                                  if (q is int) return q;
                                                  return int.tryParse(q?.toString() ?? '');
                                                }

                                                return Padding(
                                                  padding: EdgeInsets.only(
                                                    bottom:
                                                        idx == lines.length - 1 ? 0 : 10,
                                                  ),
                                                  child: Column(
                                                    children: [
                                                      Row(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment.start,
                                                        children: [
                                                          SizedBox(
                                                            width: 28,
                                                            child: Padding(
                                                              padding:
                                                                  const EdgeInsets.only(
                                                                top: 14,
                                                              ),
                                                              child: Text('${idx + 1}.'),
                                                            ),
                                                          ),
                                                          Expanded(
                                                            child: Autocomplete<
                                                                Map<String, dynamic>>(
                                                              displayStringForOption: (it) =>
                                                                  itemLabel(it),
                                                              optionsBuilder: (value) {
                                                                final q = value.text
                                                                    .trim()
                                                                    .toLowerCase();
                                                                if (q.isEmpty) {
                                                                  return items.take(30);
                                                                }
                                                                return items.where((it) {
                                                                  final label = itemLabel(it)
                                                                      .toLowerCase();
                                                                  return label.contains(q);
                                                                }).take(30);
                                                              },
                                                              onSelected: (it) {
                                                                setDialogState(() {
                                                                  line.selectedItem = it;
                                                                  line.autocompleteTextController
                                                                          ?.text =
                                                                      itemLabel(it);
                                                                });
                                                              },
                                                              fieldViewBuilder: (
                                                                context,
                                                                textEditingController,
                                                                focusNode,
                                                                onFieldSubmitted,
                                                              ) {
                                                                line.autocompleteTextController =
                                                                    textEditingController;
                                                                line.autocompleteFocusNode =
                                                                    focusNode;
                                                                final selectedLabel =
                                                                    selected == null
                                                                    ? ''
                                                                    : itemLabel(
                                                                        selected,
                                                                      );
                                                                if (selectedLabel
                                                                        .isNotEmpty &&
                                                                    textEditingController
                                                                            .text !=
                                                                        selectedLabel &&
                                                                    !focusNode.hasFocus) {
                                                                  textEditingController
                                                                      .value = textEditingController
                                                                      .value
                                                                      .copyWith(
                                                                        text:
                                                                            selectedLabel,
                                                                        selection:
                                                                            TextSelection.collapsed(
                                                                          offset:
                                                                              selectedLabel.length,
                                                                        ),
                                                                        composing:
                                                                            TextRange.empty,
                                                                      );
                                                                }
                                                                return TextField(
                                                                  controller:
                                                                      textEditingController,
                                                                  focusNode: focusNode,
                                                                  decoration:
                                                                      InputDecoration(
                                                                        hintText:
                                                                            'Ketik item',
                                                                        border:
                                                                            const OutlineInputBorder(),
                                                                        isDense: true,
                                                                        suffixIcon:
                                                                            IconButton(
                                                                          tooltip:
                                                                              'Scan QR',
                                                                          icon: const Icon(
                                                                            Icons.qr_code_scanner,
                                                                          ),
                                                                          onPressed:
                                                                              () async {
                                                                            final scanned = await _scanQrCode(
                                                                              context,
                                                                            );
                                                                            if (scanned ==
                                                                                    null ||
                                                                                scanned
                                                                                    .trim()
                                                                                    .isEmpty) {
                                                                              return;
                                                                            }

                                                                            final raw = scanned
                                                                                .trim();
                                                                            final candidate = raw
                                                                                .split(
                                                                                  '\n',
                                                                                )
                                                                                .first
                                                                                .trim()
                                                                                .split(
                                                                                  RegExp(
                                                                                    r'\s*[-–]\s*',
                                                                                  ),
                                                                                )
                                                                                .first
                                                                                .trim();
                                                                            final normalized =
                                                                                candidate.toLowerCase();

                                                                            Map<String, dynamic>?
                                                                            match;
                                                                            for (final it
                                                                                in items) {
                                                                              final code =
                                                                                  (it['item_code'] ??
                                                                                          it['kode_produk'] ??
                                                                                          '')
                                                                                      .toString()
                                                                                      .trim()
                                                                                      .toLowerCase();
                                                                              if (code
                                                                                      .isNotEmpty &&
                                                                                  code ==
                                                                                      normalized) {
                                                                                match = it;
                                                                                break;
                                                                              }
                                                                            }

                                                                            match ??= items
                                                                                .cast<
                                                                                    Map<String, dynamic>?>()
                                                                                .firstWhere(
                                                                                  (
                                                                                    it,
                                                                                  ) {
                                                                                    if (it ==
                                                                                        null) {
                                                                                      return false;
                                                                                    }
                                                                                    final label =
                                                                                        itemLabel(
                                                                                          it,
                                                                                        ).toLowerCase();
                                                                                    return label ==
                                                                                            raw.toLowerCase() ||
                                                                                        label.contains(
                                                                                          normalized,
                                                                                        );
                                                                                  },
                                                                                  orElse:
                                                                                      () =>
                                                                                          null,
                                                                                );

                                                                            if (match ==
                                                                                null) {
                                                                              if (!context
                                                                                  .mounted) {
                                                                                return;
                                                                              }
                                                                              ScaffoldMessenger.of(
                                                                                context,
                                                                              ).showSnackBar(
                                                                                SnackBar(
                                                                                  content: Text(
                                                                                    'Item tidak ditemukan di stok: $candidate',
                                                                                  ),
                                                                                ),
                                                                              );
                                                                              return;
                                                                            }

                                                                            setDialogState(() {
                                                                              line.selectedItem =
                                                                                  match;
                                                                              textEditingController.text =
                                                                                  itemLabel(
                                                                                    match!,
                                                                                  );
                                                                            });
                                                                            line.autocompleteFocusNode
                                                                                ?.unfocus();
                                                                          },
                                                                        ),
                                                                      ),
                                                                  onChanged: (_) {
                                                                    if (line
                                                                            .selectedItem !=
                                                                        null) {
                                                                      setDialogState(
                                                                        () => line.selectedItem = null,
                                                                      );
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
                                                              controller:
                                                                  line.qtyController,
                                                              textAlign:
                                                                  TextAlign.center,
                                                              keyboardType:
                                                                  TextInputType.number,
                                                              decoration:
                                                                  const InputDecoration(
                                                                hintText: '1',
                                                                border:
                                                                    OutlineInputBorder(),
                                                                isDense: true,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(width: 2),
                                                          IconButton(
                                                            tooltip: 'Hapus item',
                                                            onPressed:
                                                                lines.length <= 1
                                                                ? null
                                                                : () {
                                                                    setDialogState(() {
                                                                      line.dispose();
                                                                      lines.removeAt(
                                                                        idx,
                                                                      );
                                                                    });
                                                                  },
                                                            icon: const Icon(
                                                              Icons.close,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      if (selected != null)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                            top: 4,
                                                          ),
                                                          child: Align(
                                                            alignment:
                                                                Alignment.centerLeft,
                                                            child: Text(
                                                              'Stok tersedia: ${stockQty() ?? '-'}',
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color:
                                                                    Theme.of(context)
                                                                        .colorScheme
                                                                        .onSurfaceVariant,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      if (idx != lines.length - 1)
                                                        const Divider(height: 12),
                                                    ],
                                                  ),
                                                );
                                              }),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: notesController,
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
                            controller: courierController,
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
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Batal'),
                    ),
                    ElevatedButton(
                      onPressed: isLoading || error != null
                          ? null
                          : () async {
                              final dest = toBranchId;
                              if (dest == null || dest.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Pilih cabang tujuan')),
                                );
                                return;
                              }

                              // Close keyboard/overlay first to avoid deactivated-context asserts
                              FocusScope.of(context).unfocus();
                              final courier = courierController.text.trim();
                              if (courier.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Kurir wajib diisi')),
                                );
                                return;
                              }

                              final values = <_TransferLineValue>[];
                              for (final line in lines) {
                                final selected = line.selectedItem;
                                final itemName = selected == null
                                    ? ''
                                    : itemLabel(selected).toString().trim();
                                final qty =
                                    int.tryParse(line.qtyController.text.trim()) ?? 0;

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
                                    SnackBar(
                                      content: Text('Qty melebihi stok warehouse ($stockQty)'),
                                    ),
                                  );
                                  return;
                                }

                                values.add(_TransferLineValue(itemName: itemName, qty: qty));
                              }

                              final created = await _createTransfersBatch(
                                toBranchId: dest,
                                lines: values,
                                courier: courier,
                                notes: notesController.text.trim(),
                              );
                              if (!context.mounted) return;
                              if (created.isNotEmpty) {
                                Navigator.pop(context);

                                final toName = availableBranches
                                    .firstWhere(
                                      (b) => b['branch_id']?.toString() == dest,
                                      orElse: () => const <String, dynamic>{},
                                    )['name']
                                    ?.toString();
                                final fromName = userState.branches
                                    .cast<Map<String, dynamic>>()
                                    .where(
                                      (b) =>
                                          b['branch_id']?.toString() ==
                                          userState.branch.toString(),
                                    )
                                    .map((b) => b['name']?.toString())
                                    .whereType<String>()
                                    .cast<String?>()
                                    .firstWhere((x) => x != null, orElse: () => null);

                                await printSuratJalanTransfers(
                                  context,
                                  transfers: created,
                                  fromBranchName:
                                      fromName ?? 'Cabang ${userState.branch}',
                                  toBranchName: toName ?? 'Cabang $dest',
                                  courier: courier,
                                  notes: notesController.text.trim(),
                                );
                              }
                            },
                      child: const Text('Kirim'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    ).then((_) {
      notesController.dispose();
      courierController.dispose();
      for (final l in lines) {
        l.dispose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final outgoingPending =
        _transfers.where((t) => t['status'] == 'pending').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kirim ke Toko (Keluar)'),
        actions: [
          IconButton(
            tooltip: 'Kirim baru',
            onPressed: _showCreateTransferDialog,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _loadData,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Card(
                        child: ListTile(
                          leading: const Icon(Icons.arrow_upward),
                          title: const Text('Menunggu diproses'),
                          trailing: Chip(label: Text('$outgoingPending')),
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadData,
                        child: _transfers.isEmpty
                            ? ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(top: 48),
                                children: const [
                                  Center(
                                    child: Text('Belum ada transfer keluar'),
                                  ),
                                ],
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final cs = Theme.of(context).colorScheme;
final minW = math.max(
                                    constraints.maxWidth,
                                    920.0,
                                  );
                                  final dataRows = <DataRow>[];
                                  for (var i = 0; i < _transfers.length; i++) {
                                    final transfer =
                                        _transfers[i] as Map<String, dynamic>;
                                    final id = transfer['transfer_id']
                                            ?.toString() ??
                                        '-';
                                    final status =
                                        (transfer['status'] ?? '-').toString();
                                    final toName =
                                        (transfer['to_branch_name'] ?? '-')
                                            .toString();
                                    final itemName =
                                        (transfer['item_name'] ??
                                                transfer['nama_item'] ??
                                                '-')
                                            .toString();
                                    final qty =
                                        (transfer['quantity'] ??
                                                transfer['qty'] ??
                                                '-')
                                            .toString();
                                    final kurir =
                                        _kurirLabelDariTransfer(transfer);
                                    String? extra;
                                    if (status == 'completed' ||
                                        status == 'rejected') {
                                      extra = status == 'completed'
                                          ? 'Diterima: ${(transfer['approved_by_name'] ?? '-').toString()}'
                                          : 'Ditolak: ${(transfer['approved_by_name'] ?? '-').toString()}';
                                    }
                                    dataRows.add(
                                      DataRow(
                                        color:
                                            WidgetStateProperty.resolveWith(
                                                (s) {
                                          if (s.contains(
                                            WidgetState.hovered,
                                          )) {
                                            return cs.primary
                                                .withValues(alpha: 0.06);
                                          }
                                          return i.isOdd
                                              ? cs.surfaceContainerHighest
                                                  .withValues(alpha: 0.45)
                                              : null;
                                        }),
                                        cells: [
                                          DataCell(
                                            Text(
                                              '#$id',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(itemName),
                                                if (extra != null)
                                                  Text(
                                                    extra,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: cs
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          DataCell(Text(qty)),
                                          DataCell(Text(toName)),
                                          DataCell(Text(kurir)),
                                          DataCell(
                                            Chip(
                                              label: Text(
                                                status,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      0,
                                      12,
                                      12,
                                    ),
                                    child: Material(
                                      elevation: 0,
                                      color: cs.surfaceContainerLow
                                          .withValues(alpha: 0.65),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(
                                          color: cs.outlineVariant
                                              .withValues(alpha: 0.45),
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Scrollbar(
                                        child: SingleChildScrollView(
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          scrollDirection: Axis.horizontal,
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              minWidth: minW,
                                            ),
                                            child: SingleChildScrollView(
                                              physics:
                                                  const AlwaysScrollableScrollPhysics(),
                                              child: DataTable(
                                                headingRowColor:
                                                    WidgetStateProperty.all(
                                                  cs.surfaceContainerHigh,
                                                ),
dataRowMinHeight: 48,
                                                dataRowMaxHeight: 72,
                                                columnSpacing: 10,
                                                horizontalMargin: 8,
                                                showCheckboxColumn: false,
                                                dividerThickness: 0.5,
                                                columns: [
                                                  DataColumn(
                                                    label: dataTableColumnLabel('ID'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Item'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Qty'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Ke'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Kurir'),
                                                  ),
                                                  DataColumn(
                                                    label: dataTableColumnLabel('Status'),
                                                  ),
                                                ],
                                                rows: dataRows,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateTransferDialog,
        tooltip: 'Kirim barang',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _TransferLine {
  final TextEditingController qtyController = TextEditingController(text: '1');
  Map<String, dynamic>? selectedItem;
  // Owned by Autocomplete; do not dispose manually.
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

