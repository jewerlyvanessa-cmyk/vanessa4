import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/core/network/api_exceptions.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/modules/kasir/logic/store_operational_form_constants.dart';
import 'package:vanessa3/modules/kasir/logic/store_operational_types.dart';
import 'package:vanessa3/modules/kasir/logic/store_operational_utils.dart';
import 'package:vanessa3/modules/kasir/widgets/store_operational_entries_list.dart';
import 'package:vanessa3/modules/kasir/widgets/store_operational_entry_form.dart';
import 'package:vanessa3/modules/kasir/widgets/store_operational_entry_sheet.dart';
import 'package:vanessa3/modules/kasir/widgets/store_operational_summary_card.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/shared_widgets/manager_report_period_selector.dart';
import 'package:vanessa3/utils/app_date_picker.dart';
import 'package:vanessa3/utils/cs_order_photo_picker.dart';
import 'package:vanessa3/utils/cs_order_photo_upload.dart';
import 'package:vanessa3/utils/kasir_scope_filter.dart';
import 'package:vanessa3/utils/store_operational_print.dart';
import 'package:vanessa3/modules/manajer/widgets/store_operational_categories_sheet.dart';

export 'package:vanessa3/modules/kasir/logic/store_operational_types.dart';

/// Pencatatan pemasukan & pengeluaran operasional toko (bukan pembayaran order) per cabang.
class KeuanganTokoPage extends ConsumerStatefulWidget {
  const KeuanganTokoPage({
    super.key,
    this.scope = StoreOperationalPageScope.kasir,
    this.title,
  });

  final StoreOperationalPageScope scope;
  final String? title;

  @override
  ConsumerState<KeuanganTokoPage> createState() => _KeuanganTokoPageState();
}

