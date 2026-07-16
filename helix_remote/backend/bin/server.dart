// ignore_for_file: avoid_print
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:helix_remote_backend/src/push_provider.dart';
import 'package:helix_remote_backend/src/server_impl.dart';

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
  if (!devMode && (jwtSecret == null || jwtSecret.length < 32)) {
    stderr.writeln(
      'HELIX_REMOTE_JWT_SECRET must be set to at least 32 bytes outside explicit HELIX_REMOTE_DEV_MODE=1.',
    );
    exit(78);
  }
  final resolvedJwtSecret =
      jwtSecret ?? 'helix_remote_explicit_dev_mode_secret_min_32_bytes';
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
