import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The nested/sunken surface tone used for the sidebar, app bar, and inline
/// code/example blocks: one step darker than the page background in dark
/// mode, one step more tinted than it in light mode. Material's ColorScheme
/// only models a flat background/surface pair, so this fills the gap rather
/// than smuggling a third hardcoded hex value into every screen that needs
/// it.
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

/// Helix Admin's light and dark themes.
///
/// `primary` (violet) is fixed across both brightnesses - it has enough
/// contrast against both a near-black and a near-white surface to work as
/// icon/button fill either way. `accent` (the cyan highlight used for links
/// and monospace values) does not: bright cyan text is unreadable on a white
/// page, so it's tuned separately per brightness instead of reused verbatim.
class AppTheme {
  AppTheme._();

  static const _primary = HelixColorTokens.cFF8A2BE2;

  static final ThemeData dark = light;

  static final ThemeData light = _build(
    brightness: Brightness.light,
    background: const Color(0xFFF1F5F9),
    surface: Colors.white,
    sunken: const Color(0xFFE2E8F0),
    onSurface: const Color(0xFF1E293B),
    accent: const Color(0xFF2563EB),
    error: const Color(0xFFDC2626),
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color sunken,
    required Color onSurface,
    required Color accent,
    required Color error,
  }) {
    final colorScheme = brightness == Brightness.dark
        ? ColorScheme.dark(
            primary: _primary,
            secondary: accent,
            error: error,
            surface: surface,
            onSurface: onSurface,
          )
        : ColorScheme.light(
            primary: _primary,
            secondary: accent,
            error: error,
            surface: surface,
            onSurface: onSurface,
          );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
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
/// every call site. Each tier mirrors what the old dark-only design used
/// (`Colors.white`, `Colors.white70`, `Colors.white54`, `Colors.white38`) but
/// derived from the active theme's `onSurface`, so it lands on the correct
/// near-black or near-white base in both brightnesses instead of only ever
/// being legible on a dark card.
extension AppColorsX on BuildContext {
  ColorScheme get _scheme => Theme.of(this).colorScheme;

  Color get textPrimary => _scheme.onSurface;
  Color get textSecondary => _scheme.onSurface.withValues(alpha: 0.70);
  Color get textTertiary => _scheme.onSurface.withValues(alpha: 0.54);
  Color get textFaint => _scheme.onSurface.withValues(alpha: 0.38);

  /// The cyan/teal accent used for links, highlighted borders, and
  /// monospace values - tuned per brightness, see [AppTheme].
  Color get accentColor => _scheme.secondary;

  /// The sidebar/app-bar/code-block surface tone. See [AppSurfaces].
  Color get sunkenSurface =>
      Theme.of(this).extension<AppSurfaces>()?.sunken ??
      (Theme.of(this).brightness == Brightness.dark
          ? const Color(0xFF0B0B12)
          : const Color(0xFFEDEAF5));
}
