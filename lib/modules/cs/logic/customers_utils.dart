import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:vanessa3/core/network/api_client.dart';

/// Helper izin, format, validasi, dan fetch untuk modul pelanggan CS.
abstract final class CustomersUtils {
  CustomersUtils._();

  static bool canSeeGlobalTransactions(String roleRaw) {
    final role = roleRaw.trim().toLowerCase();
    return role == 'manajer' ||
        role == 'admin_toko' ||
        role == 'superadmin';
  }

  static bool canEditCustomer(String roleRaw) {
    final r = roleRaw.trim().toLowerCase();
    return r == 'cs' ||
        r == 'kasir' ||
        r == 'admin_toko' ||
        r == 'manajer' ||
        r == 'superadmin';
  }

  static bool canDeleteCustomer(String roleRaw) {
    final r = roleRaw.trim().toLowerCase();
    return r == 'admin_toko' || r == 'manajer' || r == 'superadmin';
  }

  static String cellStr(dynamic v) {
    final s = v?.toString().trim();
    if (s == null || s.isEmpty) return '—';
    return s;
  }

  static List<PopupMenuEntry<String>> customerMenuEntries(
    BuildContext context,
    String role,
  ) {
    final items = <PopupMenuEntry<String>>[];
    if (canSeeGlobalTransactions(role)) {
      items.add(
        const PopupMenuItem(
          value: 'transactions',
          child: Text('Riwayat transaksi'),
        ),
      );
    }
    if (canEditCustomer(role)) {
      items.add(const PopupMenuItem(value: 'edit', child: Text('Edit')));
    }
    if (canDeleteCustomer(role)) {
      if (items.isNotEmpty) {
        items.add(const PopupMenuDivider());
      }
      items.add(
        PopupMenuItem(
          value: 'delete',
          child: Text(
            'Hapus',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    return items;
  }

  static Future<List<Map<String, dynamic>>> fetchCustomerTransactions({
    required String customerId,
    String? branchId,
  }) async {
    final query = (branchId == null || branchId.toString().trim().isEmpty)
        ? null
        : {'branch_id': branchId.toString()};

    final response = await ApiClient.get(
      '/api/customers/$customerId/transactions',
      query: query,
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Gagal memuat riwayat transaksi (${response.statusCode})',
      );
    }
    final data = json.decode(response.body);
    if (data is! List) return <Map<String, dynamic>>[];
    return List<Map<String, dynamic>>.from(
      data.map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  static String fmtRp(dynamic v) {
    final n = double.tryParse(v?.toString() ?? '');
    if (n == null) return '0';
    final s = n.toStringAsFixed(0);
    return s.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

  static num sumTransactionAmounts(List<Map<String, dynamic>> rows) {
    return rows.fold<num>(0, (sum, r) {
      final v = r['jumlah'] ?? r['total'];
      if (v == null) return sum;
      if (v is num) return sum + v;
      return sum + (num.tryParse(v.toString()) ?? 0);
    });
  }

  static String fmtDateTime(dynamic v) {
    try {
      final dt = DateTime.tryParse(v?.toString() ?? '');
      if (dt == null) return '-';
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$y-$m-$d $hh:$mm';
    } catch (_) {
      return '-';
    }
  }

  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Nama tidak boleh kosong';
    }
    if (value.trim().length < 2) {
      return 'Nama minimal 2 karakter';
    }
    return null;
  }

  static String? validateEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final emailRegex = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,}$');
    if (!emailRegex.hasMatch(trimmed)) {
      return 'Format email tidak valid';
    }
    return null;
  }

  static String? validatePhone(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final phoneRegex = RegExp(r'^[\+]?[0-9]{10,15}$');
    if (!phoneRegex.hasMatch(trimmed)) {
      return 'Nomor telepon tidak valid (10-15 digit)';
    }
    return null;
  }

  static String? validateAddress(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length < 5) {
      return 'Alamat minimal 5 karakter jika diisi';
    }
    return null;
  }
}
