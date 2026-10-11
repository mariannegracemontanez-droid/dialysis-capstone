import 'package:flutter/material.dart';

/// CureNurture colour tokens — the values already used across the app,
/// named so new and updated screens share one palette.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF2C5F7D);
  static const Color primaryDark = Color(0xFF225E72);
  static const Color ink = Color(0xFF173B4F);
  static const Color textSecondary = Color(0xFF5B6D7D);
  static const Color textMuted = Color(0xFF6B7C86);
  static const Color background = Color(0xFFF3F7FA);
  static const Color surface = Colors.white;
  static const Color fieldFill = Color(0xFFF4F8FA);
  static const Color border = Color(0xFFE1EAF0);
  static const Color fieldBorder = Color(0xFFE3EDF2);
  static const Color tint = Color(0xFFEAF4F7);
  static const Color success = Color(0xFF2A9D65);
  static const Color error = Color(0xFFB3261E);
}

/// App-wide Material 3 theme.
///
/// Before this, `ThemeData(primarySwatch: Colors.blue, useMaterial3: true)`
/// left Material 3 on its default purple seed (`primarySwatch` does not feed
/// the M3 colour scheme), so every widget without an explicit colour —
/// app bar text, dialogs, bottom sheets, date pickers, switches, plain
/// buttons, progress indicators — came out purple or purple-tinted. Screens
/// that set colours explicitly are unaffected; those values still win.
class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(seedColor: AppColors.primary)
        .copyWith(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          secondary: AppColors.primaryDark,
          onSecondary: Colors.white,
          surface: AppColors.surface,
          onSurface: AppColors.ink,
          onSurfaceVariant: AppColors.textSecondary,
          error: AppColors.error,
          // Keeps dialogs, sheets and cards white instead of tinted.
          surfaceTint: Colors.transparent,
        );

    final roundedButton = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    OutlineInputBorder fieldBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
          disabledForegroundColor: Colors.white70,
          minimumSize: const Size(64, 48),
          shape: roundedButton,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          minimumSize: const Size(64, 48),
          shape: roundedButton,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.fieldFill,
        labelStyle: const TextStyle(
          color: Color(0xFF6F7F89),
          fontWeight: FontWeight.w500,
        ),
        hintStyle: const TextStyle(color: Color(0xFF8B9AA6)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: fieldBorder(AppColors.fieldBorder),
        enabledBorder: fieldBorder(AppColors.fieldBorder),
        focusedBorder: fieldBorder(AppColors.primary, 1.4),
        errorBorder: fieldBorder(AppColors.error),
        focusedErrorBorder: fieldBorder(AppColors.error, 1.4),
        errorMaxLines: 3,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: const TextStyle(
          color: AppColors.ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          height: 1.45,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
        actionTextColor: const Color(0xFF9FD3E6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Color(0xFF8B9AA6),
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700),
      ),
      listTileTheme: const ListTileThemeData(iconColor: AppColors.primary),
    );
  }
}
