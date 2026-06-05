import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vanessa3/modules/stockist/widgets/stock_inventory_grouped_table.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/stock_status_filter_summary_header.dart';
import 'package:vanessa3/utils/branch_types.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/responsive_layout.dart';
import 'package:vanessa3/utils/stock_list_route_args.dart';
import 'package:vanessa3/utils/stock_opname_report_print.dart';
import 'package:vanessa3/utils/stock_opname_session_snapshot.dart';
import 'package:vanessa3/utils/stock_inventory_search.dart'
    hide stockItemQuantity;
import 'package:vanessa3/widgets/qr_scan_route.dart';

enum _OpnameListView { pending, verified, missing, all }

enum _PostSaveAction { print, viewMissing, newSession, close }

/// Stok opname per kode unik: scan / ketik kode untuk verifikasi fisik.
class StockOpnamePage extends ConsumerStatefulWidget {
  const StockOpnamePage({
    super.key,
    this.title = 'Stok Opname',
    this.stockTypeFilter,
    this.allowBranchPicker = false,
    this.branchPickerTokoWarehouseOnly = true,
    this.branchPickerWorkshopOnly = false,
    this.missingStockRouteName,
  });

  final String title;
  final String? stockTypeFilter;
  final bool allowBranchPicker;
  final bool branchPickerTokoWarehouseOnly;
  final bool branchPickerWorkshopOnly;

  /// Route daftar stok untuk filter `missing` setelah simpan (mis. [AppRoutes.adminTokoStock]).
  final String? missingStockRouteName;

  @override
  ConsumerState<StockOpnamePage> createState() => _StockOpnamePageState();
}

class _StockOpnamePageState extends ConsumerState<StockOpnamePage> {
  static const double _pendingWarnRatio = 0.10;
  static const int _pendingWarnMinCount = 10;

  final _scanCtrl = TextEditingController();
  final _sessionNotesCtrl = TextEditingController();
  final _scanFocus = FocusNode();

  List<dynamic> _items = [];
  List<Map<String, dynamic>> _branches = const [];
  Map<String, Map<String, dynamic>> _itemsById = {};
  Map<String, String> _codeToItemId = {};
  final Set<String> _verifiedIds = {};
  final Set<String> _missingIds = {};
  final List<Map<String, dynamic>> _recentVerified = [];

  String? _selectedBranchId;
  bool _isLoading = true;
  bool _isSaving = false;
  String _error = '';
  String _listSearch = '';
  String _selectedStatus = 'ready';
  _OpnameListView _listView = _OpnameListView.pending;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    _sessionNotesCtrl.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  static bool _branchIsActive(Map<String, dynamic> b) {
    final s = (b['status'] ?? 'active').toString().trim().toLowerCase();
    return s.isEmpty || s == 'active';
  }

  static String _normalizeScanCode(String raw) {
    final candidate = raw
        .trim()
        .split('\n')
        .first
        .trim()
        .split(RegExp(r'\s*[-–]\s*'))
        .first
        .trim();
    return normalizeStockSearchQuery(candidate).toLowerCase();
  }

  static String _itemCode(Map<String, dynamic> m) =>
      (m['item_code'] ?? m['kode_produk'] ?? '').toString().trim();

  static String _itemIdStr(Map<String, dynamic> m) =>
      (m['item_id'] ?? '').toString();

