import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primaryYellow = Color(0xFFF4B400);
  static const Color accentAmber = Color(0xFF8B5CF6);
  static const Color accentOrange = Color(0xFFE67E22);
  static const Color backgroundLight = Color(0xFFFFFBF2);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceSoft = Color(0xFFFFF3D6);
  static const Color textPrimary = Color(0xFF2A1E0A);
  static const Color textSecondary = Color(0xFF6B5A36);
  static const Color border = Color(0xFFE8D9B0);

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    final colorScheme = ColorScheme.light(
      primary: primaryYellow,
      secondary: accentOrange,
      background: backgroundLight,
      surface: surfaceLight,
      onPrimary: surfaceLight,
      onSecondary: textPrimary,
      onBackground: textPrimary,
      onSurface: textPrimary,
      surfaceVariant: surfaceSoft,
    );

    return base.copyWith(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundLight,
      canvasColor: backgroundLight,
      cardColor: surfaceLight,
      dialogBackgroundColor: surfaceLight,
      dividerColor: border,
      textTheme: GoogleFonts.montserratTextTheme(base.textTheme).apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceLight,
        foregroundColor: textPrimary,
        elevation: 0,
        surfaceTintColor: surfaceLight,
        titleTextStyle: GoogleFonts.montserrat(fontSize: 20, fontWeight: FontWeight.w700, color: textPrimary),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryYellow,
          foregroundColor: textPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accentOrange),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceLight,
        selectedItemColor: primaryYellow,
        unselectedItemColor: textSecondary,
        showUnselectedLabels: true,
        elevation: 10,
      ),
      cardTheme: CardThemeData(
        color: surfaceLight,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
        tileColor: surfaceLight,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceSoft,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primaryYellow),
        ),
      ),
    );
  }

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final colorScheme = ColorScheme.dark(
      primary: primaryYellow,
      secondary: accentAmber,
      background: const Color(0xFF18140D),
      surface: const Color(0xFF221C12),
      onPrimary: surfaceLight,
      onSecondary: surfaceLight,
      onBackground: surfaceLight,
      onSurface: surfaceLight,
      surfaceVariant: const Color(0xFF372C1A),
    );

    return base.copyWith(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.background,
      canvasColor: colorScheme.background,
      cardColor: colorScheme.surface,
      dialogBackgroundColor: colorScheme.surface,
      dividerColor: const Color(0xFF4E4225),
      textTheme: GoogleFonts.montserratTextTheme(base.textTheme).apply(
        bodyColor: surfaceLight,
        displayColor: surfaceLight,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: surfaceLight,
        elevation: 0,
        surfaceTintColor: colorScheme.surface,
        titleTextStyle: GoogleFonts.montserrat(fontSize: 20, fontWeight: FontWeight.w700, color: surfaceLight),
        iconTheme: const IconThemeData(color: surfaceLight),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryYellow,
          foregroundColor: textPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accentAmber),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        selectedItemColor: primaryYellow,
        unselectedItemColor: const Color(0xFFD0C19B),
        showUnselectedLabels: true,
        elevation: 12,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
        tileColor: Color(0xFF221C12),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF372C1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: const Color(0xFF4E4225)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: const Color(0xFF4E4225)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primaryYellow),
        ),
      ),
    );
  }
}
