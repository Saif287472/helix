import 'dart:async';
import 'dart:convert';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/ops/api.dart';
import 'package:helix_remote_server/src/kernel/crypto.dart';
import 'package:helix_remote_server/src/modules/ops/open_page.dart';
import 'package:helix_remote_server/src/modules/ops/pack_host.dart';
import 'package:helix_remote_server/src/modules/ops/share_page.dart';
import 'package:helix_remote_server/src/platform/bus/event_bus.dart';
import 'package:helix_remote_server/src/platform/config/server_config.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:helix_remote_server/src/platform/observability/metrics.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:helix_remote_server/src/version.dart';
import 'package:shelf/shelf.dart';

/// Health, server info, legal documents, crash and anomaly telemetry, metrics, app
/// links, and the operator settings behind them: server name, maintenance
/// mode, federation switch and feature flags. Schema `ops`.
final class OpsModule extends ModuleBase implements ProvidesMaintenance {
  OpsModule(super.context) {
    api = _OpsFacade(this);
    _crashes = context.metrics.counter(
      'helix_client_crash_reports_total',
      'Opt-in crash reports received',
    );
    _anomalies = context.metrics.counter(
      'helix_client_anomalies_total',
      'Anomalies the apps reported',
    );
    _federationDefault = envFlag(
      context.config.env,
      'HELIX_FEDERATION_ENABLED',
    );
    final token = context.config.metricsToken;
    _metricsToken = token == null ? null : utf8.encode(token);
  }

  late final bool _federationDefault;
  late final List<int>? _metricsToken;

  /// The facade other modules receive.
  late final OpsApi api;
  late final Counter _crashes;
  late final Counter _anomalies;

  static const _probe = RateLimitPolicy(
    'ops.probe',
    capacity: 120,
    perSecond: 2,
  );
  static final _crashLimit = RateLimitPolicy.per(
    'ops.crash',
    10,
    const Duration(hours: 1),
  );
  static final _anomalyLimit = RateLimitPolicy.per(
    'ops.anomalies',
    120,
    const Duration(hours: 1),
  );

  /// The pack folder. `HELIX_PACKS_DIR` unset is the same as an empty folder:
  /// the list is empty and every file is a 404, so there is nothing to switch
  /// on and no half-configured state to fail in.
  ///
  /// One host for the node's life, not one per request: the host holds the
  /// list index, and a per-request instance would walk the folder every time.
  late final PackHost _packs = PackHost(context.config.packsDirectory);

  /// Browsing the gallery is a list plus one manifest per pack, so the two
  /// first policies are sized for one page opening, and the third for the
  /// handful of files a pack holds. All three are keyed per client IP by the
  /// pipeline, like every public route.
  static const _packListLimit = RateLimitPolicy(
    'packs.list',
    capacity: 60,
    perSecond: 1,
  );
  static const _packManifestLimit = RateLimitPolicy(
    'packs.manifest',
    capacity: 120,
    perSecond: 2,
  );
  static const _packFileLimit = RateLimitPolicy(
    'packs.file',
    capacity: 60,
    perSecond: 1,
  );

  /// Settings are cached per node; a change is announced on this topic and
  /// the cache also expires, in case a notification is missed.
  static const _changedTopic = 'ops.settings';
  static const _cacheLifetime = Duration(seconds: 30);

  OpsSettings? _cached;
  DateTime? _cachedAt;
  StreamSubscription<Object?>? _changes;

  @override
  String get name => 'ops';

  @override
  List<Migration> get migrations => const [
    Migration(1, 'ops_baseline', _baseline),
  ];

  static String _baseline(String s) =>
      '''
CREATE TABLE $s.settings (
  key text PRIMARY KEY,
  value text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
''';

