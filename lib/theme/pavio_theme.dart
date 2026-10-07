import 'package:flutter/material.dart';
import 'pavio_colors.dart';
import 'pavio_spacing.dart';
import 'pavio_text_styles.dart';

/// Global ThemeData assembled from the token files in this directory. Widgets should
/// reach for PavioColors/PavioText/PavioSpacing directly for anything the default
/// Material theming below doesn't cover (status badges, chat bubbles, etc.) rather than
/// hunting for a Theme.of(context) equivalent that doesn't exist.
class PavioTheme {
  PavioTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: PavioColors.primary700,
      brightness: Brightness.light,
      primary: PavioColors.primary700,
      onPrimary: PavioColors.white,
      secondary: PavioColors.gold500,
      onSecondary: PavioColors.goldTextOn,
      error: PavioColors.negativeFg,
      surface: PavioColors.white,
      onSurface: PavioColors.ink900,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: PavioColors.canvas,
      fontFamily: 'Noto Sans',
      textTheme: const TextTheme(
        displayLarge: PavioText.display,
        headlineLarge: PavioText.h1,
        headlineMedium: PavioText.h2,
        headlineSmall: PavioText.h3,
        bodyMedium: PavioText.body,
        labelLarge: PavioText.label,
        bodySmall: PavioText.caption,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: PavioColors.white,
        foregroundColor: PavioColors.ink900,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: PavioText.h3,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: PavioColors.primary700,
          foregroundColor: PavioColors.white,
          disabledBackgroundColor: PavioColors.ink300,
          disabledForegroundColor: PavioColors.surface,
          minimumSize: const Size.fromHeight(PavioSpacing.buttonHeightMobile),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PavioRadius.button)),
          textStyle: const TextStyle(fontFamily: 'Noto Sans', fontSize: 15, fontWeight: FontWeight.w600),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: PavioColors.primary700,
          side: const BorderSide(color: PavioColors.primary700, width: 1.5),
          minimumSize: const Size.fromHeight(PavioSpacing.buttonHeightMobile),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PavioRadius.button)),
          textStyle: const TextStyle(fontFamily: 'Noto Sans', fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: PavioColors.primary700,
          // Bounded width, unlike Size.fromHeight — TextButton (unlike Elevated/Outlined)
          // is often used inline in a Row rather than stretched full-width, and
          // Size.fromHeight's implicit width: double.infinity breaks layout there.
          minimumSize: const Size(64, PavioSpacing.buttonHeightMobile),
          textStyle: const TextStyle(fontFamily: 'Noto Sans', fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PavioColors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: PavioSpacing.s16),
        labelStyle: PavioText.label,
        hintStyle: const TextStyle(fontFamily: 'Noto Sans', fontSize: 16, color: PavioColors.ink400),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PavioRadius.input),
          borderSide: const BorderSide(color: PavioColors.line, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PavioRadius.input),
          borderSide: const BorderSide(color: PavioColors.line, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PavioRadius.input),
          borderSide: const BorderSide(color: PavioColors.primary700, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PavioRadius.input),
          borderSide: const BorderSide(color: PavioColors.negativeFg, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PavioRadius.input),
          borderSide: const BorderSide(color: PavioColors.surface, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: PavioColors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PavioRadius.card),
          side: const BorderSide(color: PavioColors.line, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(color: PavioColors.line, thickness: 1, space: 1),
    );
  }
}
