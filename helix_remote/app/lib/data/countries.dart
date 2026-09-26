/// Country data for phone-number entry during onboarding.
///
/// Split out of the old `country_code_picker.dart`, which bundled this table
/// together with a `CountryCodeSelector` / `PhoneNumberInput` pair that nothing
/// imported. The welcome steps keep their own dropdown design; this is only the
/// list behind it, so the two inline 9- and 6-entry lists can cover every
/// country the server accepts a phone number from.
///
/// The table is a superset of either earlier inline list. Adding a country here
/// makes it selectable on both the global and the personal-server verification
/// steps; nothing else needs to change.
library;

/// A country's name, ISO 3166-1 alpha-2 code, and international dialling code.
class Country {
  const Country({
    required this.name,
    required this.isoCode,
    required this.dialCode,
  });

  final String name;
  final String isoCode;
  final String dialCode;

  /// Regional-indicator flag emoji, derived from [isoCode] rather than stored
  /// per entry: each letter maps to a Unicode regional indicator symbol
  /// (U+1F1E6 = 'A'), so BD becomes the Bangladesh flag.
  String get flagEmoji {
    const regionalIndicatorBase = 0x1F1E6;
    const asciiA = 0x41;
    final codeUnits = isoCode.toUpperCase().codeUnits.map(
      (c) => regionalIndicatorBase + (c - asciiA),
    );
    return String.fromCharCodes(codeUnits);
  }

  /// `+880` and `(+880)`, the two forms that appear in the UI, both normalise
  /// to the same wire value.
  String get normalizedDialCode =>
      dialCode.replaceAll(RegExp(r'[^0-9+]'), '');

  @override
  bool operator ==(Object other) =>
      other is Country && other.isoCode == isoCode;

  @override
  int get hashCode => isoCode.hashCode;
}