  @override
  void routes(RouteRegistry routes) {
    routes
      ..add(name, Routes.live, _live, rateLimit: _probe)
      ..add(name, Routes.ready, _ready, rateLimit: _probe)
      ..add(name, Routes.serverInfo, _serverInfo, rateLimit: _probe)
      ..add(name, Routes.legal, _legal, rateLimit: _probe)
      ..add(
        name,
        Routes.crashReport,
        _crash,
        rateLimit: _crashLimit,
        maxBodyBytes: 96 * 1024,
      )
      ..add(
        name,
        Routes.anomalies,
        _anomaliesIn,
        rateLimit: _anomalyLimit,
        maxBodyBytes: 512 * 1024,
      )
      ..add(name, Routes.metrics, _metrics, extraBearer: _metricsBearer)
      ..add(name, Routes.assetLinks, _assetLinks, rateLimit: _probe)
      ..add(
        name,
        Routes.openLink,
        _openLink,
        rateLimit: _probe,
        // The Android link filter matches `/open` and `/open/` only.
        trailingSlash: true,
      )
      ..add(
        name,
        Routes.shareLink,
        _shareLink,
        rateLimit: _probe,
        // A trailing slash is the same page: the name is what the browser
        // already has, and nothing below one more segment is this route.
        trailingSlash: true,
      )
      ..add(name, Routes.packs, _packList, rateLimit: _packListLimit)
      ..add(
        name,
        Routes.packManifest,
        _packManifest,
        rateLimit: _packManifestLimit,
      )
      ..add(name, Routes.packFile, _packFile, rateLimit: _packFileLimit);
  }

  @override
  Future<void> start() async {
    _changes = context.bus.subscribe(_changedTopic).listen((_) {
      _cached = null;
    });
    // Changes announced while the bus was down were missed.
    _resync = context.bus.subscribe(EventBus.resyncTopic).listen((_) {
      _cached = null;
    });
  }

  StreamSubscription<Object?>? _resync;

  @override
  Future<void> stop() async {
    await _changes?.cancel();
    await _resync?.cancel();
  }

  @override
  Future<bool> maintenanceActive() async => (await _settings()).maintenance;

  // ---------------------------------------------------------------- settings

  Future<OpsSettings> _settings() async {
    final now = context.clock.now();
    final cached = _cached;
    if (cached != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _cacheLifetime) {
      return cached;
    }
    final rows = await context.db.query(
      'SELECT key, value FROM $schema.settings',
    );
    final stored = {for (final r in rows) r.string('key'): r.string('value')};
    final settings = OpsSettings(
      serverName: stored['server_name'] ?? context.config.serverName,
      maintenance: stored['maintenance'] == 'true',
      federationEnabled: switch (stored['federation_enabled']) {
        'true' => true,
        'false' => false,
        _ => _federationDefault,
      },
      flags: {
        for (final e in OpsApi.knownFlags.entries)
          e.key: switch (stored['flag.${e.key}']) {
            'true' => true,
            'false' => false,
            _ => e.value,
          },
      },
    );
    _cached = settings;
    _cachedAt = now;
    return settings;
  }

  Future<void> _put(Tx tx, String key, String value) async {
    await tx.execute(
      'INSERT INTO $schema.settings (key, value) VALUES (@k:text, @v:text) '
      'ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()',
      {'k': key, 'v': value},
    );
    tx.afterCommit(() async {
      _cached = null;
      await context.bus.publish(_changedTopic, {'key': key});
    });
  }

  // ------------------------------------------------------------------ routes

  Future<Response> _live(HelixRequest request) async =>
      jsonResponse(LiveResponse(time: context.clock.now()).toJson());

  Future<Response> _ready(HelixRequest request) async {
    final checks = await context.health.run();
    final ready = checks.values.every((ok) => ok);
    return jsonResponse(
      ReadyResponse(ready: ready, checks: checks).toJson(),
      status: ready ? 200 : 503,
    );
  }

  String get _termsVersion {
    final configured = context.config.env['HELIX_TERMS_VERSION']?.trim();
    return configured == null || configured.isEmpty
        ? HelixLegalDocuments.termsVersion
        : configured;
  }

  Future<Response> _serverInfo(HelixRequest request) async {
    final settings = await _settings();
    return jsonResponse(
      ServerInfo(
        name: settings.serverName,
        version: helixServerVersion,
        registration: context.config.globalMode
            ? RegistrationMode.phone
            : RegistrationMode.invite,
        maxAttachmentBytes: context.config.maxAttachmentBytes,
        termsVersion: _termsVersion,
        privacyVersion: HelixLegalDocuments.privacyVersion,
        federationDomain: settings.federationEnabled
            ? context.config.publicBaseUrl.host
            : null,
        features: settings.flags,
      ).toJson(),
    );
  }

  Future<Response> _legal(HelixRequest request) async => jsonResponse(
    LegalDocuments(
      termsVersion: _termsVersion,
      termsTitle: HelixLegalDocuments.termsTitle,
      terms: HelixLegalDocuments.termsOfService,
      privacyVersion: HelixLegalDocuments.privacyVersion,
      privacyTitle: HelixLegalDocuments.privacyTitle,
      privacy: HelixLegalDocuments.privacyPolicy,
    ).toJson(),
  );

