import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide DiagnosticLevel;
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/screens/conversation_list_screen.dart';
import 'package:helix_remote/screens/conversation_screen.dart';
import 'package:helix_remote_api/api/realtime_envelope.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';
import 'package:path/path.dart' as p;

class _FakeProtector implements RemoteMessageProtector {
  @override
  Future<String> encryptText({
    required String conversationId,
    required String messageId,
    required String plaintext,
    required String recipientDeviceId,
  }) async {
    return 'cipher:${base64UrlEncode(utf8.encode(plaintext))}';
  }

  @override
  Future<String> decryptText({
    required String conversationId,
    required String messageId,
    required String ciphertext,
  }) async {
    return utf8.decode(
      base64Url.decode(ciphertext.substring('cipher:'.length)),
    );
  }
}

class _FakeGateway implements SyncGateway {
  final sent = <Map<String, dynamic>>[];

  @override
  Future<List<RemoteRealtimeEnvelope>> fetchInboundEvents({
    required int sinceSequence,
  }) async => [];

  @override
  Future<void> sendOutboundOperation({
    required String opId,
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    sent.add({'op_id': opId, 'type': type, 'payload': payload});
  }
}

class _FakeRestClient implements HelixRemoteRestClient {
  @override
  set accessToken(String? token) {}

  @override
  Future<void> close() async {}

  @override
  Future<Map<String, dynamic>> registerAccount({
    required String accountId,
    required String username,
    required String accountIdentityPublicKey,
    required String deviceId,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
    required String accountRegistrationSignature,
    required String deviceRegistrationSignature,
    required String deviceName,
  }) async => {};

  @override
  Future<Map<String, dynamic>> getChallenge({
    required String accountId,
    required String deviceId,
  }) async => {};

  @override
  Future<Map<String, dynamic>> loginDevice({
    required String accountId,
    required String deviceId,
    required String signature,
  }) async => {};

  @override
  Future<Map<String, dynamic>> refreshToken({
    required String refreshToken,
  }) async => {};

  @override
  Future<List<RemoteDevice>> listDevices() async => [];

  @override
  Future<void> renameDevice({
    required String deviceId,
    required String deviceName,
  }) async {}

  @override
  Future<void> revokeDevice(String deviceId) async {}

  @override
  Future<void> reportLostDevice(String deviceId) async {}

  @override
  Future<List<Map<String, dynamic>>> getDeviceSecurityHistory(
    String deviceId,
  ) async => [];

  @override
  Future<void> uploadPreKeys({
    required int signedPrekeyId,
    required String signedPrekey,
    required String signedPrekeySignature,
    required List<Map<String, dynamic>> oneTimePrekeys,
  }) async {}

  @override
  Future<Map<String, dynamic>> getPreKeyBundle({
    required String accountId,
  }) async => {'devices': <Map<String, dynamic>>[]};

  @override
  Future<Map<String, dynamic>> sendContactRequest({
    required String peerAccountId,
  }) async => {};

  @override
  Future<void> acceptContactRequest(String requestId) async {}

  @override
  Future<Map<String, dynamic>> requestAttachmentUpload({
    required int fileSize,
    required String fileHash,
  }) async => {};

  @override
  Future<Map<String, dynamic>> requestAttachmentDownload(String fileId) async =>
      {};

  @override
  Future<void> requestAccountDeletion({required String confirmation}) async {}

  @override
  Future<Map<String, dynamic>> exportData() async => {};

  @override
  Future<Map<String, dynamic>> uploadBackup({
    required String backupId,
    required String backupData,
    required int version,
    required String kdf,
    required String salt,
    String backupKeyHint = '',
    int deletionWatermark = 0,
  }) async => {};

  @override
  Future<Map<String, dynamic>> downloadBackup() async => {};

  @override
  Future<Map<String, dynamic>> sendCallSignal({
    required String targetDeviceId,
    required Map<String, dynamic> payload,
  }) async => {};