/// Every country offered during onboarding, sorted by name.
const List<Country> kCountries = [
  Country(name: 'Afghanistan', isoCode: 'AF', dialCode: '+93'),
  Country(name: 'Albania', isoCode: 'AL', dialCode: '+355'),
  Country(name: 'Algeria', isoCode: 'DZ', dialCode: '+213'),
  Country(name: 'Argentina', isoCode: 'AR', dialCode: '+54'),
  Country(name: 'Armenia', isoCode: 'AM', dialCode: '+374'),
  Country(name: 'Australia', isoCode: 'AU', dialCode: '+61'),
  Country(name: 'Austria', isoCode: 'AT', dialCode: '+43'),
  Country(name: 'Azerbaijan', isoCode: 'AZ', dialCode: '+994'),
  Country(name: 'Bahrain', isoCode: 'BH', dialCode: '+973'),
  Country(name: 'Bangladesh', isoCode: 'BD', dialCode: '+880'),
  Country(name: 'Belarus', isoCode: 'BY', dialCode: '+375'),
  Country(name: 'Belgium', isoCode: 'BE', dialCode: '+32'),
  Country(name: 'Bhutan', isoCode: 'BT', dialCode: '+975'),
  Country(name: 'Bolivia', isoCode: 'BO', dialCode: '+591'),
  Country(name: 'Bosnia and Herzegovina', isoCode: 'BA', dialCode: '+387'),
  Country(name: 'Brazil', isoCode: 'BR', dialCode: '+55'),
  Country(name: 'Brunei', isoCode: 'BN', dialCode: '+673'),
  Country(name: 'Bulgaria', isoCode: 'BG', dialCode: '+359'),
  Country(name: 'Cambodia', isoCode: 'KH', dialCode: '+855'),
  Country(name: 'Cameroon', isoCode: 'CM', dialCode: '+237'),
  Country(name: 'Canada', isoCode: 'CA', dialCode: '+1'),
  Country(name: 'Chile', isoCode: 'CL', dialCode: '+56'),
  Country(name: 'China', isoCode: 'CN', dialCode: '+86'),
  Country(name: 'Colombia', isoCode: 'CO', dialCode: '+57'),
  Country(name: 'Costa Rica', isoCode: 'CR', dialCode: '+506'),
  Country(name: 'Croatia', isoCode: 'HR', dialCode: '+385'),
  Country(name: 'Cuba', isoCode: 'CU', dialCode: '+53'),
  Country(name: 'Cyprus', isoCode: 'CY', dialCode: '+357'),
  Country(name: 'Czech Republic', isoCode: 'CZ', dialCode: '+420'),
  Country(name: 'Denmark', isoCode: 'DK', dialCode: '+45'),
  Country(name: 'Dominican Republic', isoCode: 'DO', dialCode: '+1'),
  Country(name: 'Ecuador', isoCode: 'EC', dialCode: '+593'),
  Country(name: 'Egypt', isoCode: 'EG', dialCode: '+20'),
  Country(name: 'El Salvador', isoCode: 'SV', dialCode: '+503'),
  Country(name: 'Estonia', isoCode: 'EE', dialCode: '+372'),
  Country(name: 'Ethiopia', isoCode: 'ET', dialCode: '+251'),
  Country(name: 'Finland', isoCode: 'FI', dialCode: '+358'),
  Country(name: 'France', isoCode: 'FR', dialCode: '+33'),
  Country(name: 'Georgia', isoCode: 'GE', dialCode: '+995'),
  Country(name: 'Germany', isoCode: 'DE', dialCode: '+49'),
  Country(name: 'Ghana', isoCode: 'GH', dialCode: '+233'),
  Country(name: 'Greece', isoCode: 'GR', dialCode: '+30'),
  Country(name: 'Guatemala', isoCode: 'GT', dialCode: '+502'),
  Country(name: 'Honduras', isoCode: 'HN', dialCode: '+504'),
  Country(name: 'Hong Kong', isoCode: 'HK', dialCode: '+852'),
  Country(name: 'Hungary', isoCode: 'HU', dialCode: '+36'),
  Country(name: 'Iceland', isoCode: 'IS', dialCode: '+354'),
  Country(name: 'India', isoCode: 'IN', dialCode: '+91'),
  Country(name: 'Indonesia', isoCode: 'ID', dialCode: '+62'),
  Country(name: 'Iran', isoCode: 'IR', dialCode: '+98'),
  Country(name: 'Iraq', isoCode: 'IQ', dialCode: '+964'),
  Country(name: 'Ireland', isoCode: 'IE', dialCode: '+353'),
  Country(name: 'Israel', isoCode: 'IL', dialCode: '+972'),
  Country(name: 'Italy', isoCode: 'IT', dialCode: '+39'),
  Country(name: 'Jamaica', isoCode: 'JM', dialCode: '+1'),
  Country(name: 'Japan', isoCode: 'JP', dialCode: '+81'),
  Country(name: 'Jordan', isoCode: 'JO', dialCode: '+962'),
  Country(name: 'Kazakhstan', isoCode: 'KZ', dialCode: '+7'),
  Country(name: 'Kenya', isoCode: 'KE', dialCode: '+254'),
  Country(name: 'Kuwait', isoCode: 'KW', dialCode: '+965'),
  Country(name: 'Kyrgyzstan', isoCode: 'KG', dialCode: '+996'),
  Country(name: 'Laos', isoCode: 'LA', dialCode: '+856'),
  Country(name: 'Latvia', isoCode: 'LV', dialCode: '+371'),
  Country(name: 'Lebanon', isoCode: 'LB', dialCode: '+961'),
  Country(name: 'Libya', isoCode: 'LY', dialCode: '+218'),
  Country(name: 'Liechtenstein', isoCode: 'LI', dialCode: '+423'),
  Country(name: 'Lithuania', isoCode: 'LT', dialCode: '+370'),
  Country(name: 'Luxembourg', isoCode: 'LU', dialCode: '+352'),
  Country(name: 'Malaysia', isoCode: 'MY', dialCode: '+60'),
  Country(name: 'Maldives', isoCode: 'MV', dialCode: '+960'),
  Country(name: 'Malta', isoCode: 'MT', dialCode: '+356'),
  Country(name: 'Mexico', isoCode: 'MX', dialCode: '+52'),
  Country(name: 'Moldova', isoCode: 'MD', dialCode: '+373'),
  Country(name: 'Monaco', isoCode: 'MC', dialCode: '+377'),
  Country(name: 'Mongolia', isoCode: 'MN', dialCode: '+976'),
  Country(name: 'Montenegro', isoCode: 'ME', dialCode: '+382'),
  Country(name: 'Morocco', isoCode: 'MA', dialCode: '+212'),
  Country(name: 'Myanmar', isoCode: 'MM', dialCode: '+95'),
  Country(name: 'Nepal', isoCode: 'NP', dialCode: '+977'),
  Country(name: 'Netherlands', isoCode: 'NL', dialCode: '+31'),
  Country(name: 'New Zealand', isoCode: 'NZ', dialCode: '+64'),
  Country(name: 'Nicaragua', isoCode: 'NI', dialCode: '+505'),
  Country(name: 'Nigeria', isoCode: 'NG', dialCode: '+234'),
  Country(name: 'North Korea', isoCode: 'KP', dialCode: '+850'),
  Country(name: 'North Macedonia', isoCode: 'MK', dialCode: '+389'),
  Country(name: 'Norway', isoCode: 'NO', dialCode: '+47'),
  Country(name: 'Oman', isoCode: 'OM', dialCode: '+968'),
  Country(name: 'Pakistan', isoCode: 'PK', dialCode: '+92'),
  Country(name: 'Panama', isoCode: 'PA', dialCode: '+507'),
  Country(name: 'Paraguay', isoCode: 'PY', dialCode: '+595'),
  Country(name: 'Peru', isoCode: 'PE', dialCode: '+51'),
  Country(name: 'Philippines', isoCode: 'PH', dialCode: '+63'),
  Country(name: 'Poland', isoCode: 'PL', dialCode: '+48'),
  Country(name: 'Portugal', isoCode: 'PT', dialCode: '+351'),
  Country(name: 'Qatar', isoCode: 'QA', dialCode: '+974'),
  Country(name: 'Romania', isoCode: 'RO', dialCode: '+40'),
  Country(name: 'Russia', isoCode: 'RU', dialCode: '+7'),
  Country(name: 'Rwanda', isoCode: 'RW', dialCode: '+250'),
  Country(name: 'Saudi Arabia', isoCode: 'SA', dialCode: '+966'),
  Country(name: 'Serbia', isoCode: 'RS', dialCode: '+381'),
  Country(name: 'Singapore', isoCode: 'SG', dialCode: '+65'),
  Country(name: 'Slovakia', isoCode: 'SK', dialCode: '+421'),
  Country(name: 'Slovenia', isoCode: 'SI', dialCode: '+386'),
  Country(name: 'South Africa', isoCode: 'ZA', dialCode: '+27'),
  Country(name: 'South Korea', isoCode: 'KR', dialCode: '+82'),
  Country(name: 'Spain', isoCode: 'ES', dialCode: '+34'),
  Country(name: 'Sri Lanka', isoCode: 'LK', dialCode: '+94'),
  Country(name: 'Sudan', isoCode: 'SD', dialCode: '+249'),
  Country(name: 'Sweden', isoCode: 'SE', dialCode: '+46'),
  Country(name: 'Switzerland', isoCode: 'CH', dialCode: '+41'),
  Country(name: 'Syria', isoCode: 'SY', dialCode: '+963'),
  Country(name: 'Taiwan', isoCode: 'TW', dialCode: '+886'),
  Country(name: 'Tajikistan', isoCode: 'TJ', dialCode: '+992'),
  Country(name: 'Tanzania', isoCode: 'TZ', dialCode: '+255'),
  Country(name: 'Thailand', isoCode: 'TH', dialCode: '+66'),
  Country(name: 'Tunisia', isoCode: 'TN', dialCode: '+216'),
  Country(name: 'Turkey', isoCode: 'TR', dialCode: '+90'),
  Country(name: 'Turkmenistan', isoCode: 'TM', dialCode: '+993'),
  Country(name: 'Uganda', isoCode: 'UG', dialCode: '+256'),
  Country(name: 'Ukraine', isoCode: 'UA', dialCode: '+380'),
  Country(name: 'United Arab Emirates', isoCode: 'AE', dialCode: '+971'),
  Country(name: 'United Kingdom', isoCode: 'GB', dialCode: '+44'),
  Country(name: 'United States', isoCode: 'US', dialCode: '+1'),
  Country(name: 'Uruguay', isoCode: 'UY', dialCode: '+598'),
  Country(name: 'Uzbekistan', isoCode: 'UZ', dialCode: '+998'),
  Country(name: 'Venezuela', isoCode: 'VE', dialCode: '+58'),
  Country(name: 'Vietnam', isoCode: 'VN', dialCode: '+84'),
  Country(name: 'Yemen', isoCode: 'YE', dialCode: '+967'),
  Country(name: 'Zambia', isoCode: 'ZM', dialCode: '+260'),
  Country(name: 'Zimbabwe', isoCode: 'ZW', dialCode: '+263'),
];

/// The dialling codes offered during onboarding, in [kCountries] order.
///
/// The steps' dropdowns iterate this, so the two lists cannot drift apart.
List<String> get kCountryDialCodes =>
    kCountries.map((c) => c.dialCode).toList(growable: false);

/// The [Country] for a stored dialling code, or null when it is not one we
/// offer.
///
/// Used to keep a restored preference selectable, rather than letting a
/// `DropdownButton` silently snap back to its first entry because its value is
/// not in the item list.
Country? countryForDialCode(String dialCode) {
  final needle = dialCode.replaceAll(RegExp(r'[^0-9+]'), '');
  for (final country in kCountries) {
    if (country.normalizedDialCode == needle) return country;
  }
  return null;
}

/// The label a dropdown shows for [country]: flag, dialling code, and name.
///
/// The name is what makes a 130-entry list navigable - "+1" alone is ambiguous
/// across the countries that share it.
String countryLabel(Country country) =>
    '${country.flagEmoji}  ${country.dialCode}  ${country.name}';