  // ------------------------------------------------------------- theme packs
  // Three read-only routes over one folder the operator owns. Nothing here
  // opens a manifest: the pack format is understood in exactly one place,
  // `checkOrbitPack` in `helix_remote_domain`, and that runs on a device, on
  // bytes this server has no say about (ADR-033). So a hacked or broken host
  // can withhold a pack or serve an older one, and nothing it says here is a
  // fact a device acts on.

  /// `GET /v1/packs`: what the folder holds - names, sizes and a time, and no
  /// display name. A name from this list would be unsigned, and the pack's own
  /// signed theme document already carries the one a person reads.
  Future<Response> _packList(HelixRequest request) async => jsonResponse(
    OrbitPackList(
      packs: [
        for (final pack in await _packs.list())
          OrbitPackEntry(
            id: pack.id,
            revision: pack.revision,
            manifestBytes: pack.manifestBytes,
            totalBytes: pack.totalBytes,
            updatedAt: pack.updatedAt,
          ),
      ],
    ).toJson(),
  );

  /// The manifest, as published and as signed: the bytes are handed over
  /// unchanged, so the device hashes exactly what the signature covers.
  Future<Response> _packManifest(HelixRequest request) async => _servePack(
    await _packs.manifest(
      request.param('pack_id'),
      _requestedRevision(request),
    ),
    contentType: 'application/json',
  );

  /// One file of a pack, by the SHA-256 the manifest names for it.
  Future<Response> _packFile(HelixRequest request) async => _servePack(
    await _packs.file(
      request.param('pack_id'),
      _requestedRevision(request),
      request.param('digest'),
    ),
    contentType: 'application/octet-stream',
  );

  /// A revision is a number in the URL and an `r<number>` folder on disk.
  /// Anything that is not a number is 0, which no folder can be, so it joins
  /// every other missing pack as one plain 404.
  static int _requestedRevision(HelixRequest request) =>
      int.tryParse(request.param('revision')) ?? 0;

  Future<Response> _servePack(
    PackRead read, {
    required String contentType,
  }) async {
    switch (read) {
      case PackHit(:final length, :final open):
        return Response(
          200,
          body: open(),
          headers: {'content-type': contentType, 'content-length': '$length'},
        );
      case PackMiss():
        throw const ApiError(ErrorCode.notFound, message: 'no such pack');
      case PackTooBig(:final length, :final cap):
        // On the operator's disk, but past what the format can describe, so
        // this is their mistake to see rather than a page that quietly fails.
        throw ApiError(
          ErrorCode.payloadTooLarge,
          message: 'this pack file is $length bytes, over the $cap cap',
        );
    }
  }

