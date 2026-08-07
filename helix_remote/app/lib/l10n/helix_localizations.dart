import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/widgets.dart';

/// First-party strings used by application chrome. Feature strings migrate to
/// this catalog as their screens are touched; falling back to English is
/// intentional until a reviewed Bengali translation is available.
class HelixLocalizations {
  const HelixLocalizations(this.locale);

  final Locale locale;

  static const delegate = _HelixLocalizationsDelegate();

  static HelixLocalizations of(BuildContext context) =>
      Localizations.of<HelixLocalizations>(context, HelixLocalizations)!;

  String get appTitle =>
      locale.languageCode == 'bn' ? 'হেলিক্স রিমোট' : 'Helix Remote';
}

class _HelixLocalizationsDelegate
    extends LocalizationsDelegate<HelixLocalizations> {
  const _HelixLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      const {'en', 'bn'}.contains(locale.languageCode);

  /// Returns a [SynchronousFuture], which is load-bearing rather than a
  /// micro-optimisation.
  ///
  /// `Localizations` renders **nothing** until every delegate's future
  /// completes, and it can only skip that wait when all of them complete
  /// synchronously. Written as `async`, this delegate returned a future that
  /// completes a microtask later, so the whole app — every startup state,
  /// including the configuration-error screen — rendered one blank frame on
  /// launch. There is no I/O here to justify it: the catalog is compiled in
  /// and lookup is a constant-time switch on the locale.
  ///
  /// The blank frame was visible to widget tests as "found 0 widgets" after
  /// `pumpWidget`, which is how it was found.
  @override
  Future<HelixLocalizations> load(Locale locale) =>
      SynchronousFuture(HelixLocalizations(locale));

  @override
  bool shouldReload(_HelixLocalizationsDelegate old) => false;
}
