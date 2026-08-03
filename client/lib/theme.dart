import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppMotion {
  const AppMotion._();

  static const Duration short = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 350);
  static const Duration long = Duration(milliseconds: 500);
  static const Duration extraLong = Duration(milliseconds: 700);

  /// Основная кривая: быстрый разгон, мягкое торможение. Подходит почти всему.
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Для появления элементов на экране.
  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);

  /// Для исчезновения — уходит быстро, не задерживая внимание.
  static const Curve emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);

  static const Curve spring = Cubic(0.34, 1.4, 0.64, 1.0);
}

class AppRadius {
  const AppRadius._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double full = 999;

  static BorderRadius get small => BorderRadius.circular(sm);
  static BorderRadius get medium => BorderRadius.circular(md);
  static BorderRadius get large => BorderRadius.circular(lg);
  static BorderRadius get extraLarge => BorderRadius.circular(xl);
}

class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

class AppTheme {
  static const Color _seedLight = Color(0xFF6A7A4E);
  static const Color _seedDark = Color(0xFFC5E384);
  static const Color spotifyGreen = Color(0xFF1DB954);

  static TextTheme _textTheme(TextTheme base, Color onSurface) {
    final t = GoogleFonts.montserratTextTheme(base);
    return t
        .copyWith(
          displayLarge: t.displayLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.5),
          displayMedium: t.displayMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
          displaySmall: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
          headlineLarge: t.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
          headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
          headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
          titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          bodyLarge: t.bodyLarge?.copyWith(height: 1.45),
          bodyMedium: t.bodyMedium?.copyWith(height: 1.45),
          labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
        )
        .apply(bodyColor: onSurface, displayColor: onSurface);
  }

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(brightness: scheme.brightness, useMaterial3: true);
    final text = _textTheme(base.textTheme, scheme.onSurface);
    final isDark = scheme.brightness == Brightness.dark;

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.headlineSmall,
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return text.labelMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 26,
            color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          );
        }),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer, size: 26),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 24),
        selectedLabelTextStyle: text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: text.labelMedium,
      ),

      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.large),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: text.labelLarge?.copyWith(fontSize: 16),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size.fromHeight(56),
          elevation: 0,
          textStyle: text.labelLarge?.copyWith(fontSize: 16),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: text.labelLarge,
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.small),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 2,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
        extendedTextStyle: text.labelLarge?.copyWith(fontSize: 16),
      ),

      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: AppRadius.medium,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.medium,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.medium,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.medium,
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.medium,
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.extraLarge),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.primaryContainer,
        labelStyle: text.labelLarge,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.small),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        trackHeight: 6,
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          highlightColor: scheme.primary.withValues(alpha: 0.12),
          shape: const CircleBorder(),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: AppRadius.small,
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),

      extensions: <ThemeExtension<dynamic>>[
        AppBrandColors(
          spotify: spotifyGreen,
          online: isDark ? const Color(0xFF7BE38B) : const Color(0xFF2E7D32),
        ),
      ],
    );
  }

  static ColorScheme get _lightScheme => ColorScheme.fromSeed(
        seedColor: _seedLight,
        brightness: Brightness.light,
      ).copyWith(
        surface: const Color(0xFFFCFAF3),
        surfaceContainerLowest: const Color(0xFFFFFFFF),
        surfaceContainerLow: const Color(0xFFF8F5EC),
        surfaceContainer: const Color(0xFFF2EFE5),
        surfaceContainerHigh: const Color(0xFFECE9DE),
        surfaceContainerHighest: const Color(0xFFE6E3D8),
      );

  static ColorScheme get _darkScheme => ColorScheme.fromSeed(
        seedColor: _seedDark,
        brightness: Brightness.dark,
      ).copyWith(
        surface: const Color(0xFF101210),
        surfaceContainerLowest: const Color(0xFF0A0B0A),
        surfaceContainerLow: const Color(0xFF161816),
        surfaceContainer: const Color(0xFF1B1E1B),
        surfaceContainerHigh: const Color(0xFF232622),
        surfaceContainerHighest: const Color(0xFF2C302B),
      );

  static ThemeData get light => _build(_lightScheme);
  static ThemeData get dark => _build(_darkScheme);
}

@immutable
class AppBrandColors extends ThemeExtension<AppBrandColors> {
  const AppBrandColors({required this.spotify, required this.online});

  final Color spotify;
  final Color online;

  @override
  AppBrandColors copyWith({Color? spotify, Color? online}) =>
      AppBrandColors(spotify: spotify ?? this.spotify, online: online ?? this.online);

  @override
  AppBrandColors lerp(ThemeExtension<AppBrandColors>? other, double t) {
    if (other is! AppBrandColors) return this;
    return AppBrandColors(
      spotify: Color.lerp(spotify, other.spotify, t)!,
      online: Color.lerp(online, other.online, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
  AppBrandColors get brand => Theme.of(this).extension<AppBrandColors>()!;
}