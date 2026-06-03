import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color lightPrimary    = Color(0xFF6A7A4E);
  static const Color lightBackground = Color(0xFFFBF9F2);
  static const Color lightSurface    = Color(0xFFFFFFFF);
  static const Color lightNavBar     = Color(0xFFF5F3ED);
  static const Color textOnLight     = Color(0xFF2C2F24);
  static const Color lightDivider    = Color(0xFFECEAE4);

  static const Color darkDeepest = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF181818);
  static const Color darkNavBar  = Color(0xFF282828);
  static const Color darkPrimaryColor = Color(0xFFC5E384);
  static const Color darkSecondary = Color(0xFF1DB954);
  static const Color textOnDark = Color(0xFFFFFFFF);

  static const Color spotifyGreen = Color(0xFF1DB954);

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3:  true);
    final colorScheme = ColorScheme.light(
      primary: lightPrimary,
      secondary: const Color(0xFFD68C6E),
      background: lightBackground,
      surface: lightSurface,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onBackground: textOnLight,
      onSurface: textOnLight,
      error: const Color(0xFFB84A4A),
    );

    return base.copyWith(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: lightBackground,
      canvasColor: lightBackground,
      cardColor: lightSurface,
      dialogBackgroundColor: lightSurface,
      dividerColor: lightDivider,

      textTheme: GoogleFonts.montserratTextTheme(base.textTheme).apply(
        bodyColor: textOnLight,
        displayColor: textOnLight,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textOnLight,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.montserrat(
          fontSize: 20, fontWeight: FontWeight.w700, color: textOnLight,
        ),
        iconTheme: IconThemeData(color: textOnLight),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 0,
          splashFactory: InkRipple.splashFactory,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          splashFactory: InkRipple.splashFactory,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          splashFactory: InkRipple.splashFactory,
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: lightNavBar,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurface.withOpacity(0.6),
        showUnselectedLabels: true,
        elevation: 2,
      ),

      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: lightDivider, width: 0.5),
        ),
      ),

      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tileColor: colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: colorScheme.primary.withOpacity(0.16)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: colorScheme.primary.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: colorScheme.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),

      // Иконки: только overlayColor (splashRadius недоступен в ButtonStyle)
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (Set<MaterialState> states) {
              if (states.contains(MaterialState.hovered)) {
                return colorScheme.primary.withOpacity(0.1);
              }
              return null;
            },
          ),
        ),
      ),

      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final colorScheme = ColorScheme.dark(
      primary: darkPrimaryColor,
      secondary: darkSecondary,
      background: darkDeepest,
      surface: darkSurface,
      onPrimary: const Color(0xFF1A1C12),
      onSecondary: const Color(0xFF0A1E1A),
      onBackground: textOnDark,
      onSurface: textOnDark,
      error: const Color(0xFFEF5350),
    );

    return base.copyWith(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: darkDeepest,
      canvasColor: darkDeepest,
      cardColor: darkSurface,
      dialogBackgroundColor: darkSurface,
      dividerColor: darkNavBar.withOpacity(0.5),

      textTheme: GoogleFonts.montserratTextTheme(base.textTheme).apply(
        bodyColor: textOnDark,
        displayColor: textOnDark,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textOnDark,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.montserrat(
          fontSize: 20, fontWeight: FontWeight.w700, color: textOnDark,
        ),
        iconTheme: IconThemeData(color: textOnDark),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 0,
          splashFactory: InkRipple.splashFactory,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          splashFactory: InkRipple.splashFactory,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          splashFactory: InkRipple.splashFactory,
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: darkNavBar,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurface.withOpacity(0.6),
        showUnselectedLabels: true,
        elevation: 2,
      ),

      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: darkNavBar.withOpacity(0.5), width: 0.5),
        ),
      ),

      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tileColor: darkSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface.withOpacity(0.8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: darkNavBar.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: darkNavBar.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: colorScheme.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (Set<MaterialState> states) {
              if (states.contains(MaterialState.hovered)) {
                return Colors.white.withOpacity(0.1);
              }
              return null;
            },
          ),
        ),
      ),

      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}