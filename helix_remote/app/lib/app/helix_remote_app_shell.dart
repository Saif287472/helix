import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:helix_remote/app/routes.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The single application shell for every Remote startup state.
///
/// Bootstrap and authenticated UI are pages below this shell, not nested
/// applications. That gives them one navigator, theme, localization setup and
/// route table for the lifetime of the process.
class HelixRemoteAppShell extends StatelessWidget {
  const HelixRemoteAppShell({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Helix Remote',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      theme: HelixThemes.light(),
      darkTheme: HelixThemes.dark(),
      highContrastTheme: HelixThemes.highContrastLight(),
      highContrastDarkTheme: HelixThemes.highContrastDark(),
      themeMode: ThemeMode.system,
      onGenerateRoute: RemoteRouter.onGenerateRoute,
      builder: _clampTextScale,
      home: home,
    );
  }
}

Widget _clampTextScale(BuildContext context, Widget? child) {
  final mediaQuery = MediaQuery.of(context);
  return MediaQuery(
    data: mediaQuery.copyWith(
      textScaler: mediaQuery.textScaler.clamp(maxScaleFactor: 1.3),
    ),
    child: child!,
  );
}