  @override
  Future<Map<String, dynamic>> getTurnCredentials() async => {};
}

RemoteDevelopmentConfig _devConfig(String dir) => RemoteDevelopmentConfig(
  profile: RemoteRuntimeProfile.localWindows,
  restBaseUri: Uri.parse('http://127.0.0.1:8080'),
  webSocketUri: Uri.parse('ws://127.0.0.1:8080/api/v1/ws'),
  allowInsecureTransport: true,
  backendHostMode: 'same-pc',
  requestTimeoutMs: 5000,
  reconnectPolicy: const ReconnectPolicy(),
  databaseDirectory: dir,
  attachmentCacheDir: '$dir/attachments_cache',
  diagnosticLevel: DiagnosticLevel.info,
);

void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      var dir = Directory.current;
      for (var i = 0; i < 5; i++) {
        final possiblePath = p.join(
          dir.path,
          '.dart_tool',
          'lib',
          'sqlite3.dll',
        );
        if (File(possiblePath).existsSync()) {
          DynamicLibrary.open(possiblePath);
          break;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
  });

  late HelixRemoteDatabase db;
  late _FakeGateway gateway;
  late RemoteMessagingService service;
  late _FakeProtector protector;
  var tick = 0;

  DateTime clock() => DateTime.fromMillisecondsSinceEpoch(++tick * 1000);

  Future<String> cipher(String plaintext) {
    return protector.encryptText(
      conversationId: 'dm_alice_bob',
      messageId: 'seed',
      plaintext: plaintext,
      recipientDeviceId: 'local-history',
    );
  }

  setUp(() async {
    tick = 0;
    db = HelixRemoteDatabase(File(':memory:'));
    db.initialize();
    gateway = _FakeGateway();
    protector = _FakeProtector();
    service = RemoteMessagingService(
      db: db,
      syncEngine: RemoteSyncEngine(db),
      gateway: gateway,
      protector: protector,
      restClient: _FakeRestClient(),
      clock: clock,
    );
    await service.setupAccount(
      account: RemoteAccount(
        accountId: 'alice',
        username: 'alice',
        identityPublicKey: 'alice_identity_key',
        createdAt: clock(),
      ),
      device: RemoteDevice(
        deviceId: 'alice_device',
        deviceName: 'Alice phone',
        deviceSigningPublicKey: 'alice_signing',
        deviceAgreementPublicKey: 'alice_agreement',
        createdAt: clock(),
      ),
    );
    service.addContact(peerAccountId: 'bob', nickname: 'Bob');
    service.createDirectConversation(
      peerAccountId: 'bob',
      conversationId: 'dm_alice_bob',
      title: 'Bob',
    );
    db.saveMessage(
      RemoteMessage(
        messageId: 'msg_bob_1',
        conversationId: 'dm_alice_bob',
        senderAccountId: 'bob',
        senderDeviceId: 'bob_device',
        ciphertext: await cipher('budget marker from bob'),
      ),
      1,
      clock().millisecondsSinceEpoch,
      RemoteMessageStatus.delivered,
    );
    db.saveMessage(
      RemoteMessage(
        messageId: 'msg_bob_2',
        conversationId: 'dm_alice_bob',
        senderAccountId: 'bob',
        senderDeviceId: 'bob_device',
        ciphertext: await cipher('plain hello'),
      ),
      2,
      clock().millisecondsSinceEpoch,
      RemoteMessageStatus.delivered,
    );
  });

  tearDown(() {
    db.close();
  });

