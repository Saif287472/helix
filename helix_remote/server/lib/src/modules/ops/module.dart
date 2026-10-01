import 'dart:async';
import 'dart:convert';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/ops/api.dart';
import 'package:helix_remote_server/src/kernel/crypto.dart';
import 'package:helix_remote_server/src/modules/ops/open_page.dart';
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

/// Health, server info, legal documents, crash telemetry, metrics, app
/// links, and the operator settings behind them: server name, maintenance
/// mode, federation switch and feature flags. Schema `ops`.
final class OpsModule extends ModuleBase implements ProvidesMaintenance {
  OpsModule(super.context) {
    api = _OpsFacade(this);
    _crashes = context.metrics.counter(
      'helix_client_crash_reports_total',
      'Opt-in crash reports received',
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
      ..add(name, Routes.metrics, _metrics, extraBearer: _metricsBearer)
      ..add(name, Routes.assetLinks, _assetLinks, rateLimit: _probe)
      ..add(name, Routes.openLink, _openLink, rateLimit: _probe);
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

  Future<Response> _openLink(HelixRequest request) async => Response.ok(
    openPageHtml,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'content-security-policy':
          "default-src 'none'; style-src 'unsafe-inline'; "
          "script-src 'unsafe-inline'",
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
