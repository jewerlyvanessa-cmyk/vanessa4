import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

abstract final class StockMutationUtils {
  StockMutationUtils._();

  static int qty(Map<String, dynamic> m) {
    return int.tryParse(m['quantity']?.toString() ?? '') ?? 0;
  }

  static String typeLabel(Map<String, dynamic> m) {
    final type = (m['type'] ?? '').toString();
    final ref = (m['reference_type'] ?? '').toString();
    final qtyVal = qty(m);
    final orderType =
        (m['order_type'] ?? '').toString().trim().toLowerCase();

    if (type == 'transfer') {
      return qtyVal >= 0 ? 'Transfer masuk' : 'Transfer keluar';
    }
    if (type == 'in') {
      if (ref == 'item_create') return 'Stok baru';
      if (ref == 'restock') return 'Restok';
      if (ref == 'order' && orderType == 'buyback') return 'Buyback';
      return 'Stok masuk';
    }
    if (type == 'out') {
      if (ref == 'order') return 'Penjualan';
      return 'Stok keluar';
    }
    if (type == 'adjustment') {
      if (ref == 'opname') return 'Stok opname';
      return 'Koreksi';
    }
    return 'Lainnya';
  }

  static Color typeColor(Map<String, dynamic> m) {
    final type = (m['type'] ?? '').toString();
    final qtyVal = qty(m);
    if (type == 'transfer') {
      return qtyVal >= 0 ? Colors.blue : Colors.orange;
    }
    switch (type) {
      case 'in':
        return Colors.green;
      case 'out':
        return Colors.red;
      case 'adjustment':
        return Colors.blueGrey;
      default:
        return Colors.blue;
    }
  }

  static Icon typeIcon(Map<String, dynamic> m) {
    final color = typeColor(m);
    final qtyVal = qty(m);
    final type = (m['type'] ?? '').toString();
    if (type == 'transfer') {
      return Icon(
        qtyVal >= 0 ? Icons.arrow_downward : Icons.arrow_upward,
        color: color,
        size: 20,
      );
    }
    switch (type) {
      case 'in':
        return Icon(Icons.arrow_downward, color: color, size: 20);
      case 'out':
        return Icon(Icons.arrow_upward, color: color, size: 20);
      default:
        return Icon(Icons.swap_horiz, color: color, size: 20);
    }
  }

  static String humanizeBranchIdsInNotes(String note, Map<String, dynamic> m) {
    var s = note;
    final fromId = m['transfer_from_branch_id']?.toString().trim();
    final toId = m['transfer_to_branch_id']?.toString().trim();
    final fromName =
        (m['transfer_from_branch_name'] ?? '').toString().trim();
    final toName = (m['transfer_to_branch_name'] ?? '').toString().trim();
    if (fromId != null && fromId.isNotEmpty && fromName.isNotEmpty) {
      s = s.replaceAll(
        RegExp('branch\\s*$fromId', caseSensitive: false),
        fromName,
      );
    }
    if (toId != null && toId.isNotEmpty && toName.isNotEmpty) {
      s = s.replaceAll(
        RegExp('branch\\s*$toId', caseSensitive: false),
        toName,
      );
    }
    return s;
  }

  static String description(Map<String, dynamic> m) {
    final ref = (m['reference_type'] ?? '').toString();
    final qtyVal = qty(m);
    final from =
        (m['transfer_from_branch_name'] ?? '').toString().trim();
    final to = (m['transfer_to_branch_name'] ?? '').toString().trim();
    final orderNo = (m['order_number'] ?? '').toString().trim();
    final orderType =
        (m['order_type'] ?? '').toString().trim().toLowerCase();

    if (ref == 'transfer') {
      if (qtyVal >= 0) {
        if (from.isNotEmpty) return 'Diterima dari $from';
        return 'Barang diterima dari cabang lain';
      }
      if (to.isNotEmpty) return 'Dikirim ke $to';
      return 'Barang dikirim ke cabang lain';
    }
    if (ref == 'item_create') return 'Input stok baru di etalase';
    if (ref == 'restock') return 'Penambahan / restok manual';
    if (ref == 'opname') return 'Koreksi hasil stok opname';
    if (ref == 'order') {
      if (orderType == 'buyback') {
        if (orderNo.isNotEmpty) return 'Buyback lunas · $orderNo';
        return 'Buyback lunas';
      }
      if (orderNo.isNotEmpty) return 'Penjualan · $orderNo';
      return 'Pengurangan stok dari order';
    }

    final note = (m['notes'] ?? '').toString().trim();
    if (note.isNotEmpty) return humanizeBranchIdsInNotes(note, m);
    return '—';
  }

  static String filterLabel(String filterKey) {
    switch (filterKey) {
      case 'all':
        return 'Semua';
      case 'in':
        return 'Penambahan stok';
      case 'out':
        return 'Pengurangan stok';
      case 'transfer_in':
        return 'Transfer masuk';
      case 'transfer_out':
        return 'Transfer keluar';
      default:
        return 'Semua';
    }
  }

  static bool matchesFilter(Map<String, dynamic> m, String filterKey) {
    final type = (m['type'] ?? '').toString();
    final qtyVal = qty(m);
    switch (filterKey) {
      case 'all':
        return true;
      case 'in':
      case 'out':
        return type == filterKey;
      case 'transfer_in':
        return type == 'transfer' && qtyVal >= 0;
      case 'transfer_out':
        return type == 'transfer' && qtyVal < 0;
      default:
        return type == filterKey;
    }
  }

  static String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  static String dateRangeLabel(DateTime? start, DateTime? end) {
    if (start == null && end == null) return 'Semua tanggal';
    final df = DateFormat('dd/MM/yyyy');
    if (start != null &&
        end != null &&
        isoDate(start) == isoDate(end)) {
      return df.format(start);
    }
    final a = start != null ? df.format(start) : '-';
    final b = end != null ? df.format(end) : '-';
    return '$a - $b';
  }

  static String formatDateTime(dynamic raw) {
    if (raw == null) return '-';
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return raw.toString();
    final d = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }
}
