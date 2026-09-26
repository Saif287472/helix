import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote/app/routes.dart';
import 'package:helix_remote/l10n/helix_localizations.dart';
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
      onGenerateTitle: (context) => HelixLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      // Both lists come from the generated catalog, so adding a locale to
      // l10n.yaml's arb-dir is the only edit a new language needs.
      localizationsDelegates: HelixLocalizations.localizationsDelegates,
      supportedLocales: HelixLocalizations.supportedLocales,
      theme: HelixThemes.light(),
      highContrastTheme: HelixThemes.highContrastLight(),
      // Light and colourful only, unconditionally. Dark mode is deferred for
      // this product, and `ThemeMode.system` meant a user on a dark device got
      // a near-black UI that no screen here had been visually reviewed
      // against. With no `darkTheme` registered and the mode pinned there is
      // no longer a path to a theme that does not exist.
      themeMode: ThemeMode.light,
      onGenerateRoute: RemoteRouter.onGenerateRoute,
      builder: (context, child) => Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) => Navigator.of(context).maybePop(),
            ),
          },
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: child!,
          ),
        ),
      ),
      home: home,
    );
  }
}
