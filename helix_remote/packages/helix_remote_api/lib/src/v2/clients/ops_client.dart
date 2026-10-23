import 'dart:convert';
import 'dart:typed_data';

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

  /// The app's anomaly log, a batch at a time (at most
  /// [AnomalyReport.maxEntries]). Sanitise the entries first in a release
  /// build.
  Future<void> anomalies(AnomalyReport report) =>
      _t.empty(Routes.anomalies, json: report.toJson());

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

  /// The HTML landing page for a `/u/<~name>` share link. [helixName] is
  /// without its `~`; the page never answers whether the name exists.
  Future<String> sharePage(String helixName) async =>
      (await _t.send(Routes.shareLink, params: {'name': helixName})).text;

  // ------------------------------------------------------------- theme packs
  // The client asks for bytes and hands them over. It does not read a
  // manifest, and it must not: `checkOrbitPack` in `helix_remote_domain` is
  // the one place the format is understood, and it runs on exactly these bytes
  // (ADR-033). Anything this file knew about a pack would be a second
  // implementation to drift from the first.

  /// What this server hosts. The names and sizes here are a hint about what to
  /// fetch, never a fact about a pack: a hostile server can list anything.
  Future<OrbitPackList> packs() =>
      _t.call(Routes.packs, OrbitPackList.fromJson);

  /// A pack's manifest, as published and as signed.
  ///
  /// [packId] is the slug and [revision] the number from [packs]. Over
  /// 413 when the server's copy is bigger than the format allows.
  Future<Uint8List> packManifest(String packId, int revision) async =>
      (await _t.send(
        Routes.packManifest,
        params: {'pack_id': packId, 'revision': '$revision'},
        maxResponseBytes: maxManifestBytes,
      )).body;

  /// One file of a pack, by the SHA-256 its manifest gives it, in lowercase
  /// hex. The caller hashes what comes back and refuses it unless it matches -
  /// which is the whole point of asking by hash.
  Future<Uint8List> packFile(
    String packId,
    int revision,
    String digest,
  ) async => (await _t.send(
    Routes.packFile,
    params: {'pack_id': packId, 'revision': '$revision', 'digest': digest},
    maxResponseBytes: maxFileBytes,
  )).body;

  /// The pack format's own caps (`OrbitPackLimits` in `helix_remote_domain`,
  /// `docs/product/THEME_PACK_FORMAT.md`): a larger answer is not a pack this
  /// app can use, so it is never buffered.
  static const maxManifestBytes = 64 * 1024;
  static const maxFileBytes = 8 * 1024 * 1024;
}
