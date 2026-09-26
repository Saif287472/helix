import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The nested/sunken surface tone used for the sidebar, app bar, and inline
/// code/example blocks: one step more tinted than the page background.
/// Material's ColorScheme only models a flat background/surface pair, so this
/// fills the gap rather than smuggling a third hardcoded hex value into every
/// screen that needs it.
class AppSurfaces extends ThemeExtension<AppSurfaces> {
  const AppSurfaces({required this.sunken});

  final Color sunken;

  @override
  AppSurfaces copyWith({Color? sunken}) =>
      AppSurfaces(sunken: sunken ?? this.sunken);

  @override
  AppSurfaces lerp(ThemeExtension<AppSurfaces>? other, double t) {
    if (other is! AppSurfaces) return this;
    return AppSurfaces(sunken: Color.lerp(sunken, other.sunken, t)!);
  }
}

/// Helix Admin's theme.
///
/// Light only, deliberately. Dark mode is deferred for this product: the
/// console is meant to be light and colourful, and the previous `AppTheme.dark`
/// was literally `AppTheme.light` with a dark-mode-shaped name - so
/// `ThemeMode.dark` rendered pixel-identically to light while the dead branch
/// at [AppColorsX.sunkenSurface] kept a near-black surface value alive that
/// nothing could ever reach. There is one theme, and it is the light one.
class AppTheme {
  AppTheme._();

  static const _primary = HelixColorTokens.cFF8A2BE2;

  /// Fallback when no [AppSurfaces] extension is present in the tree. Light
  /// and tinted, matching the page background one step up.
  static const _sunkenFallback = Color(0xFFEDEAF5);

  static final ThemeData light = _build(
    background: const Color(0xFFF1F5F9),
    surface: Colors.white,
    sunken: const Color(0xFFE2E8F0),
    onSurface: const Color(0xFF1E293B),
    accent: const Color(0xFF2563EB),
    error: const Color(0xFFDC2626),
  );

  static ThemeData _build({
    required Color background,
    required Color surface,
    required Color sunken,
    required Color onSurface,
    required Color accent,
    required Color error,
  }) {
    final colorScheme = ColorScheme.light(
      primary: _primary,
      secondary: accent,
      error: error,
      surface: surface,
      onSurface: onSurface,
    );
    return ThemeData(
      useMaterial3: true,
      // Pinned rather than left to a brightness parameter: the app sets
      // `themeMode: ThemeMode.light` unconditionally, so this can only ever
      // be light, and asserting it here means a future `ColorScheme.dark`
      // cannot sneak in behind a removed parameter.
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      cardColor: surface,
      primaryColor: _primary,
      dividerColor: onSurface.withValues(alpha: 0.12),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: onSurface.withValues(alpha: 0.10)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      extensions: [AppSurfaces(sunken: sunken)],
    );
  }
}

/// Convenience accessors so screens reach for a semantic tier instead of
/// repeating `Theme.of(context).colorScheme.onSurface.withValues(...)` at
/// every call site. All four tiers are derived from the light theme's
/// `onSurface`, so each one lands on the same near-black base at a different
/// strength.
extension AppColorsX on BuildContext {
  ColorScheme get _scheme => Theme.of(this).colorScheme;

  Color get textPrimary => _scheme.onSurface;
  Color get textSecondary => _scheme.onSurface.withValues(alpha: 0.70);
  Color get textTertiary => _scheme.onSurface.withValues(alpha: 0.54);
  Color get textFaint => _scheme.onSurface.withValues(alpha: 0.38);

  /// The blue accent used for links, highlighted borders, and monospace
  /// values. Tuned for legibility on a white page.
  Color get accentColor => _scheme.secondary;

  /// The sidebar/app-bar/code-block surface tone. See [AppSurfaces].
  Color get sunkenSurface =>
      Theme.of(this).extension<AppSurfaces>()?.sunken ??
      AppTheme._sunkenFallback;
}
