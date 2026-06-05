import 'dart:convert';

import 'package:vanessa3/core/state/user_state.dart';
import 'package:vanessa3/utils/network_config.dart';

abstract final class StoreOperationalUtils {
  StoreOperationalUtils._();

  static bool entryIsIncome(Map<String, dynamic> e) =>
      e['entry_kind']?.toString() == 'income';

  static String? normalizeProofUrl(dynamic raw) {
    final s = raw?.toString().trim();
    if (s == null || s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    if (s.startsWith('/')) return '${NetworkConfig.baseUrl}$s';
    return '${NetworkConfig.baseUrl}/uploads/$s';
  }

  static double parseAmount(String raw) {
    final s = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final v = double.tryParse(s);
    return (v == null || v.isNaN || v.isInfinite) ? 0 : v;
  }

  static String messageFromStoreOpsBody(
    String body,
    int statusCode,
    String fallback,
  ) {
    try {
      final d = jsonDecode(body);
      if (d is Map) {
        final err = d['error']?.toString().trim();
        final det = (d['details'] ?? d['detail'])?.toString().trim();
        if (det != null && det.isNotEmpty) return det;
        if (err != null && err.isNotEmpty) return err;
      }
    } catch (_) {}
    return '$fallback (HTTP $statusCode)';
  }

  static String? categoriesLoadHint(int statusCode) {
    if (statusCode == 404) {
      return 'Server belum punya API kategori (404). Deploy backend terbaru + jalankan patch_store_operational_categories.sql, lalu restart. Daftar bawaan dipakai sementara.';
    }
    if (statusCode == 503) {
      return 'Tabel kategori belum ada di database (503). Jalankan patch_store_operational_categories.sql lalu restart backend.';
    }
    return null;
  }

  static ({double income, double expense, double net}) sumEntries(
    List<Map<String, dynamic>> entries,
  ) {
    double income = 0;
    double expense = 0;
    for (final e in entries) {
      final amt = e['amount'];
      final n = amt is num ? amt.toDouble() : double.tryParse('$amt') ?? 0;
      if (entryIsIncome(e)) {
        income += n;
      } else {
        expense += n;
      }
    }
    return (income: income, expense: expense, net: income - expense);
  }

  static String branchLabel(UserState user, String branchId) {
    if (branchId.isEmpty) return 'Cabang';
    for (final b in user.branches) {
      final id = '${b['branch_id'] ?? b['id'] ?? ''}';
      if (id == branchId) {
        return (b['alias'] ?? b['branch_name'] ?? b['name'] ?? branchId)
            .toString();
      }
    }
    return 'Cabang $branchId';
  }

  static Map<String, String>? listScopeQuery({
    required bool isManajer,
    required UserState user,
  }) {
    final branchId = user.branch.trim();
    if (branchId.isEmpty) return null;
    if (isManajer) {
      return {'branch_id': branchId};
    }
    if (user.userId == null) return null;
    return {
      'branch_id': branchId,
      'user_id': user.userId.toString(),
    };
  }

  static String scopeSubtitle({
    required bool isManajer,
    required UserState user,
  }) {
    final branch = branchLabel(user, user.branch.trim());
    if (isManajer) {
      return '$branch · Semua entri cabang aktif';
    }
    final cashier = user.username.isEmpty ? 'Kasir' : user.username;
    return '$branch · $cashier${user.userId != null ? ' (ID ${user.userId})' : ''}';
  }
}
