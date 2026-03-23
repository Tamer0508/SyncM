import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Spotify-like palette
  static const Color spotifyGreen = Color(0xFF1DB954);
  static const Color bgDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF181818);
  static const Color accentLight = Color(0xFF1ED760);

  static ThemeData get light {
    final base = ThemeData.light();
    return base.copyWith(
      primaryColor: spotifyGreen,
      scaffoldBackgroundColor: Colors.white,
      textTheme: GoogleFonts.montserratTextTheme(base.textTheme).apply(
        bodyColor: Colors.black87,
        displayColor: Colors.black87,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        titleTextStyle: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
      ),
      colorScheme: base.colorScheme.copyWith(primary: spotifyGreen, secondary: spotifyGreen),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: spotifyGreen,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      // using default CardTheme; cardColor configured separately when needed
    );
  }

  static ThemeData get dark {
    final base = ThemeData.dark();
    return base.copyWith(
      primaryColor: spotifyGreen,
      scaffoldBackgroundColor: bgDark,
      canvasColor: bgDark,
      cardColor: surfaceDark,
      textTheme: GoogleFonts.montserratTextTheme(base.textTheme).apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bgDark,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      colorScheme: base.colorScheme.copyWith(primary: spotifyGreen, secondary: spotifyGreen),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceDark,
        selectedItemColor: spotifyGreen,
        unselectedItemColor: Colors.white70,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: spotifyGreen,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      // using default CardTheme; cardColor configured separately when needed
    );
  }
}
