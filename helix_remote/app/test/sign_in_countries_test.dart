import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_countries.dart';

void main() {
  test('Bangladesh is first, and the rest of the world is there', () {
    expect(signInCountries.first.code, '+880');
    expect(signInCountries.length, greaterThan(150));
    final names = signInCountries.map((c) => c.name).toSet();
    for (final n in ['Nigeria', 'Brazil', 'Japan', 'Germany', 'Kenya']) {
      expect(names, contains(n));
    }
  });

  test('a code appears once, so a pick is never ambiguous', () {
    final codes = signInCountries.map((c) => c.code).toList();
    expect(codes.toSet().length, codes.length);
    for (final c in codes) {
      expect(c, matches(RegExp(r'^\+[1-9][0-9]{0,3}$')));
    }
  });

  test('a code not listed asks for at least seven digits', () {
    expect(signInMinDigits('+234'), 7);
    expect(signInMinDigits('+880'), 10);
    expect(signInMinDigits('+9999'), 7);
  });
}
