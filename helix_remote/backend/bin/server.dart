// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'package:sqlite3/sqlite3.dart';
import 'package:helix_remote_backend/src/push_provider.dart';
import 'package:helix_remote_backend/src/server_impl.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'src/admin_token_file.dart';

void main() async {
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
  final jwtSecret = Platform.environment['HELIX_REMOTE_JWT_SECRET'];
  if (jwtSecret == null || jwtSecret.isEmpty) {
    stderr.writeln('FATAL: HELIX_REMOTE_JWT_SECRET required');
    exit(1);
  }
  if (!devMode && jwtSecret.length < 32) {
    stderr.writeln(
      'HELIX_REMOTE_JWT_SECRET must be set to at least 32 bytes outside explicit HELIX_REMOTE_DEV_MODE=1.',
    );
    exit(78);
  }
  final resolvedJwtSecret = jwtSecret;
  final dbPath =
      Platform.environment['HELIX_REMOTE_DB_PATH'] ?? 'remote_backend.db';

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
    stderr.writeln(
      'WARNING: HELIX_REMOTE_ATTACHMENTS_DIR is not set. '
      'File attachment upload and download will be unavailable.',
    );
  }

  // TURN credentials — optional but required for relay-only WebRTC calls.
  final turnUrl = Platform.environment['HELIX_REMOTE_TURN_URL'] ?? '';
  final turnSecret = Platform.environment['HELIX_REMOTE_TURN_SECRET'] ?? '';
  if (!devMode && (turnUrl.isEmpty || turnSecret.isEmpty)) {
    stderr.writeln(
      'WARNING: HELIX_REMOTE_TURN_URL or HELIX_REMOTE_TURN_SECRET is not set. '
      'WebRTC calls in relay-only mode will fail to connect.',
    );
  }

  // FCM push provider — optional but required for push wake notifications.
  final fcmProjectId =
      Platform.environment['HELIX_REMOTE_FCM_PROJECT_ID'] ?? '';
  final fcmAccessToken =
      Platform.environment['HELIX_REMOTE_FCM_ACCESS_TOKEN'] ?? '';
  final PushProvider pushProvider;
  if (fcmProjectId.isNotEmpty && fcmAccessToken.isNotEmpty) {
    pushProvider = FcmPushProvider(
      projectId: fcmProjectId,
      accessToken: fcmAccessToken,
    );
    print('FCM push configured for project: $fcmProjectId');
  } else {
    pushProvider = const NoopPushProvider();
    if (!devMode) {
      stderr.writeln(
        'WARNING: HELIX_REMOTE_FCM_PROJECT_ID or HELIX_REMOTE_FCM_ACCESS_TOKEN '
        'not set. Push wake notifications are disabled.',
      );
    }
  }

  print('Starting Helix Remote backend database at: $dbPath');
  final sqliteDb = sqlite3.open(dbPath);

  print('Initializing server configuration...');
  final server = BackendServer.create(
    sqliteDb: sqliteDb,
    jwtSecret: resolvedJwtSecret,
    attachmentsStorageDir: attachmentsStorageDir,
    turnUrl: turnUrl,
    turnSecret: turnSecret,
    pushProvider: pushProvider,
  );

  final identity = await ServerIdentity.loadOrCreate(server.db);
  server.serverIdentity = identity;
  final adminTokenOverride = Platform.environment['HELIX_REMOTE_ADMIN_TOKEN'];
  print('==================================================');
  print('Helix Server ID: ${identity.serverId}');
  if (adminTokenOverride != null && adminTokenOverride.isNotEmpty) {
    print('Helix Admin Token: using HELIX_REMOTE_ADMIN_TOKEN from environment.');
  } else if (identity.adminToken != null) {
    final adminTokenFile = writeAdminTokenFile(
      dbPath: dbPath,
      serverId: identity.serverId,
      adminToken: identity.adminToken!,
    );
    print('Helix Admin Token (Generated on first boot):');
    print('  ${identity.adminToken}');
    print('Also saved to: ${adminTokenFile.path}');
    print('Save this token! It is required to log into Helix Admin.');
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
