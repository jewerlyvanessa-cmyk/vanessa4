import 'package:flutter/material.dart';
import 'package:vanessa3/modules/admin_toko/logic/stock_mutation_utils.dart';

void showStockMutationDetailSheet(
  BuildContext context,
  Map<String, dynamic> mutation,
) {
  final typeLabel = StockMutationUtils.typeLabel(mutation);
  final typeColor = StockMutationUtils.typeColor(mutation);
  final description = StockMutationUtils.description(mutation);
  final qty = (mutation['quantity'] ?? '').toString();
  final createdAt = StockMutationUtils.formatDateTime(mutation['created_at']);
  final itemName = (mutation['item_name'] ?? '-').toString();
  final branchName = (mutation['branch_name'] ?? '-').toString();
  final systemNote = (mutation['notes'] ?? '').toString().trim();
  final prevStock = (mutation['previous_stock'] ?? '-').toString();
  final currStock = (mutation['current_stock'] ?? '-').toString();
  final createdBy =
      (mutation['created_by_name'] ?? mutation['created_by'] ?? '-').toString();
  final orderNo = (mutation['order_number'] ?? '').toString().trim();
  final customerName = (mutation['customer_name'] ?? '').toString().trim();
  final transferFlow = [
    mutation['transfer_from_branch_name']?.toString(),
    mutation['transfer_to_branch_name']?.toString(),
  ].whereType<String>().where((x) => x.trim().isNotEmpty).join(' → ');
  final humanizedSystemNote = systemNote.isNotEmpty
      ? StockMutationUtils.humanizeBranchIdsInNotes(systemNote, mutation)
      : '';
  final showSystemNote =
      humanizedSystemNote.isNotEmpty && humanizedSystemNote != description;

  Widget detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Detail Riwayat Mutasi',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                detailRow('Item', itemName),
                detailRow('Jenis', typeLabel),
                detailRow('Keterangan', description),
                detailRow('Jumlah', '$qty pcs'),
                detailRow('Cabang', branchName),
                detailRow('Waktu', createdAt),
                detailRow('Stok Sebelum', prevStock),
                detailRow('Stok Sesudah', currStock),
                detailRow('Dibuat Oleh', createdBy),
                if (orderNo.isNotEmpty) detailRow('No. Order', orderNo),
                if (customerName.isNotEmpty) detailRow('Pelanggan', customerName),
                if (transferFlow.isNotEmpty) detailRow('Alur Transfer', transferFlow),
                if (showSystemNote) detailRow('Catatan sistem', humanizedSystemNote),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: cs.surfaceContainerLow,
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    typeLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: typeColor,
                    ),
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
