import 'package:flutter/material.dart';

class AppColors {
  static const sidebarBg      = Color(0xFF141F1D);
  static const sidebarActive  = Color(0xFF1E6B60);
  static const sidebarHover   = Color(0xFF1A2E2B);
  static const sidebarBorder  = Color(0xFF1E2E2C);
  static const primary        = Color(0xFF2E8B80);
  static const primaryLight   = Color(0xFF3AADA0);
  static const primaryDark    = Color(0xFF1E6B60);
  static const contentBg      = Color(0xFFF4F7F6);
  static const cardBg         = Colors.white;
  static const topBarBg       = Colors.white;
  static const textDark       = Color(0xFF1C2B2A);
  static const textMid        = Color(0xFF6B7B7A);
  static const textLight      = Color(0xFF9EAEAC);
  static const textWhite      = Colors.white;
  static const textSidebar    = Color(0xFFB8D0CC);
  static const statusAvailable  = Color(0xFF2E7D32);
  static const statusAvailBg    = Color(0xFFE8F5E9);
  static const statusOccupied   = Color(0xFFBF5500);
  static const statusOccupBg    = Color(0xFFFFF3E0);
  static const statusReserved   = Color(0xFF4A148C);
  static const statusResBg      = Color(0xFFF3E5F5);
  static const statusPreparing  = Color(0xFFF57C00);
  static const statusPrepBg     = Color(0xFFFFF8E1);
  static const green   = Color(0xFF2E7D32);
  static const greenBg = Color(0xFFE8F5E9);
  static const red     = Color(0xFFE53935);
  static const redBg   = Color(0xFFFFEBEE);
  static const orange  = Color(0xFFF57C00);
  static const orangeBg= Color(0xFFFFF3E0);
  static const purple  = Color(0xFF6A1B9A);
  static const purpleBg= Color(0xFFF3E5F5);
  static const divider = Color(0xFFE8EEEC);
  static const border  = Color(0xFFD4E0DE);
  static const shadow  = Color(0x0A00897B);
}

class AppText {
  static const h1 = TextStyle(
    fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textDark, letterSpacing: -0.5);

  static const h2 = TextStyle(
    fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark, letterSpacing: -0.3);

  static const h3 = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark);

  static const h4 = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark);

  static const body = TextStyle(
    fontSize: 13.5, fontWeight: FontWeight.w400, color: AppColors.textMid);

  static const bodySmall = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textLight);

  static const label = TextStyle(
    fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textLight, letterSpacing: 0.5);

  static const sidebarItem = TextStyle(
    fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textSidebar);

  static const sidebarItemActive = TextStyle(
    fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.white);

  static const statValue = TextStyle(
    fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textDark, letterSpacing: -0.5);

  static const badge = TextStyle(
    fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.4);
}

class AppTheme {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.contentBg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
    ),
    fontFamily: 'Inter',
    cardTheme: CardThemeData(
      color: AppColors.cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF7FBFA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      labelStyle: const TextStyle(fontSize: 13, color: AppColors.textMid),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    ),
  );
} 