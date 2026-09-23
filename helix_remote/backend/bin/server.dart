// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/env_sanitize.dart';
import 'package:helix_remote_backend/src/fcm_access_token.dart';
import 'package:helix_remote_backend/src/push_provider.dart';
import 'package:helix_remote_backend/src/server_impl.dart';
import 'package:helix_remote_backend/src/server_log.dart';
import 'package:helix_remote_backend/src/sms_provider.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'package:helix_remote_backend/src/startup_env.dart';
import 'src/admin_token_file.dart';
import 'src/terminal_qr.dart';

void main() async {
  // Everything the server prints is captured here so the admin console's
  // Logs screen has a source. The sink still forwards each line to
  // stdout/stderr, so `docker compose logs` is unaffected.
  final logSink = ServerLogSink(
    filePath: Platform.environment['HELIX_REMOTE_LOG_FILE'],
  );
  installServerLog(logSink);

  // Zone-overriding `print` is what catches the ~30 existing print() calls
  // (startup banner, admin token, shutdown notices) without rewriting every
  // one of them. stderr has no equivalent hook, which is why library code
  // calls logServerError() directly instead.
  await runZonedGuarded(
    () => _run(logSink),
    (error, stack) {
      logSink.error('Unhandled error: $error\n$stack');
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => logSink.info(line),
    ),
  );
}

