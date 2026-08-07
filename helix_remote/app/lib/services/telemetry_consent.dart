import 'dart:convert';

import 'package:helix_remote/services/log_redaction.dart';

/// Consent gate for optional diagnostics. It intentionally owns no transport:
/// a deployment must provide a reviewed uploader before redacted events can
/// leave a device. Both controls are disabled by default.
class TelemetryConsent {
  const TelemetryConsent({
    this.crashReporting = false,
    this.minimalAnalytics = false,
  });

  final bool crashReporting;
  final bool minimalAnalytics;

  Map<String, bool> toJson() => {
    'crash_reporting': crashReporting,
    'minimal_analytics': minimalAnalytics,
  };

  static TelemetryConsent fromJson(Map<String, dynamic>? json) =>
      TelemetryConsent(
        crashReporting: json?['crash_reporting'] == true,
        minimalAnalytics: json?['minimal_analytics'] == true,
      );
}

/// The only event shapes a future uploader may receive. This makes redaction
/// testable independently from any telemetry vendor.
class RedactedTelemetryEvent {
  RedactedTelemetryEvent.crash(Object error, StackTrace stack)
    : name = 'app_crash',
      fields = {
        'error': _redact(error.toString()),
        'stack': _redact(stack.toString().split('\n').take(5).join(' | ')),
      };

  RedactedTelemetryEvent.analytics(String name)
    : name = name,
      fields = const {};

  final String name;
  final Map<String, String> fields;

  String encode() => jsonEncode({'name': name, 'fields': fields});

  static String _redact(String value) => redactLogLine(value).replaceAllMapped(
    RegExp(r'\b(token|secret|password|key)=[^\s|]+', caseSensitive: false),
    (match) => '${match[1]}=[redacted]',
  );
}
