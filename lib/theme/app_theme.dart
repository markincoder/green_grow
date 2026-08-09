import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const forest = Color(0xFF1B4332);
  static const leaf = Color(0xFF2D6A4F);
  static const meadow = Color(0xFF40916C);
  static const sprout = Color(0xFF52B788);
  static const mist = Color(0xFFD8F3DC);
  static const canvas = Color(0xFFF3FAF5);
  static const water = Color(0xFF3D7EA6);
  static const sun = Color(0xFFE9B44C);
  static const soil = Color(0xFF6B4F3A);
  static const ink = Color(0xFF1A2E24);
  static const muted = Color(0xFF5C7268);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.meadow,
      brightness: Brightness.light,
      primary: AppColors.leaf,
      secondary: AppColors.water,
      tertiary: AppColors.sun,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: AppColors.canvas,
  );

  final display = GoogleFonts.frauncesTextTheme(base.textTheme);
  final body = GoogleFonts.manropeTextTheme(base.textTheme);

  return base.copyWith(
    textTheme: body.copyWith(
      displayLarge: display.displayLarge?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w600,
        letterSpacing: -1,
      ),
      displayMedium: display.displayMedium?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
      headlineLarge: display.headlineLarge?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w600,
      ),
      headlineMedium: display.headlineMedium?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: display.headlineSmall?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: body.titleLarge?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: body.titleMedium?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: body.bodyLarge?.copyWith(color: AppColors.ink, height: 1.45),
      bodyMedium: body.bodyMedium?.copyWith(color: AppColors.muted, height: 1.45),
      labelLarge: body.labelLarge?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.fraunces(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.mist,
      selectedColor: AppColors.sprout,
      labelStyle: GoogleFonts.manrope(
        fontWeight: FontWeight.w600,
        color: AppColors.forest,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.leaf,
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: AppColors.leaf,
      unselectedItemColor: AppColors.muted,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.leaf,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.leaf,
        side: const BorderSide(color: AppColors.meadow),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
