import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppMotion {
  const AppMotion._();

  static const Duration short = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 320);
  static const Duration long = Duration(milliseconds: 460);

  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);
  static const Curve emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);

  static const Curve spring = Cubic(0.34, 1.4, 0.64, 1.0);
}

class AppRadius {
  const AppRadius._();

  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
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

@immutable
class AppRoleColors extends ThemeExtension<AppRoleColors> {
  const AppRoleColors({
    required this.mine,
    required this.onMine,
    required this.theirs,
    required this.onTheirs,
    required this.spotify,
    required this.online,
  });

  final Color mine;
  final Color onMine;

  final Color theirs;
  final Color onTheirs;

  final Color spotify;
  final Color online;

  /// Цвет по роли. Избавляет вызывающий код от развилок.
  Color forMe(bool isMine) => isMine ? mine : theirs;
  Color onRole(bool isMine) => isMine ? onMine : onTheirs;

  @override
  AppRoleColors copyWith({
    Color? mine,
    Color? onMine,
    Color? theirs,
    Color? onTheirs,
    Color? spotify,
    Color? online,
  }) {
    return AppRoleColors(
      mine: mine ?? this.mine,
      onMine: onMine ?? this.onMine,
      theirs: theirs ?? this.theirs,
      onTheirs: onTheirs ?? this.onTheirs,
      spotify: spotify ?? this.spotify,
      online: online ?? this.online,
    );
  }

  @override
  AppRoleColors lerp(ThemeExtension<AppRoleColors>? other, double t) {
    if (other is! AppRoleColors) return this;
    return AppRoleColors(
      mine: Color.lerp(mine, other.mine, t)!,
      onMine: Color.lerp(onMine, other.onMine, t)!,
      theirs: Color.lerp(theirs, other.theirs, t)!,
      onTheirs: Color.lerp(onTheirs, other.onTheirs, t)!,
      spotify: Color.lerp(spotify, other.spotify, t)!,
      online: Color.lerp(online, other.online, t)!,
    );
  }
}

class AppTheme {
  static const Color _olive = Color(0xFF6A7A4E);

  static const Color _sea = Color(0xFF4E9B94);

  static const Color _lime = Color(0xFFC5E384);

  static const Color spotifyGreen = Color(0xFF1DB954);

  static TextTheme _textTheme(TextTheme base, Color onSurface) {
    final t = GoogleFonts.interTextTheme(base);
    return t
        .copyWith(
          displaySmall: t.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1),
          headlineLarge: t.headlineLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
          headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6),
          headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.4),
          titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
          titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          bodyLarge: t.bodyLarge?.copyWith(height: 1.5),
          bodyMedium: t.bodyMedium?.copyWith(height: 1.5),
          bodySmall: t.bodySmall?.copyWith(height: 1.4),
          labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0),
        )
        .apply(bodyColor: onSurface, displayColor: onSurface);
  }

  static ThemeData _build(ColorScheme scheme, AppRoleColors roles) {
    final base = ThemeData(brightness: scheme.brightness, useMaterial3: true);
    final text = _textTheme(base.textTheme, scheme.onSurface);

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[roles],

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
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: roles.mine.withValues(alpha: 0.18),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return text.labelSmall?.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? roles.mine : scheme.onSurfaceVariant,
          );
        }),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: roles.mine.withValues(alpha: 0.18),
        selectedIconTheme: IconThemeData(color: roles.mine, size: 24),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 24),
        selectedLabelTextStyle: text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
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
          backgroundColor: roles.mine,
          foregroundColor: roles.onMine,
          minimumSize: const Size.fromHeight(52),
          textStyle: text.labelLarge?.copyWith(fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: roles.mine,
          foregroundColor: roles.onMine,
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          textStyle: text.labelLarge?.copyWith(fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size.fromHeight(48),
          textStyle: text.labelLarge,
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: roles.mine,
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.small),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: roles.mine,
        foregroundColor: roles.onMine,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 2,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
        extendedTextStyle: text.labelLarge?.copyWith(fontSize: 15),
      ),

      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(borderRadius: AppRadius.medium, borderSide: BorderSide.none),
        enabledBorder:
            OutlineInputBorder(borderRadius: AppRadius.medium, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.medium,
          borderSide: BorderSide(color: roles.mine, width: 2),
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
        titleTextStyle: text.titleLarge,
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

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: roles.mine.withValues(alpha: 0.18),
        labelStyle: text.labelLarge,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.small),
      ),

      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: roles.mine,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: roles.mine,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: roles.mine,
        overlayColor: roles.mine.withValues(alpha: 0.12),
        trackHeight: 4,
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          highlightColor: roles.mine.withValues(alpha: 0.12),
          shape: const CircleBorder(),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: scheme.inverseSurface, borderRadius: AppRadius.small),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
    );
  }

  static ColorScheme get _lightScheme => ColorScheme.fromSeed(
        seedColor: _olive,
        brightness: Brightness.light,
      ).copyWith(
        primary: _olive,
        surface: const Color(0xFFFCFAF3),
        surfaceContainerLowest: const Color(0xFFFFFFFF),
        surfaceContainerLow: const Color(0xFFF8F5EC),
        surfaceContainer: const Color(0xFFF2EFE5),
        surfaceContainerHigh: const Color(0xFFECE9DE),
        surfaceContainerHighest: const Color(0xFFE6E3D8),
        outlineVariant: const Color(0xFFDCD8CB),
      );

  static ColorScheme get _darkScheme => ColorScheme.fromSeed(
        seedColor: _lime,
        brightness: Brightness.dark,
      ).copyWith(
        primary: _lime,
        surface: const Color(0xFF101210),
        surfaceContainerLowest: const Color(0xFF0A0B0A),
        surfaceContainerLow: const Color(0xFF161816),
        surfaceContainer: const Color(0xFF1B1E1B),
        surfaceContainerHigh: const Color(0xFF232622),
        surfaceContainerHighest: const Color(0xFF2C302B),
        outlineVariant: const Color(0xFF343A33),
      );

  static const AppRoleColors _lightRoles = AppRoleColors(
    mine: _olive,
    onMine: Color(0xFFFFFFFF),
    theirs: _sea,
    onTheirs: Color(0xFFFFFFFF),
    spotify: spotifyGreen,
    online: Color(0xFF3E8E5A),
  );

  static const AppRoleColors _darkRoles = AppRoleColors(
    mine: _lime,
    onMine: Color(0xFF1E2810),
    theirs: Color(0xFF6FC2BA),
    onTheirs: Color(0xFF06322E),
    spotify: spotifyGreen,
    online: Color(0xFF7BD69B),
  );

  static ThemeData get light => _build(_lightScheme, _lightRoles);
  static ThemeData get dark => _build(_darkScheme, _darkRoles);
}

extension AppThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
  AppRoleColors get roles => Theme.of(this).extension<AppRoleColors>()!;

  AppRoleColors get brand => roles;
}