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

  @override
  Future<HelixLocalizations> load(Locale locale) async =>
      HelixLocalizations(locale);

  @override
  bool shouldReload(_HelixLocalizationsDelegate old) => false;
}
