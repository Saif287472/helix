import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/services/telemetry_consent.dart';

void main() {
  test('telemetry is opt-in and crash events redact credentials', () {
    expect(const TelemetryConsent().crashReporting, isFalse);
    final event = RedactedTelemetryEvent.crash(
      'Bearer eyJhbGciOiJIUzI1NiJ9.secret.signature',
      StackTrace.fromString('token=super-secret'),
    );

    expect(event.encode(), isNot(contains('super-secret')));
    expect(
      event.encode(),
      isNot(contains('eyJhbGciOiJIUzI1NiJ9.secret.signature')),
    );
  });
}
