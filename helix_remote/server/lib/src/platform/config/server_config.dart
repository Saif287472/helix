import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';

enum Topology { singleHost, cluster }

enum BlobBackend { local, s3 }

/// Object storage settings. S3 means any S3-compatible store (MinIO, R2,
/// AWS) addressed with SigV4.
final class BlobConfig {
  const BlobConfig.local(this.directory)
    : backend = BlobBackend.local,
      s3 = null;

  const BlobConfig.s3(this.s3) : backend = BlobBackend.s3, directory = null;

  final BlobBackend backend;
  final String? directory;
  final S3Config? s3;
}

final class S3Config {
  const S3Config({
    required this.endpoint,
    required this.region,
    required this.bucket,
    required this.accessKeyId,
    required this.secretAccessKey,
    this.pathStyle = true,
  });

  final Uri endpoint;
  final String region;
  final String bucket;
  final String accessKeyId;
  final String secretAccessKey;
  final bool pathStyle;

  @override
  String toString() => 'S3Config($endpoint, $region, $bucket, keys redacted)';
}

/// Invalid or missing configuration. Lists variable *names* only.
final class ConfigError extends Error {
  ConfigError(this.problems);

  final List<String> problems;

  @override
  String toString() => 'Invalid configuration:\n  ${problems.join('\n  ')}';
}

/// The one boolean syntax of every `HELIX_*` switch, core and module alike:
/// `1/true/yes` or `0/false/no` (any case). Unset or empty is null; anything
/// else is a [FormatException].
bool? parseEnvFlag(String? raw) {
  final v = raw?.trim().toLowerCase();
  if (v == null || v.isEmpty) return null;
  if (const {'1', 'true', 'yes'}.contains(v)) return true;
  if (const {'0', 'false', 'no'}.contains(v)) return false;
  throw FormatException('not a boolean', raw);
}

/// [parseEnvFlag] for module config sections: [orElse] when unset, a
/// [ConfigError] naming [name] when malformed.
bool envFlag(Map<String, String> env, String name, {bool orElse = false}) {
  try {
    return parseEnvFlag(env[name]) ?? orElse;
  } on FormatException {
    throw ConfigError(['$name must be true or false']);
  }
}

/// All platform settings, read once from the environment (`HELIX_*`).
/// Modules read their own sections (SMS, push, TURN) from [env] in their
/// own config classes, so this file does not grow with every feature.
///
/// Secrets live only here and in the module configs; `toString` never
/// prints them. Operators edit `server/.env` themselves; agents never do.
final class ServerConfig {
  ServerConfig._({
    required this.env,
    required this.databaseUrl,
    required this.host,
    required this.port,
    required this.publicBaseUrl,
    required this.nodeId,
    required this.topology,
    required this.devMode,
    required this.globalMode,
    required this.serverName,
    required this.jwtKeys,
    required this.activeJwtKid,
    required this.blobs,
    required this.maxAttachmentBytes,
    required this.trustedProxies,
    required this.trustRealIp,
    required this.schemaPrefix,
    required this.logFile,
    required this.logKeepDays,
    required this.dbPoolSize,
    required this.maxInFlightBodyBytes,
    required this.metricsToken,
    required this.storageBudgetBytes,
    this.packsDirectory,
  });

  /// The raw environment, for module config sections.
  final Map<String, String> env;
  final String databaseUrl;
  final String host;
  final int port;
  final Uri publicBaseUrl;

  /// Unique per running process; used for job leases and socket routes.
  final String nodeId;
  final Topology topology;
  final bool devMode;

  /// Helix Global (phone sign-up) rather than a personal server (invites).
  final bool globalMode;
  final String serverName;

  /// JWT signing keys by key id. Tokens carry `kid`; old keys keep
  /// verifying until removed, so keys rotate without signing anyone out.
  final Map<String, Uint8List> jwtKeys;
  final String activeJwtKid;
  final BlobConfig blobs;
  final int maxAttachmentBytes;

  /// `HELIX_PACKS_DIR`: the folder of signed theme packs this server hosts,
  /// read-only (ADR-033). Unset means no packs: `GET /v1/packs` answers an
  /// empty list and every pack file is a 404, which is a working server with
  /// nothing to offer, not a broken one. The folder is the operator's, written
  /// by `tool/theme_pack_tool.dart publish`; the server never parses what is
  /// in it, and a device checks every byte against the pack's own signature.
  final String? packsDirectory;

  /// Peers whose `X-Forwarded-For` header is believed (Caddy). The client
  /// is the rightmost hop that is not one of them.
  final Set<String> trustedProxies;

  /// `HELIX_TRUST_X_REAL_IP`: also believe `X-Real-IP` from a trusted
  /// proxy (only when that proxy always overwrites it). Off by default.
  final bool trustRealIp;

  /// Schema prefix for tests (empty in production).
  final String schemaPrefix;

  /// `HELIX_LOG_FILE`: log lines are also appended to this file.
  final String? logFile;

