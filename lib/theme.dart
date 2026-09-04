import 'package:flutter/material.dart';

// ブランドカラー(アイコン・ストア素材と共通)
const Color kBrandPurple = Color(0xFF7C4DFF);
const Color kBrandPurpleDark = Color(0xFF5B21B6);
const Color kBrandPink = Color(0xFFFF7BAC);
const Color kBrandPinkDark = Color(0xFFE8578D);
const Color kBrandCream = Color(0xFFFFF8FB);
const Color kBrandInk = Color(0xFF2E2540);

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kBrandPurple,
    primary: kBrandPurple,
    secondary: kBrandPinkDark,
    surface: kBrandCream,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBrandCream,
    appBarTheme: const AppBarTheme(
      backgroundColor: kBrandCream,
      foregroundColor: kBrandInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: kBrandInk,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kBrandPurple.withValues(alpha: 0.08)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: kBrandPurple,
      side: BorderSide(color: kBrandPurple.withValues(alpha: 0.2)),
      labelStyle: const TextStyle(fontSize: 13, color: kBrandInk),
      secondaryLabelStyle: const TextStyle(fontSize: 13, color: Colors.white),
      shape: const StadiumBorder(),
      showCheckmark: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: kBrandPurple.withValues(alpha: 0.12),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: kBrandPurple.withValues(alpha: 0.15)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: kBrandPurple.withValues(alpha: 0.15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kBrandPurple, width: 1.5),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
