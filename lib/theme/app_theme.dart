import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color backgroundColor = Color(0xFF0A0A0A);
  static const Color cardColor = backgroundColor;
  static const Color accentColor = Color(0xFFFF8A65);
  static const Color titleColor = Color(0xFFF5F5F5);
  static const Color bodyColor = Color(0xFFB8B8B8);
  static const Color mutedColor = Color(0xFF8C8C8C);
  static const Color onAccentColor = Color(0xFF1F130E);

  static ThemeData dark() {
    final colorScheme =
        ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: accentColor,
        ).copyWith(
          primary: accentColor,
          onPrimary: onAccentColor,
          secondary: accentColor,
          onSecondary: onAccentColor,
          surface: cardColor,
          onSurface: titleColor,
          error: const Color(0xFFCF6679),
          onError: Colors.white,
        );

    final baseTextTheme = ThemeData.dark(useMaterial3: true).textTheme;
    final textTheme = _buildTextTheme(baseTextTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'HarmonyOS Sans',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundColor,
      canvasColor: backgroundColor,
      cardColor: cardColor,
      dividerColor: mutedColor.withValues(alpha: 0.18),
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundColor,
        foregroundColor: titleColor,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'HarmonyOS Sans',
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: titleColor,
          letterSpacing: 0.2,
        ),
      ),
      iconTheme: const IconThemeData(color: titleColor),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accentColor,
        foregroundColor: onAccentColor,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: onAccentColor,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: cardColor,
        selectedItemColor: accentColor,
        unselectedItemColor: mutedColor,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  static TextTheme _buildTextTheme(TextTheme base) {
    return base.copyWith(
      displayLarge: const TextStyle(
        fontFamily: 'HarmonyOS Sans',
        fontSize: 36,
        fontWeight: FontWeight.w800,
        height: 1.12,
        letterSpacing: -0.5,
        color: titleColor,
      ),
      headlineLarge: const TextStyle(
        fontFamily: 'HarmonyOS Sans',
        fontSize: 30,
        fontWeight: FontWeight.w700,
        height: 1.16,
        letterSpacing: -0.3,
        color: titleColor,
      ),
      headlineMedium: const TextStyle(
        fontFamily: 'HarmonyOS Sans',
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: titleColor,
      ),
      titleLarge: const TextStyle(
        fontFamily: 'HarmonyOS Sans',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.25,
        color: titleColor,
      ),
      titleMedium: const TextStyle(
        fontFamily: 'HarmonyOS Sans',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: titleColor,
      ),
      bodyLarge: const TextStyle(
        fontFamily: 'HarmonyOS Sans',
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.55,
        color: bodyColor,
      ),
      bodyMedium: const TextStyle(
        fontFamily: 'HarmonyOS Sans',
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: bodyColor,
      ),
      bodySmall: const TextStyle(
        fontFamily: 'HarmonyOS Sans',
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: mutedColor,
      ),
      labelLarge: const TextStyle(
        fontFamily: 'HarmonyOS Sans',
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: titleColor,
      ),
    );
  }
}
