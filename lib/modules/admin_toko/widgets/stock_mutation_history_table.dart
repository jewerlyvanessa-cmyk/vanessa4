import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/modules/admin_toko/logic/stock_mutation_utils.dart';
import 'package:vanessa3/modules/admin_toko/widgets/stock_mutation_detail_sheet.dart';

class StockMutationHistoryTable extends StatelessWidget {
  const StockMutationHistoryTable({
    super.key,
    required this.mutations,
  });

  final List<dynamic> mutations;

  static Widget _headCell(
    String label, {
    TextAlign align = TextAlign.left,
    bool compact = false,
  }) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 9 : 10,
        ),
        child: Text(
          label,
          textAlign: align,
          style: TextStyle(
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  static Widget _bodyCell({
    required Widget child,
    required VoidCallback onTap,
    bool compact = false,
    Alignment align = Alignment.centerLeft,
  }) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: InkWell(
        onTap: onTap,
        child: Container(
          alignment: align,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 9 : 10,
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (mutations.isEmpty) {
      return const Center(child: Text('Tidak ada data mutasi'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 600;
        final extraCompact = constraints.maxWidth < 420;
        final cs = Theme.of(context).colorScheme;
        final minW =
            narrow ? constraints.maxWidth : math.max(constraints.maxWidth, 800.0);
        final showNotesColumn = !narrow;
        final showTypeColumn = !narrow;
        final borderColor = cs.outlineVariant.withValues(alpha: 0.45);
        final tableRows = <TableRow>[
          TableRow(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            children: [
              _headCell('Item', compact: extraCompact),
              _headCell('Jumlah', align: TextAlign.right, compact: extraCompact),
              _headCell('Tanggal', compact: extraCompact),
              if (showNotesColumn)
                _headCell('Keterangan', compact: extraCompact),
              if (showTypeColumn) _headCell('Tipe', compact: extraCompact),
            ],
          ),
        ];

        for (var i = 0; i < mutations.length; i++) {
          final mutation =
              Map<String, dynamic>.from(mutations[i] as Map);
          final typeLabel = StockMutationUtils.typeLabel(mutation);
          final typeColor = StockMutationUtils.typeColor(mutation);
          final description = StockMutationUtils.description(mutation);
          String dateStr = '—';
          try {
            dateStr = DateFormat('dd/MM/yyyy HH:mm', 'id_ID').format(
              DateTime.parse(mutation['created_at']?.toString() ?? ''),
            );
          } catch (_) {}
          final descShort = description.length > 48
              ? '${description.substring(0, 45)}…'
              : description;
          void onRowTap() {
            showStockMutationDetailSheet(context, mutation);
          }

          final baseTextStyle = TextStyle(fontSize: extraCompact ? 11.5 : 12.5);
          tableRows.add(
            TableRow(
              decoration: BoxDecoration(
                color: i.isOdd
                    ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
                    : null,
              ),
              children: [
                _bodyCell(
                  compact: extraCompact,
                  onTap: onRowTap,
                  child: Row(
                    children: [
                      StockMutationUtils.typeIcon(mutation),
                      SizedBox(width: extraCompact ? 4 : 8),
                      Expanded(
                        child: Text(
                          '${mutation['item_name'] ?? '—'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: baseTextStyle.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _bodyCell(
                  compact: extraCompact,
                  onTap: onRowTap,
                  align: Alignment.centerRight,
                  child: Text(
                    '${mutation['quantity'] ?? '—'} pcs',
                    textAlign: TextAlign.right,
                    style: baseTextStyle,
                  ),
                ),
                _bodyCell(
                  compact: extraCompact,
                  onTap: onRowTap,
                  child: Text(
                    dateStr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: baseTextStyle,
                  ),
                ),
                if (showNotesColumn)
                  _bodyCell(
                    compact: extraCompact,
                    onTap: onRowTap,
                    child: Text(
                      description == '—' ? '—' : descShort,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: baseTextStyle.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                if (showTypeColumn)
                  _bodyCell(
                    compact: extraCompact,
                    onTap: onRowTap,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: extraCompact ? 6 : 8,
                          vertical: extraCompact ? 2 : 4,
                        ),
                        decoration: BoxDecoration(
                          color: typeColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          typeLabel,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: extraCompact ? 10 : 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        final columnWidths = narrow
            ? const <int, TableColumnWidth>{
                0: FlexColumnWidth(2.4),
                1: FlexColumnWidth(1.0),
                2: FlexColumnWidth(1.7),
              }
            : const <int, TableColumnWidth>{
                0: FlexColumnWidth(2.0),
                1: FlexColumnWidth(1.0),
                2: FlexColumnWidth(1.5),
                3: FlexColumnWidth(2.0),
                4: FlexColumnWidth(1.0),
              };

        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: borderColor),
          ),
          child: Scrollbar(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: minW),
                child: Table(
                  columnWidths: columnWidths,
                  border: TableBorder(
                    horizontalInside: BorderSide(color: borderColor),
                  ),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: tableRows,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
