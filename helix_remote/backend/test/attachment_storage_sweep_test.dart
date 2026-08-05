// The attachment storage sweep is actually scheduled.
//
// `cleanupOrphans` and `runLifecycleRules` have been covered by unit tests
// for a long time, but nothing outside those tests ever called them: a
// running deployment never reclaimed a single byte, and attachments
// accumulated on disk forever. These tests exercise the wiring rather than
// the rules — that starting the server sweeps, and stopping it stops.

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';

void main() {
  late Directory storageDir;
  late BackendServer server;

  void seedAccount() {
    server.db.createAccount('sweep_user', 'sweeper', 'sweep_identity_key');
    server.db.registerDevice(
      'sweep_device',
      'sweep_user',
      'sweep_device_key',
      'Sweep Device',
    );
  }

  setUp(() {
    storageDir = Directory.systemTemp.createTempSync('helix_sweep_test');
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_attachment_sweep',
      attachmentsStorageDir: storageDir,
    );
    seedAccount();
  });

  tearDown(() async {
    await server.stop();
    if (storageDir.existsSync()) {
      storageDir.deleteSync(recursive: true);
    }
  });

  /// Seeds an attachment old enough to be past every retention threshold,
  /// with a file on disk.
  File seedStale(String fileId, {required bool completed}) {
    final past = DateTime.now()
        .subtract(const Duration(days: 400))
        .millisecondsSinceEpoch;
    server.db.createAttachment(
      fileId: fileId,
      accountId: 'sweep_user',
      fileSize: 3,
      fileHash: fileId,
      createdAt: past,
    );
    if (completed) {
      server.db.updateAttachmentProgress(fileId, 3, 'COMPLETED');
    }
    final file = File('${storageDir.path}/$fileId');
    file.writeAsBytesSync([1, 2, 3]);
    return file;
  }

  test('starting the server reclaims abandoned uploads and unreferenced '
      'attachments', () async {
    final abandoned = seedStale('abandoned_upload', completed: false);
    final unreferenced = seedStale('unreferenced_file', completed: true);

    await server.start('127.0.0.1', 0);

    // startMaintenance sweeps immediately rather than waiting out the first
    // interval tick — a server restarted more often than the interval would
    // otherwise never sweep at all.
    expect(server.db.getAttachment('abandoned_upload'), isNull);
    expect(abandoned.existsSync(), isFalse);
    expect(server.db.getAttachment('unreferenced_file'), isNull);
    expect(unreferenced.existsSync(), isFalse);
  });

  test('the sweep leaves referenced and recent attachments alone', () async {
    final referenced = seedStale('referenced_file', completed: true);
    server.db.createConversation('sweep_conv', 'DIRECT', 'Test', [
      'sweep_user',
    ]);
    server.db.saveMessage(
      messageId: 'sweep_msg',
      conversationId: 'sweep_conv',
      senderAccountId: 'sweep_user',
      senderDeviceId: 'sweep_device',
      recipientDeviceId: 'sweep_device',
      ciphertext: 'x',
    );
    server.db.registerAttachmentReference('referenced_file', 'sweep_msg');

    server.db.createAttachment(
      fileId: 'fresh_file',
      accountId: 'sweep_user',
      fileSize: 3,
      fileHash: 'fresh_file',
    );
    server.db.updateAttachmentProgress('fresh_file', 3, 'COMPLETED');
    final fresh = File('${storageDir.path}/fresh_file')
      ..writeAsBytesSync([1, 2, 3]);

    await server.start('127.0.0.1', 0);

    expect(server.db.getAttachment('referenced_file'), isNotNull);
    expect(referenced.existsSync(), isTrue);
    expect(server.db.getAttachment('fresh_file'), isNotNull);
    expect(fresh.existsSync(), isTrue);
  });

  test('the retention window is configurable', () async {
    // A small volume holding 100 MB files may want far less than 30 days.
    await server.stop();
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_attachment_sweep',
      attachmentsStorageDir: storageDir,
      attachmentRetention: const Duration(days: 365 * 5),
    );
    seedAccount();
    final old = seedStale('five_year_file', completed: true);

    await server.start('127.0.0.1', 0);

    // 400 days is well inside a five-year window, so it survives a sweep
    // that would have removed it under the 30-day default.
    expect(server.db.getAttachment('five_year_file'), isNotNull);
    expect(old.existsSync(), isTrue);
  });
}
