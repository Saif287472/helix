/// The dialling codes the country picker offers (Review 1 of the Orbit port:
/// a picker, Bangladesh by default; client only, no phone-number package).
///
/// Each entry is the code with its `+`, the country's name, and the fewest
/// national digits a mobile number there has, so Next can refuse a number
/// that is too short before anything is sent.
typedef SignInCountry = ({String code, String name, int minDigits});

/// Bangladesh first, then the prototype's order (`COUNTRIES` in
/// `orbit/prototype/js/screens/signin.js`).
const signInCountries = <SignInCountry>[
  (code: '+880', name: 'Bangladesh', minDigits: 10),
  (code: '+91', name: 'India', minDigits: 10),
  (code: '+92', name: 'Pakistan', minDigits: 10),
  (code: '+977', name: 'Nepal', minDigits: 10),
  (code: '+60', name: 'Malaysia', minDigits: 9),
  (code: '+966', name: 'Saudi Arabia', minDigits: 9),
  (code: '+971', name: 'United Arab Emirates', minDigits: 9),
  (code: '+44', name: 'United Kingdom', minDigits: 10),
  (code: '+1', name: 'United States', minDigits: 10),
];

/// The fewest national digits for [code]; 7 for a code not in the list.
int signInMinDigits(String code) =>
    signInCountries.where((c) => c.code == code).firstOrNull?.minDigits ?? 7;