  void _rebuildIndexes() {
    _itemsById = {};
    _codeToItemId = {};
    for (final raw in _items) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final id = _itemIdStr(m);
      if (id.isEmpty) continue;
      _itemsById[id] = m;
      final code = _normalizeScanCode(_itemCode(m));
      if (code.isNotEmpty && !_codeToItemId.containsKey(code)) {
        _codeToItemId[code] = id;
      }
    }
  }

  Future<void> _initAndLoad() async {
    if (widget.allowBranchPicker) {
      await _loadBranches();
    } else {
      final branch = ref.read(userStateProvider).branch.trim();
      if (!mounted) return;
      setState(() {
        _selectedBranchId = branch.isEmpty ? null : branch;
      });
    }
    await _loadItems();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final resp = await http.get(
        Uri.parse('${NetworkConfig.baseUrl}/branches'),
        headers: NetworkConfig.defaultHeaders,
      );
      if (resp.statusCode != 200) {
        throw Exception('Gagal memuat cabang (${resp.statusCode})');
      }
      final decoded = jsonDecode(resp.body);
      final out = <Map<String, dynamic>>[];
      if (decoded is List) {
        for (final e in decoded) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          if (!_branchIsActive(m)) continue;
          final bt = m['branch_type']?.toString();
          if (widget.branchPickerWorkshopOnly) {
            if (!branchTypeIsWorkshop(bt)) continue;
          } else if (widget.branchPickerTokoWarehouseOnly) {
            if (!branchTypeIsTokoOrWarehouse(bt)) continue;
          }
          out.add(m);
        }
      }
      out.sort((a, b) {
        final aa =
            (a['alias'] ?? a['name'] ?? a['branch_id'] ?? '').toString();
        final bb =
            (b['alias'] ?? b['name'] ?? b['branch_id'] ?? '').toString();
        return aa.compareTo(bb);
      });
      final userBranch = ref.read(userStateProvider).branch.trim();
      String? pick = _selectedBranchId;
      if (pick == null || pick.isEmpty) {
        if (userBranch.isNotEmpty &&
            out.any((b) => (b['branch_id'] ?? '').toString() == userBranch)) {
          pick = userBranch;
        } else if (out.isNotEmpty) {
          pick = (out.first['branch_id'] ?? '').toString();
        }
      }
      if (!mounted) return;
      setState(() {
        _branches = out;
        _selectedBranchId = pick;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
  }

  String _branchLabel(String branchId) {
    for (final b in _branches) {
      if ((b['branch_id'] ?? '').toString() == branchId) {
        final alias = (b['alias'] ?? '').toString().trim();
        final name = (b['name'] ?? branchId).toString().trim();
        return alias.isNotEmpty ? alias : name;
      }
    }
    final user = ref.read(userStateProvider);
    return stockBranchDisplayName(
          branches: user.branches,
          branchId: branchId,
        ) ??
        branchId;
  }

  Future<void> _loadItems() async {
    final branchId = _selectedBranchId?.trim() ?? '';
    if (branchId.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'Pilih cabang terlebih dahulu';
        _items = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final query = <String, String>{'branch_id': branchId};
      final st = widget.stockTypeFilter?.trim();
      if (st != null && st.isNotEmpty) {
        query['stock_type'] = st;
      }

      final response = await http.get(
        Uri.parse('${NetworkConfig.baseUrl}/items')
            .replace(queryParameters: query),
        headers: NetworkConfig.defaultHeaders,
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data is List ? data : <dynamic>[];
        setState(() {
          _items = list;
          _verifiedIds.clear();
          _missingIds.clear();
          _recentVerified.clear();
          _rebuildIndexes();
          _isLoading = false;
        });
      } else {
        var msg = 'Gagal memuat stok: ${response.statusCode}';
        try {
          final err = jsonDecode(response.body) as Map;
          final d = (err['error'] ?? '').toString().trim();
          if (d.isNotEmpty) msg = d;
        } catch (_) {}
        setState(() {
          _error = msg;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  /// Item dalam scope opname (filter status, bukan pencarian daftar).
  List<Map<String, dynamic>> get _scopeItems {
    final out = <Map<String, dynamic>>[];
    for (final raw in _items) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      if (_selectedStatus != 'all' &&
          !stockItemVisibleForStatusFilter(m, _selectedStatus)) {
        continue;
      }
      out.add(m);
    }
    return out;
  }

  List<Map<String, dynamic>> get _visibleListItems {
    Iterable<Map<String, dynamic>> list = _scopeItems;
    switch (_listView) {
      case _OpnameListView.pending:
        list = list.where((m) {
          final id = _itemIdStr(m);
          return !_verifiedIds.contains(id) && !_missingIds.contains(id);
        });
      case _OpnameListView.verified:
        list = list.where((m) => _verifiedIds.contains(_itemIdStr(m)));
      case _OpnameListView.missing:
        list = list.where((m) => _missingIds.contains(_itemIdStr(m)));
      case _OpnameListView.all:
        break;
    }
    if (_listSearch.trim().isNotEmpty) {
      list = list.where((m) => stockInventoryItemMatchesQuery(m, _listSearch));
    }
    return list.toList()
      ..sort((a, b) {
        final ka = _itemCode(a).toLowerCase();
        final kb = _itemCode(b).toLowerCase();
        return ka.compareTo(kb);
      });
  }

  int get _scopeVerifiedCount =>
      _scopeItems.where((m) => _verifiedIds.contains(_itemIdStr(m))).length;

  int get _scopeMissingCount =>
      _scopeItems.where((m) => _missingIds.contains(_itemIdStr(m))).length;

  int get _scopePendingCount => _scopeItems.length -
      _scopeVerifiedCount -
      _scopeMissingCount;

  String _opnameStatusLabel(String itemId) {
    if (_verifiedIds.contains(itemId)) return 'Terverifikasi';
    if (_missingIds.contains(itemId)) return 'Hilang';
    return 'Belum scan';
  }

  bool _verifyItem(String itemId, {bool showAlready = true}) {
    final m = _itemsById[itemId];
    if (m == null) return false;

    if (_verifiedIds.contains(itemId)) {
      if (showAlready && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_itemCode(m)} sudah terverifikasi'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
      return false;
    }

    setState(() {
      _missingIds.remove(itemId);
      _verifiedIds.add(itemId);
      _recentVerified.removeWhere((e) => _itemIdStr(e) == itemId);
      _recentVerified.insert(0, m);
      if (_recentVerified.length > 8) {
        _recentVerified.removeRange(8, _recentVerified.length);
      }
    });
    return true;
  }

  void _unverifyItem(String itemId) {
    if (!_verifiedIds.contains(itemId)) return;
    setState(() {
      _verifiedIds.remove(itemId);
      _recentVerified.removeWhere((e) => _itemIdStr(e) == itemId);
    });
  }

  void _markMissing(String itemId) {
    final m = _itemsById[itemId];
    if (m == null) return;
    setState(() {
      _verifiedIds.remove(itemId);
      _recentVerified.removeWhere((e) => _itemIdStr(e) == itemId);
      _missingIds.add(itemId);
      _listView = _OpnameListView.missing;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_itemCode(m)} ditandai hilang'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _unmarkMissing(String itemId) {
    setState(() => _missingIds.remove(itemId));
  }

  Future<void> _markAllPendingAsMissing() async {
    final pendingIds = _scopeItems
        .where((m) {
          final id = _itemIdStr(m);
          return !_verifiedIds.contains(id) && !_missingIds.contains(id);
        })
        .map(_itemIdStr)
        .toList();
    if (pendingIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada barang belum scan')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tandai belum scan sebagai hilang?'),
        content: Text(
          '${pendingIds.length} barang belum discan akan ditandai hilang '
          '(qty di-set 0 saat simpan). Pastikan barang memang tidak ada fisiknya.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tandai hilang'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _missingIds.addAll(pendingIds);
      _verifiedIds.removeWhere((id) => pendingIds.contains(id));
      _recentVerified.removeWhere((m) => pendingIds.contains(_itemIdStr(m)));
      _listView = _OpnameListView.missing;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${pendingIds.length} barang ditandai hilang'),
      ),
    );
  }

  /// `quiet`: tanpa snackbar per kode (untuk batch dari kamera).
  bool _processScan(String raw, {bool fromScanner = false, bool quiet = false}) {
    final normalized = _normalizeScanCode(raw);
    if (normalized.isEmpty) return false;

    final itemId = _codeToItemId[normalized];
    if (itemId == null) {
      if (!quiet && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kode tidak ditemukan di stok sistem: $normalized'),
            backgroundColor: Colors.red.shade700,
          ),
        );
        HapticFeedback.heavyImpact();
      }
      return false;
    }

    final m = _itemsById[itemId]!;
    if (_selectedStatus != 'all' &&
        !stockItemVisibleForStatusFilter(m, _selectedStatus)) {
      if (!quiet && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_itemCode(m)} ada di sistem tapi di luar filter status saat ini',
            ),
          ),
        );
      }
      return false;
    }

    final verified = _verifyItem(itemId, showAlready: !quiet);
    if (verified) {
      if (!quiet) {
        HapticFeedback.mediumImpact();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ ${_itemCode(m)} · ${m['name'] ?? ''}'),
              duration: const Duration(milliseconds: 900),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
      }
    }

    if (!quiet) {
      _scanCtrl.clear();
      if (fromScanner) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scanFocus.requestFocus();
        });
      }
    }
    return verified;
  }

  void _processBatchScans(List<String> codes) {
    var ok = 0;
    var notFound = 0;
    var skipped = 0;
    for (final raw in codes) {
      final normalized = _normalizeScanCode(raw);
      if (normalized.isEmpty) continue;
      if (_codeToItemId[normalized] == null) {
        notFound++;
        continue;
      }
      if (_processScan(raw, quiet: true)) {
        ok++;
      } else {
        skipped++;
      }
    }
    if (!mounted) return;
    if (ok > 0) HapticFeedback.mediumImpact();
    final parts = <String>[];
    if (ok > 0) parts.add('$ok terverifikasi');
    if (skipped > 0) parts.add('$skipped sudah ada / di luar filter');
    if (notFound > 0) parts.add('$notFound tidak dikenali');
    if (parts.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(parts.join(' · ')),
        backgroundColor:
            ok > 0 ? Colors.green.shade700 : Colors.orange.shade800,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scanFocus.requestFocus();
    });
  }

  Future<void> _openScanner() async {
    final codes = await pushQrBatchScanPage(
      context,
      title: 'Scan batch — Stok Opname',
      showTorchActions: true,
    );
    if (codes == null || codes.isEmpty) return;
    _processBatchScans(codes);
  }

  List<Map<String, dynamic>> _pendingChanges() {
    final out = <Map<String, dynamic>>[];
    for (final m in _scopeItems) {
      final id = _itemIdStr(m);
      if (!_missingIds.contains(id)) continue;

      final sys = stockItemQuantity(m);
      if (sys <= 0) continue;

      out.add({
        'item_id': int.tryParse(id) ?? m['item_id'],
        'counted_quantity': 0,
        'name': (m['name'] ?? '-').toString(),
        'kode': _itemCode(m),
        'system_quantity': sys,
        'delta': -sys,
        'kind': 'missing',
      });
    }
    return out;
  }

  List<Map<String, dynamic>> _verifiedSubmitLines() {
    final out = <Map<String, dynamic>>[];
    for (final m in _scopeItems) {
      final id = _itemIdStr(m);
      if (!_verifiedIds.contains(id)) continue;
      final sys = stockItemQuantity(m);
      out.add({
        'item_id': int.tryParse(id) ?? m['item_id'],
        'counted_quantity': sys,
        'verified': true,
        'name': (m['name'] ?? '-').toString(),
        'kode': _itemCode(m),
        'kind': 'verified',
      });
    }
    return out;
  }

  List<Map<String, dynamic>> _submitLines() {
    return [..._pendingChanges(), ..._verifiedSubmitLines()];
  }

  bool get _canSaveOpname =>
      _scopeVerifiedCount > 0 || _pendingChanges().isNotEmpty;

  bool _shouldWarnIncompleteOpname() {
    final pending = _scopePendingCount;
    final total = _scopeItems.length;
    if (pending <= 0 || total <= 0) return false;
    if (pending >= _pendingWarnMinCount) return true;
    return pending / total > _pendingWarnRatio;
  }

  StockOpnameSessionSnapshot _captureSessionSnapshot({
    required String branchId,
    required int savedVerifiedCount,
    required int savedMissingCount,
  }) {
    return StockOpnameSessionSnapshot(
      branchId: branchId,
      branchLabel: _branchLabel(branchId),
      selectedStatus: _selectedStatus,
      scopeItems: List<Map<String, dynamic>>.from(_scopeItems),
      verifiedIds: Set<String>.from(_verifiedIds),
      missingIds: Set<String>.from(_missingIds),
      sessionNotes: _sessionNotesCtrl.text.trim(),
      savedVerifiedCount: savedVerifiedCount,
      savedMissingCount: savedMissingCount,
      pendingAtSave: _scopePendingCount,
    );
  }

  void _resetOpnameSession({bool clearNotes = true}) {
    setState(() {
      _verifiedIds.clear();
      _missingIds.clear();
      _recentVerified.clear();
      _listView = _OpnameListView.pending;
      if (clearNotes) _sessionNotesCtrl.clear();
    });
  }

  void _openMissingStockList(String branchId) {
    final route = widget.missingStockRouteName?.trim();
    if (route == null || route.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Buka menu Stok, filter status Hilang, untuk tindak lanjut restok.',
          ),
        ),
      );
      return;
    }
    Navigator.pushNamed(
      context,
      route,
      arguments: StockListRouteArgs.missingStock(branchId: branchId),
    );
  }

  Future<_PostSaveAction?> _showPostSaveDialog(
    StockOpnameSessionSnapshot snapshot,
  ) {
    final canViewMissing = widget.missingStockRouteName != null &&
        snapshot.savedMissingCount > 0;

    return showDialog<_PostSaveAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Opname tersimpan'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Cabang: ${snapshot.branchLabel}'),
              const SizedBox(height: 8),
              Text('✓ ${snapshot.savedVerifiedCount} barang terverifikasi'),
              if (snapshot.savedMissingCount > 0)
                Text(
                  '✗ ${snapshot.savedMissingCount} barang dikoreksi hilang (qty → 0)',
                  style: TextStyle(color: Colors.red.shade700),
                ),
              if (snapshot.pendingAtSave > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${snapshot.pendingAtSave} barang belum discan tidak diubah di sistem.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'Langkah berikutnya:',
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              const Text('• Cetak laporan untuk arsip'),
              if (canViewMissing)
                const Text('• Lihat daftar barang hilang & restok jika ditemukan'),
              const Text('• Opname baru untuk sesi berikutnya'),
            ],
          ),
        ),
        actions: [
          if (canViewMissing)
            TextButton(
              onPressed: () => Navigator.pop(ctx, _PostSaveAction.viewMissing),
              child: const Text('Lihat hilang'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _PostSaveAction.print),
            child: const Text('Cetak laporan'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _PostSaveAction.newSession),
            child: const Text('Opname baru'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _PostSaveAction.close),
            child: const Text('Selesai'),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePostSaveAction(
    _PostSaveAction? action,
    StockOpnameSessionSnapshot snapshot,
  ) async {
    if (!mounted) return;

    switch (action) {
      case _PostSaveAction.print:
        await printStockOpnameReportFromSnapshot(context, snapshot);
        break;
      case _PostSaveAction.viewMissing:
        _openMissingStockList(snapshot.branchId);
        break;
      case _PostSaveAction.newSession:
        _resetOpnameSession();
        break;
      case _PostSaveAction.close:
      case null:
        break;
    }

    await _loadItems();
  }

  Future<bool> _confirmIncompleteOpname() async {
    if (!_shouldWarnIncompleteOpname()) return true;

    final pending = _scopePendingCount;
    final total = _scopeItems.length;
    final pct = total > 0 ? ((pending / total) * 100).round() : 0;

    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Opname belum lengkap'),
        content: Text(
          '$pending dari $total barang di scope belum discan (~$pct%).\n\n'
          'Barang tersebut tidak akan diubah di sistem. '
          'Yakin ingin menyimpan opname sekarang?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Lanjut scan'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tetap simpan'),
          ),
        ],
      ),
    );
    return second == true;
  }

  Future<void> _submitOpname() async {
    final branchId = _selectedBranchId?.trim() ?? '';
    if (branchId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cabang belum dipilih')),
      );
      return;
    }

    final missingChanges = _pendingChanges();
    final verifiedLines = _verifiedSubmitLines();
    final lines = _submitLines();

    if (!_canSaveOpname || lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Scan atau tandai barang dulu sebelum simpan opname.',
          ),
        ),
      );
      return;
    }

    final warnIncomplete = _shouldWarnIncompleteOpname();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Simpan hasil opname?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (warnIncomplete)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Text(
                    'Peringatan: $_scopePendingCount barang belum discan '
                    '(${_scopeItems.isNotEmpty ? ((_scopePendingCount / _scopeItems.length) * 100).round() : 0}% scope).',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ),
              Text('Cabang: ${_branchLabel(branchId)}'),
              const SizedBox(height: 8),
              Text('Terverifikasi: ${verifiedLines.length} barang'),
              if (missingChanges.isNotEmpty)
                Text(
                  'Koreksi hilang (qty → 0): ${missingChanges.length} barang',
                  style: TextStyle(color: Colors.red.shade700),
                ),
              if (_scopePendingCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Catatan: $_scopePendingCount barang belum discan tidak diubah.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
              if (missingChanges.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...missingChanges.take(8).map((c) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${c['kode']}: ${c['system_quantity']} → 0 (hilang)',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red.shade700,
                      ),
                    ),
                  );
                }),
                if (missingChanges.length > 8)
                  Text('… dan ${missingChanges.length - 8} barang hilang lainnya'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await _printOpnameReport();
            },
            icon: const Icon(Icons.print, size: 18),
            label: const Text('Cetak dulu'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    if (!await _confirmIncompleteOpname() || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final body = <String, dynamic>{
        'branch_id': branchId,
        'lines': [
          for (final line in lines)
            {
              'item_id': line['item_id'],
              'counted_quantity': line['counted_quantity'],
              if (line['verified'] == true) 'verified': true,
            },
        ],
      };
      final sessionNote = _sessionNotesCtrl.text.trim();
      if (sessionNote.isNotEmpty) {
        body['notes'] = sessionNote;
      }

      final resp = await http.post(
        Uri.parse('${NetworkConfig.baseUrl}/items/stock-opname'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode(body),
      );

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        var verifiedCount = verifiedLines.length;
        var missingCount = missingChanges.length;
        if (decoded is Map && decoded['applied'] is List) {
          final applied = decoded['applied'] as List;
          verifiedCount = applied
              .where((e) => e is Map && e['action'] == 'verified')
              .length;
          missingCount = applied
              .where((e) => e is Map && e['action'] != 'verified')
              .length;
        }

        final snapshot = _captureSessionSnapshot(
          branchId: branchId,
          savedVerifiedCount: verifiedCount,
          savedMissingCount: missingCount,
        );

        final postAction = await _showPostSaveDialog(snapshot);
        await _handlePostSaveAction(postAction, snapshot);
      } else {
        String msg = 'Gagal menyimpan (${resp.statusCode})';
        try {
          final err = jsonDecode(resp.body) as Map;
          final d = (err['error'] ?? '').toString().trim();
          if (d.isNotEmpty) msg = d;
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _branchPicker() {
    if (!widget.allowBranchPicker || _branches.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: DropdownButtonFormField<String>(
        initialValue: _selectedBranchId,
        decoration: const InputDecoration(
          labelText: 'Cabang',
          border: OutlineInputBorder(),
        ),
        items: [
          for (final b in _branches)
            DropdownMenuItem(
              value: (b['branch_id'] ?? '').toString(),
              child: Text(
                '${(b['alias'] ?? b['name'] ?? b['branch_id'] ?? '').toString()} · ${branchTypeLabel(b['branch_type']?.toString())}',
              ),
            ),
        ],
        onChanged: (v) async {
          setState(() => _selectedBranchId = v);
          await _loadItems();
        },
      ),
    );
  }

  Widget _progressCard() {
    final total = _scopeItems.length;
    final verified = _scopeVerifiedCount;
    final pending = _scopePendingCount;
    final progress = total > 0 ? verified / total : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Progress opname',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    '$verified / $total',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _statChip(
                    label: 'Terverifikasi',
                    count: verified,
                    color: Colors.green,
                  ),
                  _statChip(
                    label: 'Belum scan',
                    count: pending,
                    color: Colors.orange,
                  ),
                  if (_scopeMissingCount > 0)
                    _statChip(
                      label: 'Hilang',
                      count: _scopeMissingCount,
                      color: Colors.red,
                    ),
                  if (_pendingChanges().isNotEmpty)
                    _statChip(
                      label: 'Akan dikoreksi',
                      count: _pendingChanges().length,
                      color: Colors.red,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip({
    required String label,
    required int count,
    required MaterialColor color,
  }) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color.shade100,
        child: Text(
          '$count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color.shade800,
          ),
        ),
      ),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _scanBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _scanCtrl,
              focusNode: _scanFocus,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Scan / ketik kode barang',
                hintText: 'KB001, scan QR…',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code_2),
                isDense: true,
              ),
              onSubmitted: _processScan,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Scan batch — beberapa QR tanpa tutup kamera',
            onPressed: _openScanner,
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
      ),
    );
  }

  Widget _recentScans() {
    if (_recentVerified.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Baru discan',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in _recentVerified.take(6))
                InputChip(
                  avatar: const Icon(Icons.check, size: 16, color: Colors.green),
                  label: Text(
                    _itemCode(m),
                    style: const TextStyle(fontSize: 12),
                  ),
                  onDeleted: () => _unverifyItem(_itemIdStr(m)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _listToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<_OpnameListView>(
          segments: [
            ButtonSegment(
              value: _OpnameListView.pending,
              label: Text('Belum ($_scopePendingCount)'),
              icon: const Icon(Icons.pending_actions, size: 18),
            ),
            ButtonSegment(
              value: _OpnameListView.verified,
              label: Text('Sudah ($_scopeVerifiedCount)'),
              icon: const Icon(Icons.check_circle_outline, size: 18),
            ),
            ButtonSegment(
              value: _OpnameListView.missing,
              label: Text('Hilang ($_scopeMissingCount)'),
              icon: const Icon(Icons.not_interested, size: 18),
            ),
            ButtonSegment(
              value: _OpnameListView.all,
              label: Text('Semua (${_scopeItems.length})'),
              icon: const Icon(Icons.list, size: 18),
            ),
          ],
          selected: {_listView},
          onSelectionChanged: (s) => setState(() => _listView = s.first),
        ),
      ),
    );
  }

  Widget _itemTile(Map<String, dynamic> m) {
    final id = _itemIdStr(m);
    final verified = _verifiedIds.contains(id);
    final missing = _missingIds.contains(id);
    final opnameStatus = _opnameStatusLabel(id);
    final code = _itemCode(m);
    final name = (m['name'] ?? '-').toString();
    final status = (m['status'] ?? '').toString();

    Color avatarBg;
    IconData avatarIcon;
    Color avatarColor;
    if (missing) {
      avatarBg = Colors.red.shade50;
      avatarIcon = Icons.close;
      avatarColor = Colors.red.shade700;
    } else if (verified) {
      avatarBg = Colors.green.shade50;
      avatarIcon = Icons.check;
      avatarColor = Colors.green.shade700;
    } else {
      avatarBg = Colors.grey.shade100;
      avatarIcon = Icons.inventory_2_outlined;
      avatarColor = Colors.grey.shade600;
    }

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: avatarBg,
        child: Icon(avatarIcon, size: 20, color: avatarColor),
      ),
      title: Text(code.isEmpty ? name : code, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        missing
            ? '$name · Opname: Hilang'
            : verified
                ? '$name · Opname: Terverifikasi'
                : '$name · Opname: $opnameStatus · ${stockItemStatusLabel(status)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!verified && !missing)
            IconButton(
              tooltip: 'Tandai hilang',
              icon: Icon(Icons.not_interested, size: 20, color: Colors.red.shade700),
              onPressed: () => _markMissing(id),
            ),
          if (missing)
            IconButton(
              tooltip: 'Batalkan tanda hilang',
              icon: const Icon(Icons.undo, size: 20),
              onPressed: () => _unmarkMissing(id),
            )
          else if (verified)
            IconButton(
              tooltip: 'Batalkan verifikasi',
              icon: const Icon(Icons.undo, size: 20),
              onPressed: () => _unverifyItem(id),
            )
          else
            IconButton.filledTonal(
              tooltip: 'Tandai ditemukan',
              icon: const Icon(Icons.check, size: 20),
              onPressed: () => _verifyItem(id, showAlready: false),
            ),
        ],
      ),
      onTap: () {
        if (missing) {
          _unmarkMissing(id);
        } else if (verified) {
          _unverifyItem(id);
        } else {
          _verifyItem(id, showAlready: false);
        }
      },
    );
  }

  Future<void> _printOpnameReport() async {
    final branchId = _selectedBranchId?.trim() ?? '';
    if (branchId.isEmpty || _scopeItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada data opname untuk dicetak')),
      );
      return;
    }
    await printStockOpnameReportPdf(
      context,
      branchLabel: _branchLabel(branchId),
      branchIdForLogo: branchId,
      selectedStatus: _selectedStatus,
      scopeItems: _scopeItems,
      verifiedIds: _verifiedIds,
      missingIds: _missingIds,
      sessionNotes: _sessionNotesCtrl.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final branchId = _selectedBranchId?.trim() ?? '';
    final visible = _visibleListItems;
    final missingCount = _pendingChanges().length;
    final canSave = _canSaveOpname;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'mark_missing') {
                await _markAllPendingAsMissing();
              } else if (value == 'reset') {
                _resetOpnameSession(clearNotes: false);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'mark_missing',
                child: Text('Tandai belum scan sebagai hilang'),
              ),
              const PopupMenuItem(
                value: 'reset',
                child: Text('Reset verifikasi & hilang'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Cetak laporan opname',
            onPressed: _isLoading || _error.isNotEmpty ? null : _printOpnameReport,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading || _isSaving ? null : _loadItems,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _initAndLoad,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _branchPicker(),
                    if (branchId.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          'Cabang: ${_branchLabel(branchId)} · scan = verifikasi (qty tidak berubah). '
                          'Tandai hilang hanya jika barang memang tidak ada.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    _scanBar(),
                    _progressCard(),
                    _recentScans(),
                    StockStatusFilterSummaryHeader(
                      selectedStatus: _selectedStatus,
                      onStatusChanged: (v) => setState(() => _selectedStatus = v),
                      summaryItems: _scopeItems,
                      filterLabel: 'Scope opname (status)',
                    ),
                    _listToggle(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.filter_list),
                          hintText: 'Filter daftar…',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: _listSearch.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () =>
                                      setState(() => _listSearch = ''),
                                )
                              : null,
                        ),
                        onChanged: (v) =>
                            setState(() => _listSearch = normalizeStockSearchQuery(v)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: TextField(
                        controller: _sessionNotesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Catatan opname (opsional)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLines: 2,
                      ),
                    ),
                    if (canSave)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Material(
                          color: missingCount > 0
                              ? Colors.red.shade50
                              : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              missingCount > 0
                                  ? '$_scopeVerifiedCount terverifikasi · '
                                      '$missingCount ditandai hilang — tekan Simpan Opname.'
                                  : '$_scopeVerifiedCount barang terverifikasi — '
                                      'tekan Simpan Opname untuk catat hasil.',
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadItems,
                        child: visible.isEmpty
                            ? ListView(
                                children: [
                                  SizedBox(
                                    height:
                                        MediaQuery.sizeOf(context).height * 0.2,
                                  ),
                                  Center(
                                    child: Text(
                                      _listView == _OpnameListView.pending
                                          ? 'Semua barang sudah discan atau ditandai hilang ✓'
                                          : _listView == _OpnameListView.missing
                                              ? 'Belum ada barang ditandai hilang'
                                              : 'Tidak ada barang di daftar ini',
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding: EdgeInsets.only(
                                  bottom:
                                      ResponsiveLayout.scrollEndGap(context) +
                                          88,
                                ),
                                itemCount: visible.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) => _itemTile(visible[i]),
                              ),
                      ),
                    ),
                  ],
                ),
      floatingActionButton: _isLoading || _error.isNotEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _isSaving || !canSave ? null : _submitOpname,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(
                _isSaving
                    ? 'Menyimpan…'
                    : missingCount > 0
                        ? 'Simpan ($missingCount hilang)'
                        : canSave
                            ? 'Simpan Opname'
                            : 'Simpan Opname',
              ),
            ),
    );
  }
}