Future<void> _run(ServerLogSink logSink) async {
  // On Windows without cmake/MSVC, native assets can't compile sqlite3 from
  // source. Pre-loading the DLL puts its symbols into the process so the
  // @Native fallback resolver finds them via DynamicLibrary.process().
  if (Platform.isWindows) {
    DynamicLibrary.open('sqlite3.dll');
  }
  final port =
      int.tryParse(Platform.environment['HELIX_REMOTE_PORT'] ?? '') ?? 8080;
  final host = Platform.environment['HELIX_REMOTE_HOST'] ?? '127.0.0.1';
  final devMode = Platform.environment['HELIX_REMOTE_DEV_MODE'] == '1';
  final topology =
      Platform.environment['HELIX_REMOTE_DEPLOYMENT_TOPOLOGY'] ?? 'single_host';
  final configuredWorkers = int.tryParse(
    Platform.environment['HELIX_REMOTE_BACKEND_WORKERS'] ?? '1',
  );
  if (!devMode &&
      (topology != 'single_host' ||
          configuredWorkers == null ||
          configuredWorkers < 1 ||
          configuredWorkers > 4)) {
    logServerError(
      'FATAL: SQLite production baseline requires '
      'HELIX_REMOTE_DEPLOYMENT_TOPOLOGY=single_host and '
      'HELIX_REMOTE_BACKEND_WORKERS in 1..4. Use the Postgres migration '
      'path before deploying beyond this ceiling.',
    );
    exit(1);
  }

  // One aggregated pass over every required/conditional env var, so a
  // misconfigured deploy sees every problem at once instead of restarting
  // once per fixed variable. See startup_env.dart for the requirement list.
  final envResult = validateStartupEnv(Platform.environment, devMode: devMode);
  for (final warning in envResult.warnings) {
    logServerWarning('WARNING: $warning');
  }
  if (envResult.isFatal) {
    logServerError('FATAL: invalid startup environment configuration:');
    for (final error in envResult.fatalErrors) {
      logServerError('  - $error');
    }
    exit(1);
  }

  // Deliberately not sanitized like the SMS vars below: this value is only
  // ever compared against itself (sign then verify), never against an
  // external system, so quotes/CRLF artifacts can't cause a mismatch bug -
  // and trimming them here would flip the effective signing key on any
  // existing deployment whose .env happens to quote it, invalidating every
  // live session on deploy. validateStartupEnv sanitizes only to decide
  // whether the value is present/long enough, not to change what's used.
  final resolvedJwtSecret = Platform.environment['HELIX_REMOTE_JWT_SECRET']!;
  final jwtKeyRing = _readJwtKeyRing(Platform.environment);
  final jwtSigningKeyId = Platform.environment['HELIX_REMOTE_JWT_ACTIVE_KID'];
  final dbPath =
      Platform.environment['HELIX_REMOTE_DB_PATH'] ?? 'remote_backend.db';

  // Attachment limits. Optional: both fall back to AttachmentsModule's
  // defaults. Configurable so an operator can change what this deployment
  // accepts by editing .env, rather than needing an app release - the
  // client reads the effective values from /api/v1/server/info.
  final maxAttachmentBytes = int.tryParse(
    sanitizeEnvValue(Platform.environment['HELIX_REMOTE_MAX_ATTACHMENT_BYTES']),
  );
  final accountQuotaBytes = int.tryParse(
    sanitizeEnvValue(Platform.environment['HELIX_REMOTE_ACCOUNT_QUOTA_BYTES']),
  );

  // How long a completed attachment nothing references is kept before the
  // storage sweep reclaims it. Exposed because the right answer depends on
  // the volume the deployment sits on, and a small VPS holding 100 MB files
  // may want far less than the 30-day default.
  final attachmentRetentionDays = int.tryParse(
    sanitizeEnvValue(
      Platform.environment['HELIX_REMOTE_ATTACHMENT_RETENTION_DAYS'],
    ),
  );

  // Attachment storage directory — optional but required for file transfers.
  final attachmentsDirPath =
      Platform.environment['HELIX_REMOTE_ATTACHMENTS_DIR'];
  Directory? attachmentsStorageDir;
  if (attachmentsDirPath != null && attachmentsDirPath.isNotEmpty) {
    final dir = Directory(attachmentsDirPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    attachmentsStorageDir = dir;
    print('Attachment storage: $attachmentsDirPath');
  } else if (!devMode) {
    logServerWarning(
      'WARNING: HELIX_REMOTE_ATTACHMENTS_DIR is not set. '
      'File attachment upload and download will be unavailable.',
    );
  }

  // TURN credentials — validated as a pair by validateStartupEnv above;
  // both empty here just means the feature is off.
  final turnUrl = Platform.environment['HELIX_REMOTE_TURN_URL'] ?? '';
  final turnSecret = Platform.environment['HELIX_REMOTE_TURN_SECRET'] ?? '';

  // FCM push provider — validated by validateStartupEnv above, which has
  // already refused to start if the project ID is set without a credential.
  final fcmProjectId =
      Platform.environment['HELIX_REMOTE_FCM_PROJECT_ID'] ?? '';
  final fcmServiceAccount =
      Platform.environment['HELIX_REMOTE_FCM_SERVICE_ACCOUNT'] ?? '';
  final fcmAccessToken =
      Platform.environment['HELIX_REMOTE_FCM_ACCESS_TOKEN'] ?? '';

  // Parsed before the server starts listening. A malformed or missing key
  // file is a deploy mistake, and the only cheap moment to report it is now
  // — the alternative is a stack trace on the first missed call, hours
  // later, in whatever log nobody is tailing.
  final serviceAccountJson = readFcmServiceAccount(fcmServiceAccount);

  final PushProvider pushProvider;
  if (fcmProjectId.isEmpty) {
    pushProvider = const NoopPushProvider();
  } else if (serviceAccountJson != null) {
    pushProvider = FcmPushProvider(
      projectId: fcmProjectId,
      tokenSource: ServiceAccountFcmAccessToken(
        serviceAccountJson: serviceAccountJson,
      ),
    );
    print('FCM push configured for project: $fcmProjectId (service account)');
  } else {
    pushProvider = FcmPushProvider.staticToken(
      projectId: fcmProjectId,
      accessToken: fcmAccessToken,
    );
    print(
      'FCM push configured for project: $fcmProjectId using a static access '
      'token. Google expires these after an hour and this server cannot '
      'renew one — set HELIX_REMOTE_FCM_SERVICE_ACCOUNT for a deployment.',
    );
  }

  // Bulk SMS (BulkSMSBD) — validated as a pair by validateStartupEnv above.
  // Without it, phone verification falls back to returning the code
  // directly in the API response (see AuthPhoneOtpHandlers) - fine for
  // local dev, not for a real deployment.
  final smsApiKey = sanitizeEnvValue(
    Platform.environment['HELIX_REMOTE_SMS_API_KEY'],
  );
  final smsSenderId = sanitizeEnvValue(
    Platform.environment['HELIX_REMOTE_SMS_SENDER_ID'],
  );
  final SmsProvider smsProvider;
  if (smsApiKey.isNotEmpty && smsSenderId.isNotEmpty) {
    smsProvider = BulkSmsBdProvider(apiKey: smsApiKey, senderId: smsSenderId);
    print('SMS delivery configured via BulkSMSBD, sender ID: $smsSenderId');
  } else {
    smsProvider = const NoopSmsProvider();
  }

  print('Starting Helix Remote backend database at: $dbPath');
  final sqliteDb = sqlite3.open(dbPath);
  sqliteDb.execute('PRAGMA journal_mode = WAL;');
  sqliteDb.execute('PRAGMA busy_timeout = 5000;');
  sqliteDb.execute('PRAGMA synchronous = NORMAL;');

  print('Initializing server configuration...');
  final server = BackendServer.create(
    sqliteDb: sqliteDb,
    jwtSecret: resolvedJwtSecret,
    jwtKeyRing: jwtKeyRing,
    jwtSigningKeyId: jwtSigningKeyId,
    attachmentsStorageDir: attachmentsStorageDir,
    maxAttachmentBytes: maxAttachmentBytes,
    accountQuotaBytes: accountQuotaBytes,
    attachmentRetention: attachmentRetentionDays == null
        ? null
        : Duration(days: attachmentRetentionDays),
    turnUrl: turnUrl,
    turnSecret: turnSecret,
    pushProvider: pushProvider,
    smsProvider: smsProvider,
  );

  // Refuse to serve a database that already contains an account holding a
  // reserved id. Before registration validated this, `account_id` was
  // client-chosen and the operator gate was `account_id == 'admin'`, so such
  // a row is the fingerprint of a claimed-admin compromise. Migration 40
  // moves admin to a stored capability and no reserved id grants anything
  // anymore - but a server whose database carries that row has a history
  // worth looking at before it takes traffic, and failing loudly is the only
  // way an operator finds out.
  final reservedAccounts = server.db.findAccountsWithReservedIds();
  if (reservedAccounts.isNotEmpty) {
    stderr.writeln('==================================================');
    stderr.writeln('REFUSING TO START: reserved account id(s) present');
    stderr.writeln('');
    stderr.writeln('  ${reservedAccounts.join(', ')}');
    stderr.writeln('');
    stderr.writeln(
      'These ids are reserved and can no longer be registered. A row that '
      'holds one was created while the operator check was still "account_id '
      'equals admin", so treat it as a possible privilege-escalation '
      'compromise: audit the account\'s activity in the audit log before '
      'doing anything else.',
    );
    stderr.writeln('');
    stderr.writeln(
      'Once reviewed, rename or delete the row to start the server.',
    );
    stderr.writeln('==================================================');
    exit(1);
  }

  final identity = await ServerIdentity.loadOrCreate(server.db);
  server.serverIdentity = identity;
  final adminTokenOverride = Platform.environment['HELIX_REMOTE_ADMIN_TOKEN'];
  print('==================================================');
  print('Helix Server ID: ${identity.serverId}');
  if (adminTokenOverride != null && adminTokenOverride.isNotEmpty) {
    print(
      'Helix Admin Token: using HELIX_REMOTE_ADMIN_TOKEN from environment.',
    );
  } else if (identity.adminToken != null) {
    final adminTokenFile = writeAdminTokenFile(
      dbPath: dbPath,
      serverId: identity.serverId,
      adminToken: identity.adminToken!,
    );
    // Deliberately stdout.writeln and not print: print() is captured by
    // the zone into the log sink, which both keeps a copy in memory for the
    // admin console and appends it to HELIX_REMOTE_LOG_FILE. The admin
    // token must not end up in either - it already has a properly
    // permissioned home in ADMIN_TOKEN.txt. stdout has no zone hook, so
    // writing there puts it on the console (and in `docker compose logs`)
    // exactly as before without it being captured.
    stdout.writeln('Helix Admin Token (Generated on first boot):');
    stdout.writeln('  ${identity.adminToken}');
    print('Also saved to: ${adminTokenFile.path}');
    print('Save this token! It is required to log into Helix Admin.');
    try {
      stdout.writeln('');
      stdout.writeln('Scan with the Helix Admin app to fill in the token:');
      stdout.writeln(renderTerminalQr(identity.adminToken!));
    } catch (_) {
      // Cosmetic only - never let QR rendering block server startup.
    }
  } else {
    print(
      'Helix Admin Token: already configured from a previous boot. Check '
      'ADMIN_TOKEN.txt next to the database, or run '
      'bin/reset_admin_token.dart to mint a new one, or set '
      'HELIX_REMOTE_ADMIN_TOKEN to override it.',
    );
  }
  print('==================================================');

  print('Starting server on http://$host:$port...');
  await server.start(host, port);
  print('Helix Remote backend monolith is online.');

  var stopping = false;
  Future<void> stopForSignal(String name) async {
    if (stopping) return;
    stopping = true;
    print('Shutdown signal ($name) received. Disposing services...');
    await server.stop();
    print('Server cleanly shutdown.');
    // Flush buffered log lines before the process goes away, or the last
    // few writes (including this shutdown notice) never reach the file.
    await logSink.dispose();
    exit(0);
  }

  void watchSignal(ProcessSignal signal, String name) {
    if (Platform.isWindows && signal == ProcessSignal.sigterm) {
      print('Shutdown signal $name is not supported on this platform.');
      return;
    }
    try {
      signal.watch().listen((_) => stopForSignal(name));
    } on SignalException {
      print('Shutdown signal $name is not supported on this platform.');
    }
  }

  watchSignal(ProcessSignal.sigint, 'SIGINT');
  watchSignal(ProcessSignal.sigterm, 'SIGTERM');
}

/// Optional rotation configuration. The legacy single secret remains the
/// default, while a JSON object such as
/// `{\"2026-07\":\"old\",\"2026-08\":\"new\"}` lets a deployment accept
/// old and new sessions during the overlap. Secrets are intentionally read
/// unchanged: operators may use arbitrary high-entropy values.
Map<String, String>? _readJwtKeyRing(Map<String, String> environment) {
  final source = environment['HELIX_REMOTE_JWT_KEY_RING_JSON'];
  if (source == null || source.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw const FormatException('must be an object');
    final keyRing = <String, String>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String ||
          entry.value is! String ||
          (entry.key as String).trim().isEmpty ||
          (entry.value as String).isEmpty) {
        throw const FormatException(
          'keys and values must be non-empty strings',
        );
      }
      keyRing[entry.key as String] = entry.value as String;
    }
    final active = environment['HELIX_REMOTE_JWT_ACTIVE_KID'];
    if (keyRing.isEmpty || active == null || !keyRing.containsKey(active)) {
      throw const FormatException(
        'HELIX_REMOTE_JWT_ACTIVE_KID must name a key in the ring',
      );
    }
    return keyRing;
  } on FormatException catch (error) {
    throw ArgumentError('Invalid HELIX_REMOTE_JWT_KEY_RING_JSON: $error');
  }
}
