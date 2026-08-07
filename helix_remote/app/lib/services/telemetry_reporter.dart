import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:helix_remote/app/remote_rest_client.dart';
import 'package:helix_remote/services/app_logger.dart';
import 'package:helix_remote/services/telemetry_consent.dart';

/// Where redacted telemetry goes once consent is granted.
///
/// An interface rather than a concrete client so the reporter can be tested
/// without a server, and so a deployment can point it at its own sink. There
/// is deliberately no default implementation that talks to a third party: the
/// audit's MED-4 recommendation was a *self-hosted* crash sink, and a vendor
/// SDK bundled here would be exactly the thing a privacy-first product must
/// not ship by accident.
abstract interface class TelemetrySink {
  Future<void> send(RedactedTelemetryEvent event);
}

/// Sends events to this deployment's own backend.
///
/// The audit's MED-4 recommendation was explicit that a self-hosted sink
/// satisfies both the observability goal and the privacy posture. This is
/// that sink: reports go to the same server the user already trusts with
/// their messages, and no third party is involved.
class RestTelemetrySink implements TelemetrySink {
  const RestTelemetrySink(this._client);

  final HelixRemoteRestClientImpl _client;

  @override
  Future<void> send(RedactedTelemetryEvent event) =>
      _client.reportTelemetryCrash(name: event.name, fields: event.fields);
}

/// Persists the user's telemetry choices.
///
/// Secure storage rather than shared preferences, matching how the rest of
/// the client stores state: it is the same store the reset path already
/// clears, so "delete my data" does not leave consent behind.
class TelemetryConsentStore {
  const TelemetryConsentStore();

  static const crashKey = 'helix_remote_telemetry_crash_reporting';
  static const analyticsKey = 'helix_remote_telemetry_minimal_analytics';

  static const _storage = FlutterSecureStorage();

  Future<TelemetryConsent> read() async {
    // Absent means denied. A first-run device with no stored value must not
    // report anything, so this cannot default to enabled.
    final crash = await _storage.read(key: crashKey);
    final analytics = await _storage.read(key: analyticsKey);
    return TelemetryConsent(
      crashReporting: crash == 'true',
      minimalAnalytics: analytics == 'true',
    );
  }

  Future<void> write(TelemetryConsent consent) async {
    await _storage.write(
      key: crashKey,
      value: consent.crashReporting.toString(),
    );
    await _storage.write(
      key: analyticsKey,
      value: consent.minimalAnalytics.toString(),
    );
  }
}

/// The one place that decides whether a diagnostic event may leave the device.
///
/// MED-4 recorded "no crash reporting and no analytics" and the first pass at
/// it added [TelemetryConsent] and [RedactedTelemetryEvent] — correct shapes,
/// tested, and referenced by nothing outside their own test file. That is the
/// same failure mode as the attachment lifecycle rules that were written,
/// tested, and never scheduled: the tests read as though the feature works.
/// This class is the part that was missing, and it is wired into the zone
/// error handlers in `main.dart`.
///
/// Fails closed at three points: no sink configured, consent not granted, or
/// the send throws. None of them may take down the app — a crash reporter
/// that crashes on a crash is worse than none.
class TelemetryReporter {
  TelemetryReporter({
    TelemetryConsent consent = const TelemetryConsent(),
    TelemetrySink? sink,
  }) : _consent = consent,
       _sink = sink;

  static TelemetryReporter instance = TelemetryReporter();

  TelemetryConsent _consent;
  TelemetrySink? _sink;

  TelemetryConsent get consent => _consent;

  /// True only when a sink exists *and* the user opted in. Exposed so the
  /// settings screen can say "unavailable on this server" rather than
  /// offering a switch that does nothing.
  bool get canReportCrashes => _sink != null && _consent.crashReporting;

  bool get canReportAnalytics => _sink != null && _consent.minimalAnalytics;

  void configure({TelemetryConsent? consent, TelemetrySink? sink}) {
    if (consent != null) _consent = consent;
    if (sink != null) _sink = sink;
  }

  /// Forgets the sink and revokes consent in memory. Used by the reset path.
  void clear() {
    _consent = const TelemetryConsent();
    _sink = null;
  }

  Future<void> reportCrash(Object error, StackTrace stack) async {
    if (!canReportCrashes) return;
    await _send(RedactedTelemetryEvent.crash(error, stack));
  }

  Future<void> reportEvent(String name) async {
    if (!canReportAnalytics) return;
    await _send(RedactedTelemetryEvent.analytics(name));
  }

  Future<void> _send(RedactedTelemetryEvent event) async {
    try {
      await _sink!.send(event);
    } catch (e) {
      // Local-only, and itself redacted by AppLogger's write boundary. The
      // point of recording it is that a sink failing silently forever is
      // indistinguishable from a product with no crashes.
      AppLogger.instance.warn('telemetry', 'event upload failed: $e');
    }
  }
}
