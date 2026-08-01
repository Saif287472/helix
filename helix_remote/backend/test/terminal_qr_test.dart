import 'package:test/test.dart';

import '../bin/src/terminal_qr.dart';

void main() {
  test('renders a multi-line block of terminal QR output', () {
    final output = renderTerminalQr('a-sample-admin-token-1234567890');
    expect(output, isNotEmpty);
    expect(output.split('\n').length, greaterThan(5));
    // Only the expected block-drawing characters, spaces and newlines.
    expect(RegExp(r'^[ █▀▄\r\n]*$').hasMatch(output), isTrue);
  });

  test('different inputs produce different QR output', () {
    final a = renderTerminalQr('token-aaaaaaaaaaaaaaaaaaaaaaaa');
    final b = renderTerminalQr('token-bbbbbbbbbbbbbbbbbbbbbbbb');
    expect(a, isNot(equals(b)));
  });

  test('does not throw for a realistic base64url admin token', () {
    expect(
      () => renderTerminalQr('AbCdEfGhIjKlMnOpQrStUvWxYz012345'),
      returnsNormally,
    );
  });
}
