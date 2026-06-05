import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/modules/cs/logic/customers_utils.dart';

/// Bottom sheet riwayat transaksi global pelanggan.
/// Caller wajib cek [CustomersUtils.canSeeGlobalTransactions] sebelum memanggil.
void showCustomerTransactionsSheet(
  BuildContext context,
  Map<String, dynamic> customer,
) {
  final customerId = (customer['customer_id'] ?? '').toString();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer['name'] ?? 'Pelanggan',
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '📞 ${customer['phone'] ?? 'N/A'}',
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Riwayat Transaksi (Global)',
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        showCustomerTransactionsSheet(context, customer);
                      },
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: CustomersUtils.fetchCustomerTransactions(
                      customerId: customerId,
                      branchId: null,
                    ),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 56,
                                color: Colors.red,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                snap.error.toString(),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      }

                      final rows = snap.data ?? const [];
                      final totalNilai =
                          CustomersUtils.sumTransactionAmounts(rows);
                      final cs = Theme.of(context).colorScheme;
                      final tt = Theme.of(context).textTheme;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total nilai transaksi: Rp ${CustomersUtils.fmtRp(totalNilai)}',
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: rows.isEmpty
                                ? const Center(
                                    child: Text(
                                      'Belum ada transaksi untuk pelanggan ini',
                                    ),
                                  )
                                : LayoutBuilder(
                                    builder: (context, c) {
                                      final minW = math.max(c.maxWidth, 400.0);
                                      final dataRows = <DataRow>[];
                                      for (var i = 0; i < rows.length; i++) {
                                        final r = rows[i];
                                        final orderType =
                                            (r['order_type'] ?? '')
                                                .toString()
                                                .trim();
                                        final jenis =
                                            orderType.isEmpty ? '—' : orderType;
                                        final amount =
                                            r['jumlah'] ?? r['total'] ?? 0;

                                        dataRows.add(
                                          DataRow(
                                            color: WidgetStateProperty
                                                .resolveWith((s) {
                                              if (s.contains(
                                                WidgetState.hovered,
                                              )) {
                                                return cs.primary.withValues(
                                                  alpha: 0.06,
                                                );
                                              }
                                              return i.isOdd
                                                  ? cs.surfaceContainerHighest
                                                      .withValues(alpha: 0.45)
                                                  : null;
                                            }),
                                            cells: [
                                              DataCell(
                                                Text(
                                                  CustomersUtils.fmtDateTime(
                                                    r['created_at'],
                                                  ),
                                                  style: tt.bodyMedium,
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  jenis,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: tt.bodyMedium,
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  'Rp ${CustomersUtils.fmtRp(amount)}',
                                                  style:
                                                      tt.titleSmall?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    color: cs.primary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                      return Material(
                                        elevation: 0,
                                        color: cs.surfaceContainerLow
                                            .withValues(alpha: 0.65),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          side: BorderSide(
                                            color: cs.outlineVariant
                                                .withValues(alpha: 0.45),
                                          ),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: Scrollbar(
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(
                                                minWidth: minW,
                                              ),
                                              child: SingleChildScrollView(
                                                child: DataTable(
                                                  headingRowColor:
                                                      WidgetStateProperty.all(
                                                    cs.surfaceContainerHigh,
                                                  ),
                                                  dataRowMinHeight: 40,
                                                  dataRowMaxHeight: 56,
                                                  columnSpacing: 12,
                                                  horizontalMargin: 10,
                                                  showCheckboxColumn: false,
                                                  dividerThickness: 0.5,
                                                  columns: [
                                                    DataColumn(
                                                      label:
                                                          dataTableColumnLabel(
                                                        'Tanggal',
                                                      ),
                                                    ),
                                                    DataColumn(
                                                      label:
                                                          dataTableColumnLabel(
                                                        'Jenis',
                                                      ),
                                                    ),
                                                    DataColumn(
                                                      label:
                                                          dataTableColumnLabel(
                                                        'Total',
                                                        numeric: true,
                                                      ),
                                                    ),
                                                  ],
                                                  rows: dataRows,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
