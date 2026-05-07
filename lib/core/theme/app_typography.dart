import 'package:flutter/material.dart';

/// Skala teks isi halaman. AppBar memakai [AppBarTheme.titleTextStyle] tersendiri.
abstract final class AppTypography {
  static const double body = 14;
  static const double bodySmall = 13;
  static const double section = 16;
  static const double tableHeader = 13;
  static const double tableCell = 14;
}

/// Judul kolom [DataTable]: gunakan [ThemeData.dataTableTheme.headingTextStyle] global.
/// Jangan set [TextStyle.fontSize] di sini.
Text dataTableColumnLabel(
  String label, {
  bool numeric = false,
}) {
  return Text(
    label,
    textAlign: numeric ? TextAlign.end : TextAlign.start,
  );
}
