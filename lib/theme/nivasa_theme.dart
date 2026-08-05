import 'package:flutter/material.dart';
import 'nivasa_colors.dart';
import 'nivasa_spacing.dart';
import 'nivasa_text_styles.dart';

/// Global ThemeData assembled from the token files in this directory. Widgets should
/// reach for NivasaColors/NivasaText/NivasaSpacing directly for anything the default
/// Material theming below doesn't cover (status badges, chat bubbles, etc.) rather than
/// hunting for a Theme.of(context) equivalent that doesn't exist.
class NivasaTheme {
  NivasaTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: NivasaColors.primary700,
      brightness: Brightness.light,
      primary: NivasaColors.primary700,
      onPrimary: NivasaColors.white,
      secondary: NivasaColors.gold500,
      onSecondary: NivasaColors.goldTextOn,
      error: NivasaColors.negativeFg,
      surface: NivasaColors.white,
      onSurface: NivasaColors.ink900,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: NivasaColors.canvas,
      fontFamily: 'Noto Sans',
      textTheme: const TextTheme(
        displayLarge: NivasaText.display,
        headlineLarge: NivasaText.h1,
        headlineMedium: NivasaText.h2,
        headlineSmall: NivasaText.h3,
        bodyMedium: NivasaText.body,
        labelLarge: NivasaText.label,
        bodySmall: NivasaText.caption,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: NivasaColors.white,
        foregroundColor: NivasaColors.ink900,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: NivasaText.h3,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NivasaColors.primary700,
          foregroundColor: NivasaColors.white,
          disabledBackgroundColor: NivasaColors.ink300,
          disabledForegroundColor: NivasaColors.surface,
          minimumSize: const Size.fromHeight(NivasaSpacing.buttonHeightMobile),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NivasaRadius.button)),
          textStyle: const TextStyle(fontFamily: 'Noto Sans', fontSize: 15, fontWeight: FontWeight.w600),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NivasaColors.primary700,
          side: const BorderSide(color: NivasaColors.primary700, width: 1.5),
          minimumSize: const Size.fromHeight(NivasaSpacing.buttonHeightMobile),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NivasaRadius.button)),
          textStyle: const TextStyle(fontFamily: 'Noto Sans', fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: NivasaColors.primary700,
          textStyle: const TextStyle(fontFamily: 'Noto Sans', fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NivasaColors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: NivasaSpacing.s16),
        labelStyle: NivasaText.label,
        hintStyle: const TextStyle(fontFamily: 'Noto Sans', fontSize: 16, color: NivasaColors.ink400),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NivasaRadius.input),
          borderSide: const BorderSide(color: NivasaColors.line, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NivasaRadius.input),
          borderSide: const BorderSide(color: NivasaColors.line, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NivasaRadius.input),
          borderSide: const BorderSide(color: NivasaColors.primary700, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NivasaRadius.input),
          borderSide: const BorderSide(color: NivasaColors.negativeFg, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NivasaRadius.input),
          borderSide: const BorderSide(color: NivasaColors.surface, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: NivasaColors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NivasaRadius.card),
          side: const BorderSide(color: NivasaColors.line, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(color: NivasaColors.line, thickness: 1, space: 1),
    );
  }
}
