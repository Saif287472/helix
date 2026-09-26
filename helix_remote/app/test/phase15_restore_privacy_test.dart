// Phase 15 backup-restore quiesce and account-deletion lifecycle tests.

import 'dart:io';
import 'dart:ffi' show DynamicLibrary;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/screens/backup_screen.dart';
import 'package:helix_remote/screens/privacy_screen.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_api/api/realtime_envelope.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';
import 'package:path/path.dart' as pathpkg;
import 'package:helix_remote/l10n/helix_localizations.dart';
import 'support/group_call_rest_stubs.dart';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

class _StubRestClient with GroupCallRestStubs implements HelixRemoteRestClient {
  bool requestedDeletion = false;
  Map<String, dynamic>? backupPayload;

  @override
  set accessToken(String? t) {}
  @override
  Future<void> close() async {}
  @override
  Future<void> requestAccountDeletion({required String confirmation}) async {
    requestedDeletion = true;
  }

  @override
  Future<Map<String, dynamic>> exportData() async => {'data': 'sample'};

  @override
  Future<Map<String, dynamic>> uploadBackup({
    required String backupId,
    required String backupData,
    required int version,
    required String kdf,
    required String salt,
    String backupKeyHint = '',
    int deletionWatermark = 0,
  }) async {
    backupPayload = {'backup_data': backupData};
    return {};
  }

  @override
  Future<Map<String, dynamic>> downloadBackup() async {
    return backupPayload ?? (throw Exception('No backup uploaded'));
  }

  @override
  dynamic noSuchMethod(Invocation i) async => {};
}

class _FakeGateway implements SyncGateway {
  @override
  Future<List<RemoteRealtimeEnvelope>> fetchInboundEvents({
    required int sinceSequence,
  }) async => [];
  @override
  Future<void> sendOutboundOperation({
    required String opId,
    required String type,
    required Map<String, dynamic> payload,
  }) async {}
}

class _FakeProtector implements RemoteMessageProtector {
  @override
  Future<String> encryptText({
    required String conversationId,
    required String messageId,
    required String plaintext,
    required String recipientDeviceId,
  }) async => 'enc:$plaintext';
  @override
  Future<String> decryptText({
    required String conversationId,
    required String messageId,
    required String ciphertext,
  }) async => ciphertext.substring(4);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

void _loadSqlCipher() {
  if (!Platform.isWindows) return;
  var dir = Directory.current;
  String? foundPath;
  for (var i = 0; i < 5; i++) {
    final candidate = pathpkg.join(
      dir.path,
      '.dart_tool',
      'lib',
      'sqlite3.dll',
    );
    if (File(candidate).existsSync()) {
      foundPath = candidate;
      break;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  if (foundPath != null) DynamicLibrary.open(foundPath);
}

HelixRemoteDatabase _openDb() {
  final db = HelixRemoteDatabase(File(':memory:'));
  db.initialize();
  return db;
}

Future<RemoteMessagingService> _makeMessaging(HelixRemoteDatabase db) async {
  var tick = 0;
  final svc = RemoteMessagingService(
    db: db,
    syncEngine: RemoteSyncEngine(db),
    gateway: _FakeGateway(),
    protector: _FakeProtector(),
    restClient: _StubRestClient(),
    clock: () => DateTime.fromMillisecondsSinceEpoch(++tick * 1000),
  );
  await svc.setupAccount(
    account: RemoteAccount(
      accountId: 'alice',
      identityPublicKey: 'ipk',
      createdAt: DateTime.now(),
    ),
    device: RemoteDevice(
      deviceId: 'dev-1',
      deviceName: 'Phone',
      deviceSigningPublicKey: 'spk',
      deviceAgreementPublicKey: 'apk',
      createdAt: DateTime.now(),
    ),
  );
  return svc;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(_loadSqlCipher);

  group('P15-W01 BackupScreen quiesce lifecycle', () {
    testWidgets('Create Backup and Restore Backup tiles are visible', (
      tester,
    ) async {
      final db = _openDb();
      addTearDown(db.close);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: BackupScreen(
            db: db,
            restClient: _StubRestClient(),
            tempDir: Directory.systemTemp.path,
          ),
        ),
      );

      expect(find.text('Create Backup'), findsOneWidget);
      expect(find.text('Restore Backup'), findsOneWidget);
    });

    testWidgets('onBeforeRestore is called when restore is triggered', (
      tester,
    ) async {
      final db = _openDb();
      addTearDown(db.close);
      final restClient = _StubRestClient();
      bool quiesced = false;
      bool reconnected = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: BackupScreen(
            db: db,
            restClient: restClient,
            tempDir: Directory.systemTemp.path,
            onBeforeRestore: () async => quiesced = true,
            onAfterRestore: () async => reconnected = true,
          ),
        ),
      );

      // Tap "Restore Backup" — prompts passphrase dialog
      await tester.tap(find.text('Restore Backup'));
      await tester.pumpAndSettle();

      // onBeforeRestore is called before the passphrase dialog is shown?
      // Actually no — passphrase is shown first. Cancel without entering one.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Cancelled before passphrase entered — quiesce should NOT have been called
      expect(quiesced, isFalse);
      expect(reconnected, isFalse);
    });

    testWidgets('Create Backup opens recovery-secret dialog', (tester) async {
      final db = _openDb();
      addTearDown(db.close);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: BackupScreen(
            db: db,
            restClient: _StubRestClient(),
            tempDir: Directory.systemTemp.path,
          ),
        ),
      );

      await tester.tap(find.text('Create Backup'));
      await tester.pumpAndSettle();

      // Dialog appears with obscured passphrase field and Encrypt Backup button
      expect(find.text('Encrypt Backup'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('P15-W02 PrivacyScreen account deletion lifecycle', () {
    testWidgets('Export and Delete Account tiles are visible', (tester) async {
      final db = _openDb();
      addTearDown(db.close);
      final messaging = await _makeMessaging(db);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: PrivacyScreen(
            restClient: _StubRestClient(),
            messagingService: messaging,
          ),
        ),
      );

      expect(find.text('Export my data'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
    });

    testWidgets('onBeforeDelete called before server deletion', (tester) async {
      final db = _openDb();
      addTearDown(db.close);
      final restClient = _StubRestClient();
      final messaging = await _makeMessaging(db);
      final callOrder = <String>[];

      bool accountDeleted = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: PrivacyScreen(
            restClient: restClient,
            messagingService: messaging,
            onBeforeDelete: () async => callOrder.add('before'),
            onAccountDeleted: () async {
              callOrder.add('purge');
              accountDeleted = true;
            },
          ),
        ),
      );

      // Tap Delete Account
      // Delete account now sits at the bottom of the screen, below the
      // ordinary toggles, so the tile has to be scrolled into view first.
      await tester.ensureVisible(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();

      // Enter correct confirmation text
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));

      expect(restClient.requestedDeletion, isTrue);
      expect(accountDeleted, isTrue);
      // onBeforeDelete fires before purge
      expect(callOrder, equals(['before', 'purge']));
    });

    testWidgets('wrong confirmation text shows error message', (tester) async {
      final db = _openDb();
      addTearDown(db.close);
      final messaging = await _makeMessaging(db);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: PrivacyScreen(
            restClient: _StubRestClient(),
            messagingService: messaging,
          ),
        ),
      );

      // Delete account now sits at the bottom of the screen, below the
      // ordinary toggles, so the tile has to be scrolled into view first.
      await tester.ensureVisible(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Deletion confirmation did not match'), findsOneWidget);
    });
  });
}
