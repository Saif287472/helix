import 'package:flutter/material.dart';
import 'package:helix_remote/l10n/helix_localizations.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Wraps [home] the way the real shell does.
///
/// Screens read their copy through `HelixLocalizations.of(context)`, which
/// requires the delegate to be installed above them. A test that pumps a bare
/// `MaterialApp(home: screen)` gets a build failure that surfaces as
/// "Found 0 widgets with text ..." — the screen never rendered at all, which
/// reads like a missing string rather than a missing delegate.
///
/// Using this rather than repeating the wiring per test also means a test
/// exercises the same theme and locale setup the app ships.
Widget localizedTestApp(
  Widget home, {
  ThemeData? theme,
  Locale? locale,
  NavigatorObserver? navigatorObserver,
}) {
  return MaterialApp(
    localizationsDelegates: HelixLocalizations.localizationsDelegates,
    supportedLocales: HelixLocalizations.supportedLocales,
    locale: locale,
    theme: theme ?? HelixThemes.light(),
    navigatorObservers: [?navigatorObserver],
    home: home,
  );
}
