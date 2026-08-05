import 'package:flutter/material.dart';

/// A country's name, ISO 3166-1 alpha-2 code, and international dialing
/// code, used by [CountryCodeSelector]/[PhoneNumberInput] to build a
/// combined country-selector + national-number phone input instead of
/// asking users to type a full E.164 number (country code included) by
/// hand.
class Country {
  const Country({
    required this.name,
    required this.isoCode,
    required this.dialCode,
  });

  final String name;
  final String isoCode;
  final String dialCode;

  /// Regional-indicator flag emoji, computed from [isoCode] rather than
  /// stored per-entry - each letter maps to a Unicode regional indicator
  /// symbol (U+1F1E6 = 'A'), so e.g. "BD" becomes the Bangladesh flag.
  String get flagEmoji {
    const regionalIndicatorBase = 0x1F1E6;
    const asciiA = 0x41;
    final codeUnits = isoCode.toUpperCase().codeUnits.map(
      (c) => regionalIndicatorBase + (c - asciiA),
    );
    return String.fromCharCodes(codeUnits);
  }

  @override
  bool operator ==(Object other) =>
      other is Country && other.isoCode == isoCode;

  @override
  int get hashCode => isoCode.hashCode;
}

/// Common countries, sorted by name. Not exhaustive - covers the countries
/// most likely to matter for this app's userbase without carrying every
/// territory/dependency in the world.
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

const Country kDefaultCountry = Country(
  name: 'Bangladesh',
  isoCode: 'BD',
  dialCode: '+880',
);

/// Finds the [Country] whose dial code is the longest matching prefix of
/// [e164] (longest, since dial codes overlap - e.g. `+1` vs `+91`), and
/// returns it along with the remaining national digits. Falls back to
/// [kDefaultCountry] with the input taken as-is if nothing matches (e.g.
/// malformed input) - used to pre-fill the country selector from a phone
/// number collected earlier in the flow.
({Country country, String nationalNumber}) splitE164PhoneNumber(String e164) {
  final digits = e164.startsWith('+') ? e164.substring(1) : e164;
  Country? bestMatch;
  for (final country in kCountries) {
    final code = country.dialCode.substring(1);
    if (digits.startsWith(code)) {
      if (bestMatch == null || code.length > bestMatch.dialCode.length - 1) {
        bestMatch = country;
      }
    }
  }
  if (bestMatch == null) {
    return (country: kDefaultCountry, nationalNumber: digits);
  }
  return (
    country: bestMatch,
    nationalNumber: digits.substring(bestMatch.dialCode.length - 1),
  );
}

/// Button showing the selected country's flag and dial code, styled to
/// match an adjacent `OutlineInputBorder` [TextField]. Tapping opens a
/// searchable bottom sheet to change it.
class CountryCodeSelector extends StatelessWidget {
  const CountryCodeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final Country selected;
  final ValueChanged<Country> onChanged;
  final bool enabled;

  Future<void> _openPicker(BuildContext context) async {
    final result = await showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CountryPickerSheet(),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    // IntrinsicWidth gives the InputDecorator a bounded width equal to its
    // content's natural size - without it, sitting as a non-Expanded child
    // of PhoneNumberInput's Row hands it an unbounded width constraint,
    // which InputDecorator explicitly asserts against (it's normally only
    // ever used inside a already-constrained TextField).
    return IntrinsicWidth(
      child: InkWell(
        onTap: enabled ? () => _openPicker(context) : null,
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(selected.flagEmoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 6),
              Text(selected.dialCode),
              const SizedBox(width: 2),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    );
  }
}

/// Combines [CountryCodeSelector] with a national-number text field. The
/// caller owns [numberController] (national digits only - no country code,
/// no leading zero expected) and the selected [country]; this widget is
/// purely presentational, matching the standard enterprise-app pattern of
/// `[ 🇧🇩 +880 ▾ ] [ 1712345678 ]` instead of asking for a hand-typed E.164
/// number.
class PhoneNumberInput extends StatelessWidget {
  const PhoneNumberInput({
    super.key,
    required this.country,
    required this.onCountryChanged,
    required this.numberController,
    this.enabled = true,
    this.errorText,
    this.errorMaxLines,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.next,
  });

  final Country country;
  final ValueChanged<Country> onCountryChanged;
  final TextEditingController numberController;
  final bool enabled;
  final String? errorText;

  /// Defaults to null, which - per [InputDecoration.errorMaxLines] -
  /// truncates [errorText] to a single line with an ellipsis instead of
  /// wrapping it. Server-provided error text (e.g. an SMS gateway's own
  /// rejection reason) can be longer than a label like "Invalid number",
  /// so callers showing that kind of text should set this explicitly.
  final int? errorMaxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CountryCodeSelector(
          selected: country,
          onChanged: onCountryChanged,
          enabled: enabled,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: numberController,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: 'Phone number',
              hintText: 'e.g. 1712345678',
              border: const OutlineInputBorder(),
              errorText: errorText,
              errorMaxLines: errorMaxLines,
            ),
            keyboardType: TextInputType.phone,
            textInputAction: textInputAction,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
      ],
    );
  }
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet();

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Country> get _filtered {
    if (_query.isEmpty) return kCountries;
    final query = _query.toLowerCase();
    return kCountries
        .where(
          (c) =>
              c.name.toLowerCase().contains(query) ||
              c.dialCode.contains(query) ||
              c.isoCode.toLowerCase() == query,
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        final filtered = _filtered;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          // Deliberately not mainAxisSize.min: this Column fills the
          // DraggableScrollableSheet's bounded height (search field + the
          // Expanded list below taking the rest), not just its own content.
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Search country or code',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No matching countries'))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final country = filtered[index];
                          return ListTile(
                            leading: Text(
                              country.flagEmoji,
                              style: const TextStyle(fontSize: 24),
                            ),
                            title: Text(country.name),
                            trailing: Text(country.dialCode),
                            onTap: () => Navigator.of(context).pop(country),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
