import 'package:helix_remote_domain/models.dart';
import 'package:test/test.dart';

/// The legal texts the server reports and the app shows (review F-05: the
/// package had no tests, and the verify scripts skipped it silently).
void main() {
  test('versions are dates, and each document states its own', () {
    final date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    expect(HelixLegalDocuments.termsVersion, matches(date));
    expect(HelixLegalDocuments.privacyVersion, matches(date));
    expect(
      HelixLegalDocuments.termsOfService,
      contains('Version: ${HelixLegalDocuments.termsVersion}'),
    );
    expect(
      HelixLegalDocuments.privacyPolicy,
      contains('Version: ${HelixLegalDocuments.privacyVersion}'),
    );
  });

  test('each document starts with its title and states the effective date', () {
    for (final (title, text) in [
      (HelixLegalDocuments.termsTitle, HelixLegalDocuments.termsOfService),
      (HelixLegalDocuments.privacyTitle, HelixLegalDocuments.privacyPolicy),
    ]) {
      expect(text.trimLeft(), startsWith(title));
      expect(
        text,
        contains('Effective date: ${HelixLegalDocuments.effectiveDate}'),
      );
    }
  });
}
