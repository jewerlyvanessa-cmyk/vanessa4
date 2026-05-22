import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/modules/admin_toko/utils/daily_orders_payments_helpers.dart';
import 'package:vanessa3/modules/admin_toko/widgets/daily_orders_daily_table.dart';
import 'package:vanessa3/utils/app_date_picker.dart';

/// Blok daftar order global (dashboard Owner atau halaman penuh).
class OwnerGlobalOrdersSection extends StatefulWidget {
  const OwnerGlobalOrdersSection({
    super.key,
    required this.ordersRaw,
    required this.loading,
    required this.error,
    required this.selectedDate,
    required this.onDateChanged,
    required this.onRefresh,
    this.showSectionTitle = true,
  });

  final List<Map<String, dynamic>> ordersRaw;
  final bool loading;
  final String error;
  final DateTime selectedDate;
  final Future<void> Function(DateTime date) onDateChanged;
  final VoidCallback onRefresh;
  final bool showSectionTitle;

  @override
  State<OwnerGlobalOrdersSection> createState() =>
      _OwnerGlobalOrdersSectionState();
}

class _OwnerGlobalOrdersSectionState extends State<OwnerGlobalOrdersSection> {
  AdminOrderFilter _orderFilter = AdminOrderFilter.all;

  List<dynamic> _filteredTableRaw() {
    return rawOrdersForTable(
      widget.ordersRaw,
      filter: _orderFilter,
      serviceCustomMode: false,
    );
  }

  int get _orderCount => dedupeOrdersById(_filteredTableRaw()).length;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE, d MMM yyyy', 'id_ID').format(
      widget.selectedDate,
    );
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showSectionTitle) ...[
          Text(
            'Daftar Order Global',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Semua cabang · hari ini atau tanggal dipilih',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.loading
                    ? null
                    : () async {
                        final picked = await showAppDatePicker(
                          context: context,
                          initialDate: widget.selectedDate,
                        );
                        if (picked != null) {
                          await widget.onDateChanged(picked);
                        }
                      },
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(dateLabel),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Muat ulang',
              onPressed: widget.loading ? null : widget.onRefresh,
              icon: const Icon(Icons.refresh),
            ),
            Chip(label: Text('$_orderCount order')),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: AdminOrderFilter.values.map((f) {
            return FilterChip(
              label: Text(
                adminOrderFilterLabel(f, serviceCustomMode: false),
              ),
              selected: _orderFilter == f,
              onSelected: widget.loading
                  ? null
                  : (_) => setState(() => _orderFilter = f),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        if (widget.loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (widget.error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Text(widget.error, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: widget.onRefresh,
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          )
        else
          DailyOrdersDailyTable(
            ordersRaw: widget.ordersRaw,
            filteredTableRaw: _filteredTableRaw(),
            emptyHint:
                'Tidak ada order pada tanggal ini di cabang yang terdaftar.',
            emptyFilterMessage: 'Tidak ada order untuk filter yang dipilih.',
            onOrderTap: (_) {},
            statusCellBuilder: (row) {
              final branch = (row['branch_name'] ?? '').toString();
              final status = (row['status'] ?? '-').toString();
              if (branch.isEmpty) {
                return Text(status);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(status, style: const TextStyle(fontSize: 12)),
                  Text(
                    branch,
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            },
            filterDeduped: (deduped) => deduped,
          ),
      ],
    );
  }
}