  /// Opt-in crash reports become one redacted log line; nothing is stored.
  Future<Response> _crash(HelixRequest request) async {
    if (!(await _settings()).flags['crash_reporting_upload']!) {
      throw const ApiError(
        ErrorCode.forbidden,
        message: 'Crash reporting is turned off on this server.',
      );
    }
    final report = request.json(CrashReport.fromJson);
    if (report.name.length > 120 ||
        report.fields.length > CrashReport.maxFields) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'fields'},
      );
    }
    _crashes.inc();
    log.warn('client_crash', {
      'name': report.name,
      'device_id': request.device.deviceId,
      'fields': {
        for (final e in report.fields.entries)
          if (RegExp(r'^[a-z][a-z0-9_]{0,40}$').hasMatch(e.key))
            e.key: e.value.length > CrashReport.maxValueLength
                ? e.value.substring(0, CrashReport.maxValueLength)
                : e.value,
      },
    });
    return noContent();
  }

  /// The apps' anomaly logs: each entry becomes one redacted `client_anomaly`
  /// warning in the server's log (the console, the log file and the admin
  /// console's live view); nothing is stored. Every build sends them, with no
  /// opt-in and no flag (the owner's decision, 2026-10-21).
  Future<Response> _anomaliesIn(HelixRequest request) async {
    final report = request.json(AnomalyReport.fromJson);
    if (report.entries.length > AnomalyReport.maxEntries) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'entries'},
      );
    }
    String cap(String value, int max) =>
        value.length > max ? '${value.substring(0, max)}…' : value;
    final key = RegExp(r'^[a-z][a-z0-9_]{0,40}$');
    for (final e in report.entries) {
      _anomalies.inc();
      log.warn('client_anomaly', {
        'kind': cap(e.kind, 20),
        'where': cap(e.where, 200),
        'device_id': request.device.deviceId,
        'app_version': cap(report.appVersion, 40),
        'platform': cap(report.platform, 20),
        'debug': report.debug,
        'at': e.at.toUtc().toIso8601String(),
        if (e.message.isNotEmpty)
          'message': cap(e.message, Anomaly.maxMessageLength),
        if (e.stack.isNotEmpty) 'stack': cap(e.stack, Anomaly.maxStackLength),
        if (e.fields.isNotEmpty)
          'fields': {
            for (final f in e.fields.entries.take(Anomaly.maxFields))
              if (key.hasMatch(f.key)) f.key: cap(f.value, 500),
          },
      });
    }
    return noContent();
  }

  /// `HELIX_METRICS_TOKEN` opens the metrics route (and nothing else) for a
  /// scraper; compared in constant time.
  Future<Principal?> _metricsBearer(String token) async {
    final expected = _metricsToken;
    if (expected == null) return null;
    return constantTimeEquals(utf8.encode(token), expected)
        ? const AdminPrincipal(adminId: 'metrics-token')
        : null;
  }

  Future<Response> _metrics(HelixRequest request) async {
    await context.metrics.collect();
    return Response.ok(
      api.renderMetrics(),
      headers: {'content-type': 'text/plain; version=0.0.4; charset=utf-8'},
    );
  }

  /// Android App Links (`HELIX_ANDROID_CERT_SHA256`, comma-separated
  /// `AB:CD:…` fingerprints of the app's signing certificates).
  Future<Response> _assetLinks(HelixRequest request) async {
    final fingerprints = (context.config.env['HELIX_ANDROID_CERT_SHA256'] ?? '')
        .split(',')
        .map((f) => f.trim().toUpperCase())
        .where((f) => RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$').hasMatch(f))
        .toList();
    return Response.ok(
      jsonEncode([
        if (fingerprints.isNotEmpty)
          {
            'relation': ['delegate_permission/common.handle_all_urls'],
            'target': {
              'namespace': 'android_app',
              'package_name': androidPackage,
              'sha256_cert_fingerprints': fingerprints,
            },
          },
      ]),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _openLink(HelixRequest request) async =>
      _landingPage(openPageHtml);

  Future<Response> _shareLink(HelixRequest request) async =>
      _landingPage(sharePageHtml);

  /// One of the two pages a browser opens straight from a shared link. They
  /// carry a one-tap action on a code, so they must not be framed
  /// (clickjacking): `frame-ancestors` is the modern control and
  /// `x-frame-options` covers old browsers.
  Response _landingPage(String html) => Response.ok(
    html,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'content-security-policy':
          "default-src 'none'; style-src 'unsafe-inline'; "
          "script-src 'unsafe-inline'; frame-ancestors 'none'; "
          "base-uri 'none'; form-action 'none'",
      'x-frame-options': 'DENY',
    },
  );
}

final class _OpsFacade implements OpsApi {
  _OpsFacade(this._m);

  final OpsModule _m;

  @override
  Future<OpsSettings> settings() => _m._settings();

  @override
  Future<bool> flag(String name) async {
    final value = (await _m._settings()).flags[name];
    if (value == null) throw ArgumentError.value(name, 'name', 'unknown flag');
    return value;
  }

  @override
  Future<OpsSettings> update(Tx tx, AdminConfigPatch patch) async {
    final name = patch.serverName?.trim();
    if (name != null) {
      if (name.isEmpty || name.length > AdminConfigPatch.maxServerNameLength) {
        throw const ApiError(
          ErrorCode.invalidField,
          details: {'field': 'server_name'},
        );
      }
      await _m._put(tx, 'server_name', name);
    }
    if (patch.maintenance != null) {
      await _m._put(tx, 'maintenance', '${patch.maintenance}');
    }
    if (patch.federationEnabled != null) {
      await _m._put(tx, 'federation_enabled', '${patch.federationEnabled}');
    }
    final current = await _m._settings();
    return OpsSettings(
      serverName: name ?? current.serverName,
      maintenance: patch.maintenance ?? current.maintenance,
      federationEnabled: patch.federationEnabled ?? current.federationEnabled,
      flags: current.flags,
    );
  }

  @override
  Future<void> setFlag(Tx tx, String name, bool enabled) async {
    if (!OpsApi.knownFlags.containsKey(name)) {
      throw ArgumentError.value(name, 'name', 'unknown flag');
    }
    await _m._put(tx, 'flag.$name', '$enabled');
  }

  @override
  String renderMetrics() => _m.context.metrics.render();
}
