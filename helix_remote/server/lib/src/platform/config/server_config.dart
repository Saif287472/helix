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
    required this.schemaPrefix,
    required this.logFile,
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

  /// Peers whose `X-Forwarded-For`/`X-Real-IP` headers are believed (Caddy).
  final Set<String> trustedProxies;

  /// Schema prefix for tests (empty in production).
  final String schemaPrefix;
  final String? logFile;

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
      final v = read(name)?.toLowerCase();
      if (v == null) return orElse;
      if (const {'1', 'true', 'yes'}.contains(v)) return true;
      if (const {'0', 'false', 'no'}.contains(v)) return false;
      problems.add('$name must be true or false');
      return orElse;
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
        final endpoint = Uri.tryParse(require('HELIX_S3_ENDPOINT'));
        blobs = BlobConfig.s3(
          S3Config(
            endpoint: endpoint ?? Uri(),
            region: read('HELIX_S3_REGION') ?? 'us-east-1',
            bucket: require('HELIX_S3_BUCKET'),
            accessKeyId: require('HELIX_S3_ACCESS_KEY_ID'),
            secretAccessKey: require('HELIX_S3_SECRET_ACCESS_KEY'),
            pathStyle: flag('HELIX_S3_PATH_STYLE', orElse: true),
          ),
        );
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
      globalMode: flag('HELIX_GLOBAL_MODE'),
      serverName: read('HELIX_SERVER_NAME') ?? 'Helix',
      jwtKeys: Map.unmodifiable(jwtKeys),
      activeJwtKid: activeKid,
      blobs: blobs,
      maxAttachmentBytes: integer(
        'HELIX_MAX_ATTACHMENT_BYTES',
        100 * 1024 * 1024,
        min: 1024,
      ),
      trustedProxies: {
        ...(read('HELIX_TRUSTED_PROXIES') ?? '127.0.0.1,::1')
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty),
      },
      schemaPrefix: prefix,
      logFile: read('HELIX_LOG_FILE'),
    );
  }

  @override
  String toString() =>
      'ServerConfig(host: $host, port: $port, base: $publicBaseUrl, '
      'node: $nodeId, topology: ${topology.name}, global: $globalMode, '
      'blobs: ${blobs.backend.name}, secrets redacted)';
}
