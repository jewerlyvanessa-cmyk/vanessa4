import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/core/network/api_exceptions.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/manager_report_period_selector.dart';
import 'package:vanessa3/utils/file_uploader.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/kasir_scope_filter.dart';
import 'package:vanessa3/utils/store_operational_print.dart';

// Conditional imports for platform-specific packages
import 'package:image_picker/image_picker.dart'
    if (dart.library.html) '../../../utils/image_picker_stub.dart';

enum _MoneyKind { expense, income }

/// Pencatatan pemasukan & pengeluaran operasional toko (bukan pembayaran order) per cabang.
class KeuanganTokoPage extends ConsumerStatefulWidget {
  const KeuanganTokoPage({super.key});

  @override
  ConsumerState<KeuanganTokoPage> createState() => _KeuanganTokoPageState();
}

class _KeuanganTokoPageState extends ConsumerState<KeuanganTokoPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  static const _expenseCategories = <String>[
    'ATK & perlengkapan',
    'Listrik / utilitas',
    'Air',
    'Transport / kirim',
    'Konsumsi',
    'Maintenance & perbaikan',
    'Lainnya (pengeluaran)',
  ];

  static const _incomeCategories = <String>[
    'Pendapatan lain (bukan order)',
    'Pengembalian / koreksi kas (+)',
    'Pendapatan jasa / komisi',
    'Lainnya (pemasukan)',
  ];

  _MoneyKind _kind = _MoneyKind.expense;
  String _category = _expenseCategories.first;

  List<String> get _categoriesForKind => _kind == _MoneyKind.income
      ? _incomeCategories
      : _expenseCategories;

  bool _entryIsIncome(Map<String, dynamic> e) =>
      e['entry_kind']?.toString() == 'income';

  String? _normalizeUrl(dynamic raw) {
    final s = raw?.toString().trim();
    if (s == null || s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    if (s.startsWith('/')) return '${NetworkConfig.baseUrl}$s';
    return '${NetworkConfig.baseUrl}/uploads/$s';
  }

  XFile? _newProofX;
  String? _newProofUrl;
  bool _uploadingProof = false;

  List<Map<String, dynamic>> _entries = [];
  bool _loadingList = true;
  bool _submitting = false;
  String? _listError;
  late DateTime _rangeStart;
  late DateTime _rangeEnd;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final t = managerReportDateOnly(DateTime.now());
    _rangeStart = t;
    _rangeEnd = t;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEntries());
  }

  bool get _singleDayFilter {
    final s = managerReportDateOnly(_rangeStart);
    final e = managerReportDateOnly(_rangeEnd);
    return managerReportSameCalendarDay(s, e);
  }

  String _branchLabel() {
    final u = ref.read(userStateProvider);
    final bid = u.branch;
    if (bid.isEmpty) return 'Cabang';
    for (final b in u.branches) {
      final id = '${b['branch_id'] ?? b['id'] ?? ''}';
      if (id == bid) {
        return (b['alias'] ?? b['branch_name'] ?? b['name'] ?? bid)
            .toString();
      }
    }
    return 'Cabang $bid';
  }

  /// Query scope: cabang aktif + entri milik user login (selaras laporan kasir).
  Map<String, String>? _listScopeQuery() {
    final u = ref.read(userStateProvider);
    final branchId = u.branch.trim();
    final userId = u.userId;
    if (userId == null) return null;
    if (branchId.isEmpty) return null;
    return {
      'branch_id': branchId,
      'user_id': userId.toString(),
    };
  }

  String _scopeSubtitle() {
    final u = ref.read(userStateProvider);
    final cashier = u.username.isEmpty ? 'Kasir' : u.username;
    return '${_branchLabel()} · $cashier${u.userId != null ? ' (ID ${u.userId})' : ''}';
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final today = managerReportDateOnly(now);
    final picked = await showDateRangePicker(
      context: context,
      locale: const Locale('id', 'ID'),
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: DateTimeRange(
        start: managerReportDateOnly(_rangeStart),
        end: managerReportDateOnly(_rangeEnd),
      ),
    );
    if (picked == null || !mounted) return;
    final days = picked.end.difference(picked.start).inDays + 1;
    if (days > kManagerReportMaxRangeDays) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Rentang maksimal $kManagerReportMaxRangeDays hari.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _rangeStart = picked.start;
      _rangeEnd = picked.end;
    });
    await _loadEntries();
  }

  Future<void> _printReport() async {
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada data untuk dicetak.')),
      );
      return;
    }
    await printStoreOperationalPdf(
      context,
      branchLabel: _branchLabel(),
      branchIdForLogo: ref.read(userStateProvider).branch.trim(),
      periodStart: _rangeStart,
      periodEnd: _rangeEnd,
      entries: _entries,
    );
  }

  Future<void> _pickNewProof(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (picked == null) return;
    setState(() {
      _newProofX = picked;
      _newProofUrl = null;
    });
  }

  void _clearNewProof() {
    setState(() {
      _newProofX = null;
      _newProofUrl = null;
    });
  }

  Future<String?> _ensureNewProofUploaded() async {
    if (_newProofUrl != null && _newProofUrl!.trim().isNotEmpty) {
      return _newProofUrl;
    }
    final x = _newProofX;
    if (x == null) return null;
    if (kIsWeb) {
      // Web build memakai stub picker (null) dalam repo ini.
      return null;
    }

    setState(() => _uploadingProof = true);
    try {
      final f = File(x.path);
      final token = ref.read(userStateProvider).authToken;
      final url = await FileUploader.uploadImage(f, token: token);
      if (url == null || url.trim().isEmpty) return null;
      setState(() => _newProofUrl = url);
      return url;
    } finally {
      if (mounted) setState(() => _uploadingProof = false);
    }
  }

  Future<void> _openEntrySheet(Map<String, dynamic> e) async {
    final proofUrl = _normalizeUrl(e['proof_photo_url']);
    final branchId = ref.read(userStateProvider).branch;
    final entryId = e['entry_id']?.toString() ?? '';

    String kindLabel(bool income) => income ? 'Pemasukan' : 'Pengeluaran';

    final money = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final dt = DateTime.tryParse(e['created_at']?.toString() ?? '');
    final whenStr = dt != null
        ? DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(dt.toLocal())
        : '—';
    final income = _entryIsIncome(e);
    final cat = e['category']?.toString() ?? '—';
    final notes = e['notes']?.toString() ?? '';
    final amt = e['amount'];
    final value = amt is num ? amt.toDouble() : double.tryParse('$amt') ?? 0;

    Future<void> uploadOrChangePhoto() async {
      if (branchId.isEmpty || entryId.isEmpty) return;
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Kamera'),
                onTap: () => Navigator.of(c).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Galeri'),
                onTap: () => Navigator.of(c).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (source == null) return;

      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (picked == null) return;
      if (kIsWeb) return;
      final f = File(picked.path);
      final token = ref.read(userStateProvider).authToken;
      final url = await FileUploader.uploadImage(f, token: token);
      if (url == null || url.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal upload foto bukti.')),
          );
        }
        return;
      }
      final res = await ApiClient.post(
        '/store-operational/$entryId/proof-photo',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'branch_id': int.tryParse(branchId),
          'proof_photo_url': url,
        }),
      );
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          final updated = Map<String, dynamic>.from(decoded);
          setState(() {
            final idx = _entries.indexWhere(
              (x) => (x['entry_id']?.toString() ?? '') == entryId,
            );
            if (idx >= 0) _entries[idx] = updated;
          });
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Foto bukti tersimpan.')),
          );
        }
      } else {
        if (mounted) {
          final msg = _messageFromStoreOpsBody(
            res.body,
            res.statusCode,
            'Gagal menyimpan foto bukti',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
      }
    }

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Bukti entri',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              Text('Jenis: ${kindLabel(income)}'),
              Text('Kategori: $cat'),
              Text('Nominal: ${money.format(value)}'),
              Text('Waktu: $whenStr'),
              if (notes.trim().isNotEmpty) Text('Ket: $notes'),
              const SizedBox(height: 12),
              if (proofUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    proofUrl,
                    height: 180,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Text('Gagal memuat foto bukti.'),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              FilledButton.icon(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await printStoreOperationalReceiptPdf(
                    context,
                    branchLabel: _branchLabel(),
                    branchIdForLogo: ref.read(userStateProvider).branch.trim(),
                    entry: e,
                  );
                },
                icon: const Icon(Icons.print_outlined),
                label: const Text('Cetak bukti'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await uploadOrChangePhoto();
                },
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(proofUrl == null ? 'Upload foto bukti' : 'Ubah foto bukti'),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Tutup'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _parseAmount(String raw) {
    final s = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final v = double.tryParse(s);
    return (v == null || v.isNaN || v.isInfinite) ? 0 : v;
  }

  String _messageFromStoreOpsBody(String body, int statusCode, String fallback) {
    try {
      final d = jsonDecode(body);
      if (d is Map) {
        final err = d['error']?.toString();
        final det = d['details']?.toString() ?? d['detail']?.toString();
        if (err != null && err.isNotEmpty) {
          return (det != null && det.isNotEmpty) ? '$err\n\n$det' : err;
        }
      }
    } catch (_) {}
    return '$fallback ($statusCode)';
  }

  Future<void> _loadEntries() async {
    final scope = _listScopeQuery();
    if (scope == null) {
      final u = ref.read(userStateProvider);
      setState(() {
        _loadingList = false;
        _listError = u.userId == null
            ? 'User belum login. Silakan login ulang.'
            : 'Cabang aktif tidak tersedia. Ganti cabang lewat profil lalu coba lagi.';
        _entries = [];
      });
      return;
    }

    setState(() {
      _loadingList = true;
      _listError = null;
    });

    try {
      final s = managerReportDateOnly(_rangeStart);
      final e = managerReportDateOnly(_rangeEnd);
      final periodQ = managerReportPeriodQueryParams(s, e);
      final res = await ApiClient.get(
        '/store-operational',
        query: {
          ...scope,
          ...periodQ,
        },
      );
      if (res.statusCode != 200) {
        setState(() {
          _loadingList = false;
          _listError = _messageFromStoreOpsBody(
            res.body,
            res.statusCode,
            'Gagal memuat data',
          );
          _entries = [];
        });
        return;
      }
      final decoded = jsonDecode(res.body);
      final uid = scope['user_id'];
      final filteredUid = int.tryParse(uid ?? '');
      List<Map<String, dynamic>> entries = [];
      if (decoded is List && filteredUid != null && filteredUid > 0) {
        entries = filterKasirOperationalForUser(decoded, filteredUid);
      }
      setState(() {
        _entries = entries;
        _loadingList = false;
      });
    } on UnauthorizedException catch (_) {
      if (mounted) {
        setState(() {
          _loadingList = false;
          _entries = [];
        });
      }
    } catch (e) {
      setState(() {
        _loadingList = false;
        _listError = '$e';
        _entries = [];
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final userState = ref.read(userStateProvider);
    final branch = userState.branch.trim();
    if (userState.userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User belum login. Silakan login ulang.')),
        );
      }
      return;
    }
    if (branch.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cabang aktif tidak tersedia. Ganti cabang lewat profil.',
            ),
          ),
        );
      }
      return;
    }

    final amount = _parseAmount(_amountController.text);
    if (amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nominal tidak valid.')),
        );
      }
      return;
    }

    final branchId = int.tryParse(branch);
    if (branchId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Branch ID tidak valid.')),
        );
      }
      return;
    }

    setState(() => _submitting = true);
    try {
      final proofUrl = await _ensureNewProofUploaded();
      if (_newProofX != null && (proofUrl == null || proofUrl.isEmpty)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upload foto bukti gagal. Coba lagi.')),
          );
        }
        return;
      }
      final res = await ApiClient.post(
        '/store-operational',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'branch_id': branchId,
          'amount': amount,
          'category': _category,
          'notes': _notesController.text.trim(),
          'entry_kind': _kind == _MoneyKind.income ? 'income' : 'expense',
          'proof_photo_url': proofUrl,
        }),
      );
      if (res.statusCode == 201) {
        _amountController.clear();
        _notesController.clear();
        _clearNewProof();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pencatatan tersimpan.')),
          );
        }
        await _loadEntries();
      } else {
        if (mounted) {
          final msg = _messageFromStoreOpsBody(
            res.body,
            res.statusCode,
            'Gagal menyimpan',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
      }
    } on UnauthorizedException catch (_) {
      // ApiClient sudah menangani sesi
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(userStateProvider, (prev, next) {
      if (prev?.branch != next.branch || prev?.userId != next.userId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadEntries();
        });
      }
    });

    final cs = Theme.of(context).colorScheme;
    final money = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final timeFmt = DateFormat('HH:mm');
    final dateTimeFmt = DateFormat('d MMM yyyy, HH:mm', 'id_ID');

    double sumIncome = 0;
    double sumExpense = 0;
    for (final e in _entries) {
      final amt = e['amount'];
      final n = amt is num
          ? amt.toDouble()
          : double.tryParse('$amt') ?? 0;
      if (_entryIsIncome(e)) {
        sumIncome += n;
      } else {
        sumExpense += n;
      }
    }
    final sumNet = sumIncome - sumExpense;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Keuangan Toko'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _scopeSubtitle(),
                style: Theme.of(context).textTheme.labelSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Cetak PDF',
            onPressed: (_loadingList || _entries.isEmpty) ? null : _printReport,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
            onPressed: _loadingList ? null : _loadEntries,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadEntries,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Catat pemasukan/pengeluaran operasional — hanya entri Anda di cabang aktif (di luar pembayaran order).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: AppTypography.bodySmall,
                  ),
            ),
            const SizedBox(height: 16),
            Material(
              elevation: 0,
              color: cs.surfaceContainerLow.withValues(alpha: 0.65),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Entri baru',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<_MoneyKind>(
                        segments: const [
                          ButtonSegment<_MoneyKind>(
                            value: _MoneyKind.expense,
                            label: Text('Pengeluaran'),
                            icon: Icon(Icons.south_east, size: 18),
                          ),
                          ButtonSegment<_MoneyKind>(
                            value: _MoneyKind.income,
                            label: Text('Pemasukan'),
                            icon: Icon(Icons.north_east, size: 18),
                          ),
                        ],
                        selected: {_kind},
                        onSelectionChanged: (s) {
                          setState(() {
                            _kind = s.first;
                            _category = _categoriesForKind.first;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey<String>('cat_$_kind'),
                        initialValue: _category,
                        decoration: const InputDecoration(
                          labelText: 'Kategori',
                          border: OutlineInputBorder(),
                        ),
                        items: _categoriesForKind
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _category = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Nominal (Rp)',
                          border: OutlineInputBorder(),
                          prefixText: 'Rp ',
                        ),
                        validator: (value) {
                          if (_parseAmount(value ?? '') <= 0) {
                            return 'Nominal wajib diisi';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Keterangan (opsional)',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (_submitting || _uploadingProof)
                                  ? null
                                  : () => _pickNewProof(ImageSource.camera),
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Kamera'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (_submitting || _uploadingProof)
                                  ? null
                                  : () => _pickNewProof(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('Galeri'),
                            ),
                          ),
                        ],
                      ),
                      if (_newProofX != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Foto bukti dipilih',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ),
                            TextButton(
                              onPressed:
                                  (_submitting || _uploadingProof) ? null : _clearNewProof,
                              child: const Text('Hapus'),
                            ),
                          ],
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: kIsWeb
                              ? Container(
                                  height: 160,
                                  color: cs.surfaceContainerHighest,
                                  alignment: Alignment.center,
                                  child: const Text('Preview tidak tersedia di web'),
                                )
                              : Image.file(
                                  File(_newProofX!.path),
                                  height: 160,
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ],
                      if (_uploadingProof) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: const [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text('Mengupload foto bukti...'),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Simpan'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daftar catatan',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        managerReportPeriodShortSubtitle(
                          managerReportDateOnly(_rangeStart),
                          managerReportDateOnly(_rangeEnd),
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _loadingList ? null : _pickDateRange,
                  icon: const Icon(Icons.date_range, size: 20),
                  label: const Text('Rentang'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                managerReportPeriodTitle(
                  managerReportDateOnly(_rangeStart),
                  managerReportDateOnly(_rangeEnd),
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            if (!_loadingList &&
                _listError == null &&
                _entries.isNotEmpty) ...[
              Material(
                elevation: 0,
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pemasukan',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            Text(
                              money.format(sumIncome),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.green.shade700,
                                fontSize: AppTypography.body,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pengeluaran',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            Text(
                              money.format(sumExpense),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: cs.error,
                                fontSize: AppTypography.body,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Saldo',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            Text(
                              money.format(sumNet),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: sumNet >= 0
                                    ? Colors.green.shade800
                                    : cs.error,
                                fontSize: AppTypography.body,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_loadingList)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_listError != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _listError!,
                  style: TextStyle(color: cs.error),
                ),
              )
            else if (_entries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Belum ada pemasukan atau pengeluaran pada periode ini.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              )
            else
              ..._entries.map((e) {
                final amt = e['amount'];
                final cat = e['category']?.toString() ?? '—';
                final notes = e['notes']?.toString() ?? '';
                final income = _entryIsIncome(e);
                final created = e['created_at'];
                DateTime? dt;
                if (created is String) {
                  dt = DateTime.tryParse(created);
                }
                final timeStr = dt != null
                    ? (_singleDayFilter
                        ? timeFmt.format(dt.toLocal())
                        : dateTimeFmt.format(dt.toLocal()))
                    : '—';
                final value = amt is num
                    ? amt.toDouble()
                    : double.tryParse('$amt') ?? 0;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => _openEntrySheet(e),
                    leading: CircleAvatar(
                      backgroundColor: income
                          ? Colors.green.shade50
                          : cs.errorContainer.withValues(alpha: 0.65),
                      foregroundColor:
                          income ? Colors.green.shade800 : cs.error,
                      child: Icon(
                        income ? Icons.north_east : Icons.south_east,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      cat,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          income ? 'Pemasukan' : 'Pengeluaran',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: income
                                    ? Colors.green.shade700
                                    : cs.error,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (notes.isNotEmpty) Text(notes),
                      ],
                    ),
                    isThreeLine: notes.isNotEmpty,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          money.format(value),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: income
                                ? Colors.green.shade800
                                : cs.error,
                            fontSize: AppTypography.body,
                          ),
                        ),
                        Text(
                          timeStr,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
