import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Approximation of Apple's Liquid Glass design language (iOS 26 /
/// macOS 26) implemented on top of Flutter's Material widget set.
///
/// Flutter does not ship a first-class Liquid Glass theme, so this is
/// not pixel-faithful to Tahoe / iOS 26. What it captures:
///
///   * Translucent surface tints — cards, app bars, scaffold backgrounds
///     all sit on low-alpha layers so blurred content can show through.
///   * Apple system colors — `systemBlue` accent, neutral group-grays
///     for backgrounds.
///   * Generous corner radii (16 px on cards, sheets, dialogs).
///   * No elevation shadows, no surface tint on scroll — glass is flat.
///   * No Material ink ripples — Apple platforms don't ripple.
///   * Cupertino-style page transitions everywhere.
///
/// For full effect on macOS the host window also needs vibrancy
/// (translucent backing) — that requires `flutter_acrylic` or similar
/// native plumbing and is out of scope here. The opt-in
/// [GlassSurface] widget gives per-card backdrop blur regardless.

/// `true` when the running platform is one Apple ships Liquid Glass on.
/// Web on Safari/iOS is excluded — `BackdropFilter` performance there is
/// poor and the app already runs Material there.
bool get isLiquidGlassPlatform {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

// ── Apple system color approximations ────────────────────────────────

const Color _systemBlueLight = Color(0xFF007AFF);
const Color _systemBlueDark = Color(0xFF0A84FF);

// iOS "systemGroupedBackground" / "secondarySystemGroupedBackground"
const Color _groupedBgLight = Color(0xFFF2F2F7);
const Color _cardBgLight = Color(0xFFFFFFFF);
const Color _groupedBgDark = Color(0xFF000000);
const Color _cardBgDark = Color(0xFF1C1C1E);

// Light/dark surface tints used when rendering against a non-vibrant
// host window. Higher alpha than a real OS-level glass material because
// without vibrancy beneath, full translucency would render almost
// invisible.
const double _surfaceAlphaLight = 0.78;
const double _surfaceAlphaDark = 0.72;

// ── Public theme builders ────────────────────────────────────────────

ThemeData liquidGlassLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: _systemBlueLight,
    brightness: Brightness.light,
  ).copyWith(
    primary: _systemBlueLight,
    surface: _groupedBgLight,
    onSurface: const Color(0xFF1C1C1E),
  );
  return _baseTheme(scheme).copyWith(
    scaffoldBackgroundColor: _groupedBgLight,
    cardTheme: CardThemeData(
      color: _cardBgLight.withValues(alpha: _surfaceAlphaLight),
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: _cardBgLight.withValues(alpha: 0.7),
      foregroundColor: const Color(0xFF1C1C1E),
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      centerTitle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _cardBgLight.withValues(alpha: 0.92),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: _cardBgLight.withValues(alpha: 0.92),
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: _cardBgLight.withValues(alpha: 0.92),
      modalElevation: 0,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}

ThemeData liquidGlassDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: _systemBlueDark,
    brightness: Brightness.dark,
  ).copyWith(
    primary: _systemBlueDark,
    surface: _groupedBgDark,
    onSurface: const Color(0xFFE5E5EA),
  );
  return _baseTheme(scheme).copyWith(
    scaffoldBackgroundColor: _groupedBgDark,
    cardTheme: CardThemeData(
      color: _cardBgDark.withValues(alpha: _surfaceAlphaDark),
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: _cardBgDark.withValues(alpha: 0.7),
      foregroundColor: const Color(0xFFE5E5EA),
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      centerTitle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _cardBgDark.withValues(alpha: 0.92),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: _cardBgDark.withValues(alpha: 0.92),
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: _cardBgDark.withValues(alpha: 0.92),
      modalElevation: 0,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}

ThemeData _baseTheme(ColorScheme scheme) {
  // Use Cupertino transitions everywhere on Apple platforms; they're
  // shorter and feel right on glass surfaces. NoSplash kills Material's
  // ink ripple — Apple controls don't ripple.
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        // Even on the long tail (web, desktop) prefer Cupertino under
        // this theme — the visual language is consistent.
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
      },
    ),
    // Filled buttons / FABs default to system blue; outlined buttons
    // get a thin glass border. ListTiles use a transparent background
    // so they blend with whatever Card/GlassSurface they sit in.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      tileColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.08),
      thickness: 0.5,
      space: 1,
    ),
  );
}
