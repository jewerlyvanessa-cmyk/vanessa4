import 'package:flutter/material.dart';

import 'app_typography.dart';

class AppTheme {
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFFFDE21), // warna utama logo
      brightness: Brightness.light,
    );

    final onSurface = colorScheme.onSurface;
    final onSurfaceVariant = colorScheme.onSurfaceVariant;

    final textTheme = TextTheme(
      displayLarge: TextStyle(fontSize: 57, color: onSurface),
      displayMedium: TextStyle(fontSize: 45, color: onSurface),
      displaySmall: TextStyle(fontSize: 36, color: onSurface),
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: AppTypography.section,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: onSurface,
      ),
      titleSmall: TextStyle(
        fontSize: AppTypography.body,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: onSurface,
      ),
      bodyLarge: TextStyle(
        fontSize: AppTypography.body,
        height: 1.35,
        color: onSurface,
      ),
      bodyMedium: TextStyle(
        fontSize: AppTypography.body,
        height: 1.35,
        color: onSurface,
      ),
      bodySmall: TextStyle(
        fontSize: AppTypography.bodySmall,
        height: 1.35,
        color: onSurfaceVariant,
      ),
      labelLarge: TextStyle(
        fontSize: AppTypography.body,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      labelMedium: TextStyle(
        fontSize: AppTypography.bodySmall,
        fontWeight: FontWeight.w500,
        color: onSurface,
      ),
      labelSmall: TextStyle(
        fontSize: AppTypography.bodySmall,
        fontWeight: FontWeight.w500,
        color: onSurfaceVariant,
      ),
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ),
      ),
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      dataTableTheme: DataTableThemeData(
dataTextStyle: TextStyle(
          fontSize: AppTypography.tableCell,
          height: 1.25,
          color: onSurface,
        ),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: TextStyle(
          fontSize: AppTypography.body,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: AppTypography.bodySmall,
          color: onSurfaceVariant,
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: TextStyle(
          fontSize: AppTypography.bodySmall,
          color: onSurface,
        ),
        secondaryLabelStyle: TextStyle(
          fontSize: AppTypography.bodySmall,
          color: onSurfaceVariant,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      ),
      dialogTheme: DialogThemeData(
        titleTextStyle: TextStyle(
          fontSize: AppTypography.section,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
        contentTextStyle: TextStyle(
          fontSize: AppTypography.body,
          color: onSurface,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        dragHandleColor: onSurfaceVariant,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: AppTypography.body,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: AppTypography.body,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: AppTypography.body,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: AppTypography.body,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        labelStyle: TextStyle(
          color: colorScheme.primary,
          fontSize: AppTypography.bodySmall,
        ),
        helperStyle: TextStyle(fontSize: AppTypography.bodySmall),
        hintStyle: TextStyle(
          fontSize: AppTypography.body,
          color: onSurfaceVariant,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      scaffoldBackgroundColor: colorScheme.surface,
    );
  }
}
