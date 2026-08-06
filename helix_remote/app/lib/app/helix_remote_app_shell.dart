import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:helix_remote/app/routes.dart';

/// The single application shell for every Remote startup state.
///
/// Bootstrap and authenticated UI are pages below this shell, not nested
/// applications. That gives them one navigator, theme, localization setup and
/// route table for the lifetime of the process.
class HelixRemoteAppShell extends StatelessWidget {
  const HelixRemoteAppShell({super.key, required this.home});

  final Widget home;

  static const _seedColor = Color(0xFF166A64);

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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
      ),
      highContrastTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          contrastLevel: 1,
        ),
      ),
      highContrastDarkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
          contrastLevel: 1,
        ),
      ),
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