  testWidgets('P12 conversation screen uses service for search and receipts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(
          conversationId: 'dm_alice_bob',
          messagingService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('budget marker from bob'), findsOneWidget);
    expect(
      db.getPendingOperations().where((op) => op['type'] == 'READ_RECEIPT'),
      isNotEmpty,
    );

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'budget');
    await tester.pumpAndSettle();

    expect(find.text('budget marker from bob'), findsOneWidget);
    expect(find.text('plain hello'), findsNothing);
  });

  testWidgets('P09 open conversation reacts to inbound sync messages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(
          conversationId: 'dm_alice_bob',
          messagingService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('live arrival'), findsNothing);

    final applied = service.syncEngine.handleIncomingEnvelope(
      RemoteRealtimeEnvelope(
        eventId: 'evt_live_message',
        serverSequence: 1,
        schemaVersion: 1,
        timestamp: clock().millisecondsSinceEpoch,
        type: 'chat_message',
        payload: {
          'message_id': 'msg_live',
          'conversation_id': 'dm_alice_bob',
          'sender_account_id': 'bob',
          'sender_device_id': 'bob_device',
          'ciphertext': await cipher('live arrival'),
        },
      ),
    );
    expect(applied, isTrue);

    await tester.pumpAndSettle();
    expect(find.text('live arrival'), findsOneWidget);
  });

  testWidgets('P12 conversation screen sends and mutates through service', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(
          conversationId: 'dm_alice_bob',
          messagingService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'draft text');
    await tester.pump();
    expect(gateway.sent.last['type'], 'TYPING');
    final typingPayload = gateway.sent.last['payload'] as Map<String, dynamic>;
    expect(typingPayload['is_typing'], isTrue);

    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(find.text('draft text'), findsOneWidget);
    expect(
      db.getPendingOperations().any((op) => op['type'] == 'SEND_MESSAGE'),
      isFalse,
    );

    await tester.tap(find.byTooltip('Message actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('React +1'));
    await tester.pumpAndSettle();
    expect(find.text('+1'), findsOneWidget);

    await tester.tap(find.byTooltip('Message actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'updated text');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('updated text'), findsOneWidget);

    await tester.tap(find.byTooltip('Message actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete for me'));
    await tester.pumpAndSettle();
    expect(find.text('updated text'), findsNothing);
  });

  testWidgets('P07 contact screen exposes pending request actions', (
    tester,
  ) async {
    service.recordIncomingContactRequest(
      requestId: 'cr_carol',
      peerAccountId: 'carol',
      nickname: 'Carol',
    );
    service.sendContactRequest(requestId: 'cr_dan', peerAccountId: 'dan');

    final dir = Directory.systemTemp.createTempSync('p07_widget_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final root = RemoteCompositionRoot.production(
      databaseDirectory: dir.path,
      devConfig: _devConfig(dir.path),
    );
    addTearDown(root.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ConversationListScreen(messagingService: service, root: root),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.people));
    await tester.pump();

    expect(find.text('PendingReceived'), findsOneWidget);
    expect(find.byTooltip('Accept request'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.byTooltip('Accept request'));
    await tester.pump();
    expect(db.getContact('carol')!.status, 'Accepted');
    expect(find.text('Contact request accepted'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(db.getContact('dan'), isNull);
    expect(db.getContactRequest('cr_dan')!.status, 'Cancelled');
  });

  testWidgets(
    'P09 contact list reacts to inbound contact changes and disposes',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('p09_widget_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final root = RemoteCompositionRoot.production(
        databaseDirectory: dir.path,
        devConfig: _devConfig(dir.path),
      );
      addTearDown(root.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ConversationListScreen(messagingService: service, root: root),
        ),
      );
      await tester.pump();
      expect(service.debugChangeListenerCount, equals(1));

      await tester.tap(find.byIcon(Icons.people));
      await tester.pump();
      expect(find.text('Eve'), findsNothing);

      final applied = service.syncEngine.handleIncomingEnvelope(
        RemoteRealtimeEnvelope(
          eventId: 'evt_contact_eve',
          serverSequence: 1,
          schemaVersion: 1,
          timestamp: clock().millisecondsSinceEpoch,
          type: 'contact_updated',
          payload: {
            'peer_account_id': 'eve',
            'nickname': 'Eve',
            'status': 'PendingReceived',
            'request_id': 'cr_eve',
            'direction': 'received',
          },
        ),
      );
      expect(applied, isTrue);

      await tester.pump();
      expect(find.text('Eve'), findsOneWidget);
      expect(find.byTooltip('Accept request'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(service.debugChangeListenerCount, equals(0));
    },
  );

  testWidgets('P10 outbox banner shows queued and failed retry state', (
    tester,
  ) async {
    db.enqueueOperation(
      'op_profile',
      'PROFILE_UPDATE',
      jsonEncode({'display_name': 'private display'}),
      idempotencyKey: 'profile:alice',
    );
    db.enqueueOperation(
      'op_report',
      'SAFETY_REPORT',
      jsonEncode({'context_hash': 'secret-context-hash'}),
      idempotencyKey: 'report:1',
    );
    db.updateOperationStatus('op_report', 'FAILED', 5);

    final dir = Directory.systemTemp.createTempSync('p10_widget_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final root = RemoteCompositionRoot.production(
      databaseDirectory: dir.path,
      devConfig: _devConfig(dir.path),
    );
    addTearDown(root.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ConversationListScreen(messagingService: service, root: root),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Outbox:'), findsOneWidget);
    expect(find.textContaining('queued'), findsOneWidget);
    expect(find.textContaining('failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('secret-context-hash'), findsNothing);
    expect(find.textContaining('private display'), findsNothing);
  });

  testWidgets('P11 attachment control is reachable only with service', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(
          conversationId: 'dm_alice_bob',
          messagingService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Attach file'), findsNothing);

    final attachmentDir = Directory.systemTemp.createTempSync(
      'p11_attachment_ui_',
    );
    addTearDown(() => attachmentDir.deleteSync(recursive: true));
    final attachmentService = RemoteAttachmentService(
      baseUrl: 'http://127.0.0.1:9',
      authToken: 'test-token',
      db: db,
      tempDir: attachmentDir,
      wrappingKey: Uint8List(32),
    );
    var pickerCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(
          conversationId: 'dm_alice_bob',
          messagingService: service,
          attachmentService: attachmentService,
          pickAttachmentFile: () async {
            pickerCalled = true;
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Attach file'), findsOneWidget);
    await tester.tap(find.byTooltip('Attach file'));
    await tester.pump();
    expect(pickerCalled, isTrue);
  });

  testWidgets('P11 encrypted attachment messages render file actions', (
    tester,
  ) async {
    const keyDeliverySecret = 'delivery-secret';
    final attachmentPlaintext = jsonEncode(
      const RemoteAttachmentContent(
        fileId: 'file_rendered',
        filename: 'photo.png',
        fileSize: 2048,
        fileHash: 'file_rendered',
        mimeType: 'image/png',
        keyDeliverySecret: keyDeliverySecret,
      ).toMessageJson(),
    );
    db.saveMessage(
      RemoteMessage(
        messageId: 'msg_attachment_rendered',
        conversationId: 'dm_alice_bob',
        senderAccountId: 'bob',
        senderDeviceId: 'bob_device',
        ciphertext: await cipher(attachmentPlaintext),
      ),
      3,
      clock().millisecondsSinceEpoch,
      RemoteMessageStatus.delivered,
    );

    final attachmentDir = Directory.systemTemp.createTempSync(
      'p11_attachment_card_',
    );
    addTearDown(() => attachmentDir.deleteSync(recursive: true));
    final attachmentService = RemoteAttachmentService(
      baseUrl: 'http://127.0.0.1:9',
      authToken: 'test-token',
      db: db,
      tempDir: attachmentDir,
      wrappingKey: Uint8List(32),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(
          conversationId: 'dm_alice_bob',
          messagingService: service,
          attachmentService: attachmentService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Attachment: photo.png'), findsOneWidget);
    expect(find.text('photo.png'), findsOneWidget);
    expect(find.textContaining('Not downloaded'), findsOneWidget);
    expect(find.byTooltip('Download attachment'), findsOneWidget);
    expect(find.textContaining(keyDeliverySecret), findsNothing);
  });
}
