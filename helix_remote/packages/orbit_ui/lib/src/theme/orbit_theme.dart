import 'package:flutter/material.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// Turns one theme's tokens into a Flutter [ThemeData].
///
/// The prototype is CSS: every colour is a custom property and the browser
/// decides which rule wins. Flutter has no cascade, so the port has to say
/// once, here, which token each Material role comes from. Nothing else in
/// `orbit_ui` may reach into [ColorScheme] by hand - a widget that wanted a
/// different shade would be inventing one.
///
/// Colours, plus the two things every screen inherits in the prototype: the
/// body font (`--font` on `.phone-screen`) and standard density, so Windows
/// does not shrink Material's controls the way its default "compact" density
/// would. Type sizes, shapes and elevation follow in Phase 3, when the
/// components that use them exist.
abstract final class OrbitTheme {
  static ThemeData of(OrbitTokens t) => ThemeData(
    useMaterial3: true,
    fontFamily: t.font.family,
    visualDensity: VisualDensity.standard,
    brightness: t.meta.dark ? Brightness.dark : Brightness.light,
    colorScheme: ColorScheme(
      brightness: t.meta.dark ? Brightness.dark : Brightness.light,
      primary: t.accent,
      onPrimary: t.onAccent,
      primaryContainer: t.accentSoft,
      onPrimaryContainer: t.accentInk,
      secondary: t.cyan,
      onSecondary: t.inBubble,
      secondaryContainer: t.successSoft,
      onSecondaryContainer: t.success,
      tertiary: t.cyanInk,
      onTertiary: t.onAccent,
      error: t.danger,
      onError: t.onBrand,
      errorContainer: t.dangerSoft,
      onErrorContainer: t.danger,
      surface: t.surface,
      onSurface: t.ink,
      onSurfaceVariant: t.ink3,
      surfaceContainerLowest: t.bg,
      surfaceContainerLow: t.surface,
      surfaceContainer: t.field,
      surfaceContainerHigh: t.field,
      surfaceContainerHighest: t.field,
      outline: t.controlLine,
      outlineVariant: t.line,
      shadow: t.ink,
      scrim: t.scrim,
      inverseSurface: t.inverse,
      onInverseSurface: t.onInverse,
      inversePrimary: t.inverseAccent,
    ),
    scaffoldBackgroundColor: t.bg,
    extensions: <ThemeExtension<dynamic>>[t],
  );
}