class _KeuanganTokoPageState extends ConsumerState<KeuanganTokoPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  StoreOperationalMoneyKind _kind = StoreOperationalMoneyKind.expense;
  String _category = StoreOperationalFormConstants.expenseCategories.first;

  List<String> _apiExpenseCategories = [];
  List<String> _apiIncomeCategories = [];
  bool _loadingCategories = false;
  String? _categoriesError;

  List<String> get _categoriesForKind {
    if (_kind == StoreOperationalMoneyKind.income) {
      return _apiIncomeCategories.isNotEmpty
          ? _apiIncomeCategories
          : StoreOperationalFormConstants.incomeCategories;
    }
    return _apiExpenseCategories.isNotEmpty
        ? _apiExpenseCategories
        : StoreOperationalFormConstants.expenseCategories;
  }

  CsOrderPhotoPickResult? _newProofPick;
  String? _newProofUrl;
  bool _uploadingProof = false;

  List<Map<String, dynamic>> _entries = [];
  bool _loadingList = true;
  bool _submitting = false;
  String? _listError;
  late DateTime _rangeStart;
  late DateTime _rangeEnd;

  bool get _isManajer =>
      widget.scope == StoreOperationalPageScope.manajer;

  String get _pageTitle =>
      widget.title ?? (_isManajer ? 'Pencatatan Keuangan' : 'Keuangan Toko');

  String get _activeBranchId => ref.read(userStateProvider).branch.trim();

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadCategories();
      await _loadEntries();
    });
  }

  void _syncSelectedCategory() {
    final list = _categoriesForKind;
    if (list.isEmpty) return;
    if (!list.contains(_category)) {
      setState(() => _category = list.first);
    }
  }

  Future<void> _loadCategories() async {
    if (!mounted) return;
    setState(() {
      _loadingCategories = true;
      _categoriesError = null;
    });
    try {
      final res = await ApiClient.get('/store-operational/categories');
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() {
          _loadingCategories = false;
          _categoriesError =
              StoreOperationalUtils.categoriesLoadHint(res.statusCode);
          _apiExpenseCategories =
              List<String>.from(StoreOperationalFormConstants.expenseCategories);
          _apiIncomeCategories =
              List<String>.from(StoreOperationalFormConstants.incomeCategories);
        });
        _syncSelectedCategory();
        return;
      }
      final decoded = jsonDecode(res.body);
      final all = decoded is List
          ? decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      final expense = <String>[];
      final income = <String>[];
      for (final row in all) {
        final name = row['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        if (row['entry_kind']?.toString() == 'income') {
          income.add(name);
        } else {
          expense.add(name);
        }
      }
      setState(() {
        _loadingCategories = false;
        _apiExpenseCategories = expense.isNotEmpty
            ? expense
            : List<String>.from(StoreOperationalFormConstants.expenseCategories);
        _apiIncomeCategories = income.isNotEmpty
            ? income
            : List<String>.from(StoreOperationalFormConstants.incomeCategories);
      });
      _syncSelectedCategory();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingCategories = false;
        _categoriesError = null;
        _apiExpenseCategories =
            List<String>.from(StoreOperationalFormConstants.expenseCategories);
        _apiIncomeCategories =
            List<String>.from(StoreOperationalFormConstants.incomeCategories);
      });
      _syncSelectedCategory();
    }
  }

  Future<void> _openCategoryManager() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const StoreOperationalCategoriesSheet(),
    );
    if (mounted) await _loadCategories();
  }

  bool get _singleDayFilter {
    final s = managerReportDateOnly(_rangeStart);
    final e = managerReportDateOnly(_rangeEnd);
    return managerReportSameCalendarDay(s, e);
  }

  String _scopeSubtitle() {
    return StoreOperationalUtils.scopeSubtitle(
      isManajer: _isManajer,
      user: ref.read(userStateProvider),
    );
  }

  Future<void> _pickDateRange() async {
    final today = managerReportDateOnly(DateTime.now());
    final picked = await showAppDateRangePicker(
      context: context,
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
          content: Text('Rentang maksimal $kManagerReportMaxRangeDays hari.'),
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
      branchLabel: StoreOperationalUtils.branchLabel(
        ref.read(userStateProvider),
        _activeBranchId,
      ),
      branchIdForLogo: _activeBranchId,
      periodStart: _rangeStart,
      periodEnd: _rangeEnd,
      entries: _entries,
    );
  }

  Future<void> _pickNewProofFromCamera() async {
    try {
      final pick = await CsOrderPhotoPicker.pickFromCamera(imageQuality: 80);
      if (pick == null || !pick.hasPhoto) return;
      setState(() {
        _newProofPick = pick;
        _newProofUrl = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? 'Kamera web gagal. Izinkan akses kamera, atau gunakan Pilih File.'
                : 'Gagal ambil foto: $e',
          ),
        ),
      );
    }
  }

  Future<void> _pickNewProofFromGallery() async {
    try {
      final pick = await CsOrderPhotoPicker.pickFromGallery(imageQuality: 80);
      if (pick == null || !pick.hasPhoto) return;
      setState(() {
        _newProofPick = pick;
        _newProofUrl = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memilih foto: $e')),
      );
    }
  }

  void _clearNewProof() {
    setState(() {
      _newProofPick = null;
      _newProofUrl = null;
    });
  }

  Future<String?> _ensureNewProofUploaded() async {
    if (_newProofUrl != null && _newProofUrl!.trim().isNotEmpty) {
      return _newProofUrl;
    }
    final pick = _newProofPick;
    if (pick == null || !pick.hasPhoto) return null;

    setState(() => _uploadingProof = true);
    try {
      final url = await CsOrderPhotoUpload.upload(
        file: pick.file,
        bytes: pick.bytes,
        fileName: pick.fileName,
      );
      if (url == null || url.trim().isEmpty) return null;
      setState(() => _newProofUrl = url);
      return url;
    } finally {
      if (mounted) setState(() => _uploadingProof = false);
    }
  }

  Future<void> _openEntrySheet(Map<String, dynamic> e) async {
    final user = ref.read(userStateProvider);
    await showStoreOperationalEntrySheet(
      context: context,
      entry: e,
      branchId: _activeBranchId,
      branchLabel: StoreOperationalUtils.branchLabel(user, _activeBranchId),
      branchIdForLogo: _activeBranchId,
      authToken: user.authToken,
      onEntryUpdated: (updated) {
        setState(() {
          final entryId = updated['entry_id']?.toString() ?? '';
          final idx = _entries.indexWhere(
            (x) => (x['entry_id']?.toString() ?? '') == entryId,
          );
          if (idx >= 0) _entries[idx] = updated;
        });
      },
    );
  }

  Future<void> _loadEntries() async {
    final user = ref.read(userStateProvider);
    final scope = StoreOperationalUtils.listScopeQuery(
      isManajer: _isManajer,
      user: user,
    );
    if (scope == null) {
      setState(() {
        _loadingList = false;
        _listError = user.userId == null
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
      final res = await ApiClient.get(
        '/store-operational',
        query: {
          ...scope,
          ...managerReportPeriodQueryParams(s, e),
        },
      );
      if (res.statusCode != 200) {
        setState(() {
          _loadingList = false;
          _listError = StoreOperationalUtils.messageFromStoreOpsBody(
            res.body,
            res.statusCode,
            'Gagal memuat data',
          );
          _entries = [];
        });
        return;
      }
      final decoded = jsonDecode(res.body);
      final List<Map<String, dynamic>> entries;
      if (_isManajer) {
        entries = decoded is List
            ? decoded
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
            : <Map<String, dynamic>>[];
      } else {
        final filteredUid = int.tryParse(scope['user_id'] ?? '') ?? 0;
        entries = filteredUid > 0
            ? parseKasirOperationalListResponse(
                decoded,
                filteredUid,
                requestedUserScope: true,
              )
            : <Map<String, dynamic>>[];
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
    final branch = _activeBranchId;
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

    final amount = StoreOperationalUtils.parseAmount(_amountController.text);
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
      if (_newProofPick != null &&
          _newProofPick!.hasPhoto &&
          (proofUrl == null || proofUrl.isEmpty)) {
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
          'entry_kind': _kind == StoreOperationalMoneyKind.income
              ? 'income'
              : 'expense',
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
      } else if (mounted) {
        final msg = StoreOperationalUtils.messageFromStoreOpsBody(
          res.body,
          res.statusCode,
          'Gagal menyimpan',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
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
      if (!_isManajer &&
          (prev?.branch != next.branch || prev?.userId != next.userId)) {
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
    final totals = StoreOperationalUtils.sumEntries(_entries);

    return Scaffold(
      appBar: AppBar(
        title: Text(_pageTitle),
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
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Kelola kategori',
            onPressed: _openCategoryManager,
          ),
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
        onRefresh: () async {
          await Future.wait([_loadCategories(), _loadEntries()]);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              _isManajer
                  ? 'Catat uang masuk dan uang keluar operasional cabang aktif (di luar pembayaran order).'
                  : 'Catat pemasukan/pengeluaran operasional — hanya entri Anda di cabang aktif (di luar pembayaran order).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: AppTypography.bodySmall,
                  ),
            ),
            const SizedBox(height: 16),
            StoreOperationalEntryForm(
              formKey: _formKey,
              kind: _kind,
              onKindChanged: (v) {
                setState(() => _kind = v);
                _syncSelectedCategory();
              },
              category: _category,
              onCategoryChanged: (v) => setState(() => _category = v),
              categories: _categoriesForKind,
              loadingCategories: _loadingCategories,
              categoriesError: _categoriesError,
              amountController: _amountController,
              notesController: _notesController,
              submitting: _submitting,
              uploadingProof: _uploadingProof,
              newProofPick: _newProofPick,
              onPickCamera: _pickNewProofFromCamera,
              onPickGallery: _pickNewProofFromGallery,
              onClearProof: _clearNewProof,
              onOpenCategoryManager: _openCategoryManager,
              onSubmit: _submit,
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
            if (!_loadingList && _listError == null && _entries.isNotEmpty) ...[
              StoreOperationalSummaryCard(
                sumIncome: totals.income,
                sumExpense: totals.expense,
                sumNet: totals.net,
                money: money,
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
                child: Text(_listError!, style: TextStyle(color: cs.error)),
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
              StoreOperationalEntriesList(
                entries: _entries,
                money: money,
                timeFmt: timeFmt,
                dateTimeFmt: dateTimeFmt,
                singleDayFilter: _singleDayFilter,
                showUserId: _isManajer,
                onEntryTap: _openEntrySheet,
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
