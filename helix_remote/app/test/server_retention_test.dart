import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/plans/server_retention.dart';

void main() {
  test('says how long files stay, and that the phone keeps its copy', () {
    const terms = ServerRetentionTerms(days: 30);
    expect(terms.note, contains('stay on the server for 30 days'));
    expect(terms.note, contains('your copy on this phone stays'));
    expect(terms.note, isNot(contains('Premium')));
  });

  test('names Premium only when it keeps them longer for this account', () {
    const terms = ServerRetentionTerms(days: 30, premiumDays: 90);
    expect(terms.note, endsWith('Orbit Premium keeps them 90 days.'));
  });
}
