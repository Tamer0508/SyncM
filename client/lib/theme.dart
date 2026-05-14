import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // User-specified palette
  // Light theme: background #E8EDF2, accent/red #E43636
  static const Color lightBackground = Color(0xFFE8EDF2);
  static const Color lightPrimary = Color(0xFFE43636);
  // Dark theme: primary purple #9D3ED5, background #282828
  static const Color darkBackground = Color(0xFF282828);
  static const Color darkPrimary = Color(0xFF9D3ED5);

  // Complementary tones
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceSoftLight = Color(0xFFF6F8FA);
  static const Color surfaceDark = Color(0xFF333333);
  static const Color textOnLight = Color(0xFF0F1722);
  static const Color textOnDark = Color(0xFFF2F5F7);

  // Optional brand color (Spotify) kept for specific UI parts
  static const Color spotifyGreen = Color(0xFF1DB954);

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    final colorScheme = ColorScheme.light(
      primary: lightPrimary,
      secondary: darkPrimary, // use purple as secondary accent
      background: lightBackground,
      surface: surfaceLight,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onBackground: textOnLight,
      onSurface: textOnLight,
      error: const Color(0xFFB00020),
    );

    return base.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.background,
      canvasColor: colorScheme.background,
      cardColor: colorScheme.surface,
      dialogBackgroundColor: colorScheme.surface,
      dividerColor: surfaceSoftLight,
      textTheme: GoogleFonts.montserratTextTheme(base.textTheme).apply(
        bodyColor: textOnLight,
        displayColor: textOnLight,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textOnLight,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.montserrat(fontSize: 20, fontWeight: FontWeight.w700, color: textOnLight),
        iconTheme: IconThemeData(color: textOnLight),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurface.withOpacity(0.6),
        showUnselectedLabels: true,
        elevation: 8,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceSoftLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary.withOpacity(0.16)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary),
        ),
      ),
      // small visual tweaks
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final colorScheme = ColorScheme.dark(
      primary: darkPrimary,
      secondary: lightPrimary, // use red as secondary accent for contrast
      background: darkBackground,
      surface: surfaceDark,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onBackground: textOnDark,
      onSurface: textOnDark,
      error: const Color(0xFFEF5350),
    );

    return base.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.background,
      canvasColor: colorScheme.background,
      cardColor: colorScheme.surface,
      dialogBackgroundColor: colorScheme.surface,
      dividerColor: colorScheme.onSurface.withOpacity(0.12),
      textTheme: GoogleFonts.montserratTextTheme(base.textTheme).apply(
        bodyColor: textOnDark,
        displayColor: textOnDark,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textOnDark,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.montserrat(fontSize: 20, fontWeight: FontWeight.w700, color: textOnDark),
        iconTheme: IconThemeData(color: textOnDark),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurface.withOpacity(0.6),
        showUnselectedLabels: true,
        elevation: 12,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface.withOpacity(0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.onSurface.withOpacity(0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.onSurface.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary),
        ),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}
