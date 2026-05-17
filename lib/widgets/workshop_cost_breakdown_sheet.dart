import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/data/api_service.dart';

final _moneyFmt = NumberFormat('#,###', 'id_ID');

/// Editor biaya workshop (material / jasa / lain) → backend menyinkronkan [orders.total].
Future<void> showWorkshopCostBreakdownSheet(
  BuildContext context, {
  required int orderId,
  required String branchId,
  VoidCallback? onSaved,
  /// Jika true, material / ongkos / lain-lain boleh semuanya 0.
  bool allowAllZeroCosts = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: _WorkshopCostBreakdownBody(
          orderId: orderId,
          branchId: branchId,
          allowAllZeroCosts: allowAllZeroCosts,
          onSaved: () {
            Navigator.of(ctx).pop();
            onSaved?.call();
          },
        ),
      );
    },
  );
}

class _WorkshopCostBreakdownBody extends StatefulWidget {
  const _WorkshopCostBreakdownBody({
    required this.orderId,
    required this.branchId,
    required this.onSaved,
    this.allowAllZeroCosts = false,
  });

  final int orderId;
  final String branchId;
  final VoidCallback onSaved;
  final bool allowAllZeroCosts;

  @override
  State<_WorkshopCostBreakdownBody> createState() =>
      _WorkshopCostBreakdownBodyState();
}

class _WorkshopCostBreakdownBodyState extends State<_WorkshopCostBreakdownBody> {
  final _materialCtrl = TextEditingController();
  final _laborCtrl = TextEditingController();
  final _otherCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  int? _lastRevision;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _materialCtrl.dispose();
    _laborCtrl.dispose();
    _otherCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final data = await ApiService.getOrderCostBreakdown(
        widget.orderId,
        widget.branchId,
      );
      final latest = data['latest'];
      if (latest is Map) {
        _materialCtrl.text = _fmtNum(latest['material_cost']);
        _laborCtrl.text = _fmtNum(latest['labor_cost']);
        _otherCtrl.text = _fmtNum(latest['other_cost']);
        final n = latest['notes']?.toString().trim();
        if (n != null && n.isNotEmpty) _notesCtrl.text = n;
        _lastRevision = int.tryParse(latest['revision']?.toString() ?? '');
      }
    } catch (e) {
      _loadError = e.toString();
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  static String _fmtNum(dynamic v) {
    final n = num.tryParse(v?.toString() ?? '') ?? 0;
    if (n == 0) return '';
    return n.toString();
  }

  double _parseField(TextEditingController c) {
    final t = c.text.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(t) ?? 0;
  }

  Future<void> _save() async {
    final m = _parseField(_materialCtrl);
    final l = _parseField(_laborCtrl);
    final o = _parseField(_otherCtrl);
    if (m < 0 || l < 0 || o < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nilai biaya tidak boleh negatif')),
      );
      return;
    }
    if (!widget.allowAllZeroCosts && m + l + o <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi minimal satu komponen biaya > 0')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final res = await ApiService.submitOrderCostBreakdown(
        orderId: widget.orderId,
        branchId: widget.branchId,
        materialCost: m,
        laborCost: l,
        otherCost: o,
        notes: _notesCtrl.text.trim(),
      );
      final total = res['order_total'];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              total != null
                  ? 'Biaya disimpan. Total tagihan: Rp ${_moneyFmt.format(num.tryParse(total.toString()) ?? 0)}'
                  : 'Biaya disimpan',
            ),
          ),
        );
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Biaya aktual · Order #${widget.orderId}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Ini biaya final workshop (bukan estimasi). Total tagihan di kasir diperbarui; sisa bayar = total − DP.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            if (_lastRevision != null) ...[
              const SizedBox(height: 8),
              Text(
                'Revisi terakhir di form: #$_lastRevision (akan bertambah saat simpan)',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (_loadError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _loadError!,
                    style: TextStyle(color: cs.error, fontSize: 12),
                  ),
                ),
              TextField(
                controller: _materialCtrl,
                decoration: const InputDecoration(
                  labelText: 'Material',
                  prefixText: 'Rp ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _laborCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ongkos',
                  prefixText: 'Rp ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _otherCtrl,
                decoration: const InputDecoration(
                  labelText: 'Lain-lain',
                  prefixText: 'Rp ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Batal'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Simpan & update tagihan'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
