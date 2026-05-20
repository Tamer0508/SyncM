import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color lightPrimary    = Color(0xFFE43636);  // красный акцент
  static const Color lightBackground = Color(0xFFF5F6FA);  // мягкий светло-серый фон
  static const Color lightSurface    = Color(0xFFFFFFFF);  // белые карточки/поверхности
  static const Color lightNavBar     = Color(0xFFFFFFFF);  // белая нижняя панель
  static const Color textOnLight     = Color(0xFF1A1C1E);  // почти чёрный текст
  static const Color lightDivider    = Color(0xFFE0E0E0);

  static const Color darkDeepest      = Color(0xFF121212);  // самый глубокий фон (scaffold)
  static const Color darkSurface      = Color(0xFF1F1F1F);  // карточки, диалоги
  static const Color darkNavBar       = Color(0xFF282828);  // нижняя панель, AppBar (если непрозрачный)
  static const Color darkPrimaryColor = Color(0xFF9D3ED5);  // фиолетовый акцент
  static const Color textOnDark       = Color(0xFFE1E3E6);  // светлый текст

  // Brand colors
  static const Color spotifyGreen = Color(0xFF1DB954);

  // ==================== Light Theme ====================
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    final colorScheme = ColorScheme.light(
      primary: lightPrimary,
      secondary: const Color(0xFF9D3ED5),
      background: lightBackground,
      surface: lightSurface,
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
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textOnLight,
        ),
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
        backgroundColor: lightNavBar,
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
        fillColor: lightSurface,
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
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  // ==================== Dark Theme ====================
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final colorScheme = ColorScheme.dark(
      primary: darkPrimaryColor,
      secondary: lightPrimary,               // контрастный акцент
      background: darkDeepest,
      surface: darkSurface,
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
      scaffoldBackgroundColor: darkDeepest,          // #121212
      canvasColor: darkDeepest,
      cardColor: darkSurface,                        // #1F1F1F
      dialogBackgroundColor: darkSurface,
      dividerColor: darkNavBar.withOpacity(0.5),     // мягкий разделитель
      textTheme: GoogleFonts.montserratTextTheme(base.textTheme).apply(
        bodyColor: textOnDark,
        displayColor: textOnDark,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,         // наследует фон scaffold
        foregroundColor: textOnDark,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.montserrat(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textOnDark,
        ),
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
        backgroundColor: darkNavBar,                  // #282828
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurface.withOpacity(0.6),
        showUnselectedLabels: true,
        elevation: 12,
      ),
      cardTheme: CardThemeData(
        color: darkSurface,                           // #1F1F1F
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: darkSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface.withOpacity(0.8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: darkNavBar.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: darkNavBar.withOpacity(0.3)),
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