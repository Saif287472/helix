// Docker Compose's `env_file` doesn't strip quotes or CRLF the way a shell
// does - a live deployment hit "Attempt to read property is_masking on
// null" from BulkSMSBD, which is exactly the kind of server-side error a
// mismatched (quoted, or \r-suffixed) sender ID would produce.

import 'package:helix_remote_backend/src/env_sanitize.dart';
import 'package:test/test.dart';

void main() {
  test('a null value sanitizes to an empty string', () {
    expect(sanitizeEnvValue(null), equals(''));
  });

  test('a plain value passes through unchanged', () {
    expect(sanitizeEnvValue('880964890985'), equals('880964890985'));
  });

  test('surrounding whitespace is trimmed', () {
    expect(sanitizeEnvValue('  880964890985  '), equals('880964890985'));
  });

  test('a trailing carriage return (Windows-edited .env) is trimmed', () {
    expect(sanitizeEnvValue('880964890985\r'), equals('880964890985'));
  });

  test('matching double quotes are stripped', () {
    expect(sanitizeEnvValue('"880964890985"'), equals('880964890985'));
  });

  test('matching single quotes are stripped', () {
    expect(sanitizeEnvValue("'880964890985'"), equals('880964890985'));
  });

  test('mismatched quotes are left alone, not stripped', () {
    expect(sanitizeEnvValue('"880964890985\''), equals('"880964890985\''));
  });

  test('a lone quote character is left alone, not stripped to empty', () {
    expect(sanitizeEnvValue('"'), equals('"'));
  });

  test('only the outermost layer of quoting is stripped', () {
    expect(sanitizeEnvValue('"\'880964890985\'"'), equals("'880964890985'"));
  });
}
