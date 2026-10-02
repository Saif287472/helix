import 'dart:convert';

import 'package:helix_remote_api/src/v2/transport/errors.dart';
import 'package:helix_remote_api/src/v2/transport/transport.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The `ops` module's client routes: health, server info, legal documents,
/// crash telemetry and the app-link documents. The admin-only metrics route
/// is `AdminClient.metrics` (it needs the admin token audience).
final class OpsClient {
  const OpsClient(this._t);

  final HelixTransport _t;

  Future<LiveResponse> live() => _t.call(Routes.live, LiveResponse.fromJson);

  /// Also returns (rather than throws) the 503 "not ready" answer.
  Future<ReadyResponse> ready() =>
      _t.call(Routes.ready, ReadyResponse.fromJson, accept: const {503});

  /// What a client needs before signing in.
  Future<ServerInfo> serverInfo() =>
      _t.call(Routes.serverInfo, ServerInfo.fromJson);

  Future<LegalDocuments> legal() =>
      _t.call(Routes.legal, LegalDocuments.fromJson);

  /// Opt-in only, and only while the `crash_reporting_upload` flag is on
  /// (`forbidden` otherwise). Redact [CrashReport.fields] first.
  Future<void> crashReport(CrashReport report) =>
      _t.empty(Routes.crashReport, json: report.toJson());

  /// The Android asset-links statements (a JSON list).
  Future<List<Object?>> assetLinks() async {
    final response = await _t.send(Routes.assetLinks);
    try {
      final value = jsonDecode(response.text);
      if (value is List) return value.cast<Object?>();
    } on FormatException {
      // Fall through.
    }
    throw MalformedResponseException(path: '', requestId: response.requestId);
  }

  /// The HTML landing page for shared `#HLX-…` links.
  Future<String> openPage() async => (await _t.send(Routes.openLink)).text;
}
