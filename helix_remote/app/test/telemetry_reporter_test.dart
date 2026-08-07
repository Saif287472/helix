// MED-4 — crash reporting.
//
// The first pass at this finding added TelemetryConsent and
// RedactedTelemetryEvent, tested them, and wired them to nothing: no
// reference outside their own test file, so no crash was ever reported. This
// suite covers the part that closes the finding — the decision to send, and
// the guarantee that a denied user sends nothing.

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/services/telemetry_consent.dart';
import 'package:helix_remote/services/telemetry_reporter.dart';

class _RecordingSink implements TelemetrySink {
  final sent = <RedactedTelemetryEvent>[];

  @override
  Future<void> send(RedactedTelemetryEvent event) async => sent.add(event);
}

class _ThrowingSink implements TelemetrySink {
  @override
  Future<void> send(RedactedTelemetryEvent event) async =>
      throw StateError('sink offline');
}

void main() {
  test('a crash is not reported without consent, even with a sink', () async {
    final sink = _RecordingSink();
    final reporter = TelemetryReporter(sink: sink);

    expect(reporter.canReportCrashes, isFalse);
    await reporter.reportCrash(StateError('boom'), StackTrace.current);

    expect(sink.sent, isEmpty);
  });

  test('consent alone is not enough — a sink must exist', () async {
    final reporter = TelemetryReporter(
      consent: const TelemetryConsent(crashReporting: true),
    );

    expect(reporter.canReportCrashes, isFalse);
    // Would throw on a null sink if the guard were missing.
    await reporter.reportCrash(StateError('boom'), StackTrace.current);
  });

  test('with both, the crash is sent', () async {
    final sink = _RecordingSink();
    final reporter = TelemetryReporter(
      consent: const TelemetryConsent(crashReporting: true),
      sink: sink,
    );

    await reporter.reportCrash(StateError('boom'), StackTrace.current);

    expect(sink.sent, hasLength(1));
    expect(sink.sent.single.name, equals('app_crash'));
  });

  test('crash-report consent does not enable analytics', () async {
    // Two separate switches. Granting one must not imply the other, or the
    // consent is not informed.
    final sink = _RecordingSink();
    final reporter = TelemetryReporter(
      consent: const TelemetryConsent(crashReporting: true),
      sink: sink,
    );

    await reporter.reportEvent('conversation_opened');

    expect(sink.sent, isEmpty);
    expect(reporter.canReportAnalytics, isFalse);
  });

  test('a failing sink never propagates', () async {
    // A crash reporter that throws while reporting a crash turns one failure
    // into two, inside the zone handler that was already handling the first.
    final reporter = TelemetryReporter(
      consent: const TelemetryConsent(crashReporting: true),
      sink: _ThrowingSink(),
    );

    await expectLater(
      reporter.reportCrash(StateError('boom'), StackTrace.current),
      completes,
    );
  });

  test('clear() revokes consent and drops the sink', () async {
    final sink = _RecordingSink();
    final reporter = TelemetryReporter(
      consent: const TelemetryConsent(
        crashReporting: true,
        minimalAnalytics: true,
      ),
      sink: sink,
    );

    reporter.clear();
    await reporter.reportCrash(StateError('boom'), StackTrace.current);

    expect(sink.sent, isEmpty);
    expect(reporter.consent.crashReporting, isFalse);
    expect(reporter.consent.minimalAnalytics, isFalse);
  });

  test('the reported payload carries no raw token or phone number', () async {
    final sink = _RecordingSink();
    final reporter = TelemetryReporter(
      consent: const TelemetryConsent(crashReporting: true),
      sink: sink,
    );

    await reporter.reportCrash(
      StateError(
        'request failed: Bearer eyJhbGciOiJIUzI1NiJ9.abcdef.ghijkl '
        'phone=+8801712345678',
      ),
      StackTrace.current,
    );

    final encoded = sink.sent.single.encode();
    expect(encoded, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
    expect(encoded, isNot(contains('8801712345678')));
  });
}
