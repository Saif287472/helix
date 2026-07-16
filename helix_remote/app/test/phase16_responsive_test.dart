// Phase 16 responsive UI and keyboard-awareness tests.
// Verifies that key screens render without overflow at constrained sizes
// and that keyboard-inset layouts remain usable.

import 'dart:io';
import 'dart:ffi' show DynamicLibrary;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/screens/backup_screen.dart';
import 'package:helix_remote/screens/device_management_screen.dart';
import 'package:helix_remote/screens/privacy_screen.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_api/api/realtime_envelope.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';
import 'package:path/path.dart' as pathpkg;

// ---------------------------------------------------------------------------
// Minimal stubs
// ---------------------------------------------------------------------------

class _MinRestClient implements HelixRemoteRestClient {
  @override
  set accessToken(String? t) {}
  @override
  Future<void> close() async {}
  @override
  Future<List<RemoteDevice>> listDevices() async => [];
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

void _setSmallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
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
    restClient: _MinRestClient(),
    clock: () => DateTime.fromMillisecondsSinceEpoch(++tick * 1000),
  );
  await svc.setupAccount(
    account: RemoteAccount(
      accountId: 'alice',
      username: 'alice',
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

  group('P16-W01 BackupScreen small screen (320×568)', () {
    testWidgets('renders without overflow', (tester) async {
      _setSmallScreen(tester);
      final db = _openDb();
      addTearDown(db.close);

      await tester.pumpWidget(
        MaterialApp(
          home: BackupScreen(
            db: db,
            restClient: _MinRestClient(),
            tempDir: Directory.systemTemp.path,
          ),
        ),
      );

      expect(find.text('Create Backup'), findsOneWidget);
      expect(find.text('Restore Backup'), findsOneWidget);
      // No overflow exception thrown
    });

    testWidgets('SafeArea wraps body content', (tester) async {
      _setSmallScreen(tester);
      final db = _openDb();
      addTearDown(db.close);

      await tester.pumpWidget(
        MaterialApp(
          home: BackupScreen(
            db: db,
            restClient: _MinRestClient(),
            tempDir: Directory.systemTemp.path,
          ),
        ),
      );

      // SafeArea is present in the tree
      expect(find.byType(SafeArea), findsWidgets);
    });
  });

  group('P16-W02 PrivacyScreen small screen (320×568)', () {
    testWidgets('renders without overflow', (tester) async {
      _setSmallScreen(tester);
      final db = _openDb();
      addTearDown(db.close);
      final messaging = await _makeMessaging(db);

      await tester.pumpWidget(
        MaterialApp(
          home: PrivacyScreen(
            restClient: _MinRestClient(),
            messagingService: messaging,
          ),
        ),
      );

      expect(find.text('Export My Data'), findsOneWidget);
      expect(find.text('Delete Account'), findsOneWidget);
    });
  });

  group('P16-W03 DeviceManagementScreen small screen (320×568)', () {
    testWidgets('renders without overflow', (tester) async {
      _setSmallScreen(tester);

      await tester.pumpWidget(
        MaterialApp(home: DeviceManagementScreen(restClient: _MinRestClient())),
      );
      await tester.pump();

      expect(find.text('Link New Device'), findsOneWidget);
    });
  });

  group('P16-W04 keyboard inset — scrollable forms', () {
    testWidgets('BackupScreen body is SingleChildScrollView', (tester) async {
      final db = _openDb();
      addTearDown(db.close);

      await tester.pumpWidget(
        MaterialApp(
          home: BackupScreen(
            db: db,
            restClient: _MinRestClient(),
            tempDir: Directory.systemTemp.path,
          ),
        ),
      );

      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('PrivacyScreen body is SingleChildScrollView', (tester) async {
      final db = _openDb();
      addTearDown(db.close);
      final messaging = await _makeMessaging(db);

      await tester.pumpWidget(
        MaterialApp(
          home: PrivacyScreen(
            restClient: _MinRestClient(),
            messagingService: messaging,
          ),
        ),
      );

      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
