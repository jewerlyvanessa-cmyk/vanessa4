import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

/// Dialog pilih item dari order jual (buyback, service, dll).
abstract final class CsOrderItemSelectionDialog {
  CsOrderItemSelectionDialog._();

  static String _itemLabel(Map<String, dynamic> item) {
    return (item['nama_item'] ??
            item['item_name'] ??
            item['name'] ??
            'Unknown Item')
        .toString();
  }

  static Future<Map<String, dynamic>?> show(
    BuildContext context,
    List<dynamic> items, {
    String title = 'Pilih Item',
    String Function(Map<String, dynamic> item)? itemLabel,
  }) {
    final labelFor = itemLabel ?? _itemLabel;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        final dataRows = <DataRow>[];
        for (var i = 0; i < items.length; i++) {
          final item = items[i] as Map<String, dynamic>;
          final picked = Map<String, dynamic>.from(item);
          dataRows.add(
            DataRow(
              color: WidgetStateProperty.resolveWith((s) {
                if (s.contains(WidgetState.hovered)) {
                  return cs.primary.withValues(alpha: 0.06);
                }
                return i.isOdd
                    ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
                    : null;
              }),
              onSelectChanged: (_) => Navigator.of(dialogContext).pop(picked),
              cells: [
                DataCell(Text(labelFor(item))),
                DataCell(Text('${item['kode_produk'] ?? '—'}')),
              ],
            ),
          );
        }
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            height: math.min(
              360.0,
              MediaQuery.sizeOf(dialogContext).height * 0.5,
            ),
            child: Material(
              elevation: 0,
              color: cs.surfaceContainerLow.withValues(alpha: 0.65),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      cs.surfaceContainerHigh,
                    ),
                    dataRowMinHeight: 40,
                    columnSpacing: 12,
                    horizontalMargin: 12,
                    showCheckboxColumn: false,
                    columns: [
                      DataColumn(label: dataTableColumnLabel('Item')),
                      DataColumn(label: dataTableColumnLabel('Kode')),
                    ],
                    rows: dataRows,
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Batal'),
            ),
          ],
        );
      },
    );
  }
}
