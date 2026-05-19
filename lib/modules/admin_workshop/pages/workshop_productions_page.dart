import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/order_status_ui.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

/// Admin workshop: lacak perhiasan yang dibuat tukang dari stok material.
class WorkshopProductionsPage extends ConsumerStatefulWidget {
  const WorkshopProductionsPage({super.key});

  @override
  ConsumerState<WorkshopProductionsPage> createState() =>
      _WorkshopProductionsPageState();
}

class _WorkshopProductionsPageState
    extends ConsumerState<WorkshopProductionsPage> {
  static const _periods = ['today', 'week', 'month', 'all'];

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String _period = 'month';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final branch = ref.read(userStateProvider).branch;
      final rows = await ApiService.getWorkshopProductions(
        branch,
        period: _period,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _fmtDate(dynamic raw) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return DateFormat('dd MMM yyyy HH:mm').format(dt);
    } catch (_) {
      return raw.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Produksi Tukang'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              children: _periods.map((p) {
                final labels = {
                  'today': 'Hari ini',
                  'week': '7 hari',
                  'month': '30 hari',
                  'all': 'Semua',
                };
                return FilterChip(
                  label: Text(labels[p] ?? p),
                  selected: _period == p,
                  onSelected: (_) {
                    setState(() => _period = p);
                    _load();
                  },
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton.tonal(
                                onPressed: _load,
                                child: const Text('Coba lagi'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _rows.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.diamond_outlined,
                                  size: 48,
                                  color: cs.onSurfaceVariant
                                      .withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 12),
                                const Text('Belum ada produksi tercatat'),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              physics: ResponsiveLayout.scrollPhysics,
                              padding: ResponsiveLayout.safeScrollPadding(
                                context,
                              ),
                              itemCount: _rows.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final r = _rows[i];
                                final orderId = r['order_id']?.toString();
                                final status = r['order_status']?.toString();
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.diamond,
                                              color: cs.primary,
                                              size: 22,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                r['output_name']?.toString() ??
                                                    '—',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize:
                                                      AppTypography.section,
                                                ),
                                              ),
                                            ),
                                            if (orderId != null &&
                                                orderId.isNotEmpty)
                                              Chip(
                                                label: Text('Order #$orderId'),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              )
                                            else
                                              Chip(
                                                label: const Text('Mandiri'),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Kode: ${r['output_kode'] ?? '—'} · '
                                          '${r['output_weight'] ?? '—'} g · '
                                          '${r['output_material'] ?? ''} '
                                          '${r['output_purity'] ?? ''}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Bahan: ${r['material_name'] ?? '—'} '
                                          '(${r['material_qty_used'] ?? '—'} dipakai)',
                                          style: TextStyle(
                                            fontSize: AppTypography.bodySmall,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Tukang: ${r['technician_name'] ?? r['technician_id'] ?? '—'} · '
                                          '${_fmtDate(r['created_at'])}',
                                          style: TextStyle(
                                            fontSize: AppTypography.bodySmall,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                        if (status != null &&
                                            status.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            'Status order: ${OrderStatusUi.label(status)}',
                                            style: TextStyle(
                                              fontSize: AppTypography.bodySmall,
                                              color: cs.secondary,
                                            ),
                                          ),
                                        ],
                                        if ((r['production_notes'] ?? '')
                                            .toString()
                                            .trim()
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            r['production_notes'].toString(),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  fontStyle: FontStyle.italic,
                                                ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