  /// `HELIX_LOG_KEEP_DAYS`: how many days of rotated log files to keep
  /// (1 to 3650, default 14). The file rotates at midnight UTC.
  final int logKeepDays;

  /// `HELIX_DB_POOL_SIZE`: connections in the main Postgres pool (the
  /// ephemeral store and the bus `LISTEN` have their own).
  final int dbPoolSize;

  /// `HELIX_MAX_INFLIGHT_BODY_BYTES`: request body bytes this node buffers
  /// at once across all requests; over it requests get `unavailable`.
  final int maxInFlightBodyBytes;

  /// `HELIX_METRICS_TOKEN`: a bearer token that opens `GET /v1/ops/metrics`
  /// only (for a Prometheus scraper). Unset: an admin token is needed.
  final String? metricsToken;

  /// `HELIX_STORAGE_BUDGET_BYTES`: the most the database and the stored
  /// media together may hold. Over it, uploads and large sends get
  /// `quota_exceeded` (`StorageBudget`). Unset: no server-wide limit.
  final int? storageBudgetBytes;

  static ServerConfig fromEnv(Map<String, String> env) {
    final problems = <String>[];
    String? read(String name) {
      final v = env[name]?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    String require(String name) {
      final v = read(name);
      if (v == null) problems.add('$name is required');
      return v ?? '';
    }

    bool flag(String name, {bool orElse = false}) {
      try {
        return parseEnvFlag(env[name]) ?? orElse;
      } on FormatException {
        problems.add('$name must be true or false');
        return orElse;
      }
    }

    int integer(String name, int orElse, {int min = 0, int? max}) {
      final v = read(name);
      if (v == null) return orElse;
      final parsed = int.tryParse(v);
      if (parsed == null || parsed < min || (max != null && parsed > max)) {
        problems.add('$name must be an integer in range');
        return orElse;
      }
      return parsed;
    }

    final devMode = flag('HELIX_DEV_MODE');
    final databaseUrl = require('HELIX_DATABASE_URL');
    final port = integer('HELIX_PORT', 8080, min: 0, max: 65535);
    final host = read('HELIX_HOST') ?? '127.0.0.1';
    final base = Uri.tryParse(
      read('HELIX_PUBLIC_BASE_URL') ?? 'http://$host:$port',
    );
    if (base == null || !base.hasScheme || base.host.isEmpty) {
      problems.add('HELIX_PUBLIC_BASE_URL must be an absolute URL');
    }

    final topology = switch (read('HELIX_TOPOLOGY') ?? 'single_host') {
      'single_host' => Topology.singleHost,
      'cluster' => Topology.cluster,
      _ => () {
        problems.add('HELIX_TOPOLOGY must be single_host or cluster');
        return Topology.singleHost;
      }(),
    };

    final jwtKeys = <String, Uint8List>{};
    final rawKeys = read('HELIX_JWT_KEYS');
    if (rawKeys == null) {
      problems.add(
        'HELIX_JWT_KEYS is required (JSON object of key id to base64url secret)',
      );
    } else {
      try {
        final decoded = jsonDecode(rawKeys) as Map<String, Object?>;
        for (final e in decoded.entries) {
          final secret = decodeBytes(e.value! as String);
          if (secret.length < 32) {
            problems.add(
              'HELIX_JWT_KEYS key "${e.key}" must be at least 32 bytes',
            );
          }
          jwtKeys[e.key] = secret;
        }
      } on Object {
        problems.add(
          'HELIX_JWT_KEYS must be a JSON object of key id to base64url secret',
        );
      }
    }
    final activeKid =
        read('HELIX_JWT_ACTIVE_KID') ??
        (jwtKeys.length == 1 ? jwtKeys.keys.single : '');
    if (jwtKeys.isNotEmpty && !jwtKeys.containsKey(activeKid)) {
      problems.add('HELIX_JWT_ACTIVE_KID must name a key in HELIX_JWT_KEYS');
    }

    final BlobConfig blobs;
    switch (read('HELIX_BLOB_STORE') ?? 'local') {
      case 'local':
        blobs = BlobConfig.local(read('HELIX_BLOB_DIR') ?? 'helix_blobs');
      case 's3':
        // Read every value even when the endpoint is wrong: one start-up
        // names all the problems, not only the first.
        final rawEndpoint = require('HELIX_S3_ENDPOINT');
        final region = read('HELIX_S3_REGION') ?? 'us-east-1';
        final bucket = require('HELIX_S3_BUCKET');
        final accessKeyId = require('HELIX_S3_ACCESS_KEY_ID');
        final secretAccessKey = require('HELIX_S3_SECRET_ACCESS_KEY');
        final pathStyle = flag('HELIX_S3_PATH_STYLE', orElse: true);
        final endpoint = Uri.tryParse(rawEndpoint);
        // An endpoint that is not a full URL used to start the node and then
        // fail per request with an error that named nothing: every signed
        // request builds a relative URI. `minio:9000` parses as a scheme with
        // no host, `storage.example.com` as a path (AUD-1c-3).
        final usable =
            endpoint != null &&
            endpoint.hasAuthority &&
            (endpoint.scheme == 'http' || endpoint.scheme == 'https') &&
            endpoint.userInfo.isEmpty &&
            !endpoint.hasQuery &&
            !endpoint.hasFragment;
        if (!usable && rawEndpoint.isNotEmpty) {
          problems.add(
            'HELIX_S3_ENDPOINT must be http(s)://host[:port], with no '
            'credentials, query or fragment',
          );
        }
        // A refused endpoint never stores anything: the node stops on the
        // problem above, so this branch only keeps `blobs` a value.
        blobs = usable
            ? BlobConfig.s3(
                S3Config(
                  endpoint: endpoint,
                  region: region,
                  bucket: bucket,
                  accessKeyId: accessKeyId,
                  secretAccessKey: secretAccessKey,
                  pathStyle: pathStyle,
                ),
              )
            : const BlobConfig.local('helix_blobs');
      default:
        problems.add('HELIX_BLOB_STORE must be local or s3');
        blobs = const BlobConfig.local('helix_blobs');
    }

    if (topology == Topology.cluster &&
        blobs.backend == BlobBackend.local &&
        !devMode) {
      problems.add(
        'HELIX_TOPOLOGY=cluster needs shared object storage (HELIX_BLOB_STORE=s3)',
      );
    }

    final prefix = read('HELIX_SCHEMA_PREFIX') ?? '';
    if (prefix.isNotEmpty && !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(prefix)) {
      problems.add('HELIX_SCHEMA_PREFIX must be [a-z][a-z0-9_]*');
    }

    final metricsToken = read('HELIX_METRICS_TOKEN');
    if (metricsToken != null && metricsToken.length < 32) {
      problems.add('HELIX_METRICS_TOKEN must be at least 32 characters');
    }

    // Read before the check below, so every problem is reported at once.
    final globalMode = flag('HELIX_GLOBAL_MODE');
    final maxAttachmentBytes = integer(
      'HELIX_MAX_ATTACHMENT_BYTES',
      100 * 1024 * 1024,
      min: 1024,
    );
    final dbPoolSize = integer('HELIX_DB_POOL_SIZE', 10, min: 2, max: 200);
    final logKeepDays = integer('HELIX_LOG_KEEP_DAYS', 14, min: 1, max: 3650);
    final maxInFlightBodyBytes = integer(
      'HELIX_MAX_INFLIGHT_BODY_BYTES',
      256 * 1024 * 1024,
      min: 1024 * 1024,
    );
    final trustRealIp = flag('HELIX_TRUST_X_REAL_IP');

    // Unset, or set to nothing, means this server hosts no theme packs. A
    // path of only spaces would never resolve, so it is read as unset rather
    // than as a folder nobody can reach.
    final packsRaw = read('HELIX_PACKS_DIR')?.trim();
    final packsDirectory = packsRaw == null || packsRaw.isEmpty
        ? null
        : packsRaw;

    final storageBudgetRaw = read('HELIX_STORAGE_BUDGET_BYTES');
    final storageBudgetBytes = storageBudgetRaw == null
        ? null
        : int.tryParse(storageBudgetRaw);
    // Dev mode (tests) may set a tiny budget to see it refuse.
    if (storageBudgetRaw != null &&
        (storageBudgetBytes == null ||
            storageBudgetBytes < (devMode ? 1 : 1024 * 1024 * 1024))) {
      problems.add(
        'HELIX_STORAGE_BUDGET_BYTES must be a number of bytes, at least 1 GiB',
      );
    }

    if (problems.isNotEmpty) throw ConfigError(problems);

    return ServerConfig._(
      env: Map.unmodifiable(env),
      databaseUrl: databaseUrl,
      host: host,
      port: port,
      publicBaseUrl: base!,
      nodeId: read('HELIX_NODE_ID') ?? Uuid.v7(),
      topology: topology,
      devMode: devMode,
      globalMode: globalMode,
      serverName: read('HELIX_SERVER_NAME') ?? 'Helix',
      jwtKeys: Map.unmodifiable(jwtKeys),
      activeJwtKid: activeKid,
      blobs: blobs,
      maxAttachmentBytes: maxAttachmentBytes,
      packsDirectory: packsDirectory,
      trustedProxies: {
        ...(read('HELIX_TRUSTED_PROXIES') ?? '127.0.0.1,::1')
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty),
      },
      trustRealIp: trustRealIp,
      schemaPrefix: prefix,
      logFile: read('HELIX_LOG_FILE'),
      logKeepDays: logKeepDays,
      dbPoolSize: dbPoolSize,
      maxInFlightBodyBytes: maxInFlightBodyBytes,
      metricsToken: metricsToken,
      storageBudgetBytes: storageBudgetBytes,
    );
  }

  @override
  String toString() =>
      'ServerConfig(host: $host, port: $port, base: $publicBaseUrl, '
      'node: $nodeId, topology: ${topology.name}, global: $globalMode, '
      'blobs: ${blobs.backend.name}, secrets redacted)';
}
