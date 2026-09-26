import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart' hide DiagnosticLevel;
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/screens/contacts_screen.dart';
import 'package:helix_remote/screens/conversation_list_screen.dart';
import 'package:helix_remote/screens/conversation_screen.dart';
import 'package:helix_remote_api/api/realtime_envelope.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';
import 'package:path/path.dart' as p;
import 'package:helix_remote/l10n/helix_localizations.dart';
import 'support/group_call_rest_stubs.dart';

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

class _FakeRestClient with GroupCallRestStubs implements HelixRemoteRestClient {
  @override
  set accessToken(String? token) {}

  @override
  Future<void> close() async {}

  @override
  Future<Map<String, dynamic>> registerAccount({
    required String accountId,
    required String phoneHash,
    required String otpCode,
    String? otpChallengeId,
    String? inviteCode,
    required String displayName,
    bool tosAccepted = false,
    String tosVersion = '',
    required String accountIdentityPublicKey,
    required String deviceId,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
    required String accountRegistrationSignature,
    required String deviceRegistrationSignature,
    required String deviceName,
    String phoneLast4 = '',
  }) async => {};

  @override
  Future<Map<String, dynamic>> fetchDiscoverySalt() async => {};

  @override
  Future<Map<String, dynamic>> redeemRecovery({
    required String accountId,
    required String recoveryCode,
    required String deviceId,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
    required String deviceName,
    String? accountIdentityPublicKey,
    String? phoneHash,
  }) async => {};

  @override
  Future<Map<String, dynamic>> fetchProfile() async => {};

  @override
  Future<List<Map<String, dynamic>>> fetchContacts() async => [];

  @override
  Future<List<Map<String, dynamic>>> fetchContactRequests() async => [];

  @override
  Future<Map<String, dynamic>> requestPhoneOtp({
    required String phoneHash,
    required String phoneNumber,
  }) async => {};

  @override
  Future<Map<String, dynamic>> verifyPhoneOtp({
    required String phoneHash,
    required String otpCode,
    String? challengeId,
  }) async => {'valid': true};

  @override
  Future<Map<String, dynamic>> lookupInvite({
    required String inviteCode,
  }) async => {};

  @override
  Future<Map<String, dynamic>> autoIssueGlobalInvite() async => {};

  @override
  Future<Map<String, dynamic>> getServerInfo() async => {'server_name': ''};

  @override
  Future<Map<String, dynamic>> matchPhoneHashes(
    List<String> phoneHashes, {
    bool fullSync = false,
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
  Future<Map<String, dynamic>> requestNewDeviceLink({
    required String accountId,
    required String deviceId,
    required String deviceName,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
  }) async => {};

  @override
  Future<Map<String, dynamic>> approveDeviceLink({
    required String linkId,
    required String verificationCode,
  }) async => {};

  @override
  Future<Map<String, dynamic>> rejectDeviceLink({
    required String linkId,
    required String verificationCode,
  }) async => {};

  @override
  Future<Map<String, dynamic>> completeNewDeviceLink({
    required String linkId,
    required String signature,
  }) async => {};

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
  Future<Map<String, dynamic>> requestBackupMediaUpload({
    required String objectId,
    required int byteSize,
    required String sha256,
  }) async => {};

  @override
  Future<Map<String, dynamic>> getBackupMediaStatus(String objectId) async =>
      {};

  @override
  Future<List<Map<String, dynamic>>> searchContacts(String query) async =>
      const [];

  @override
  Future<Map<String, dynamic>> getMyProfile() async => {};

  @override
  Future<Map<String, dynamic>> updateDisplayName(String displayName) async =>
      {};

  @override
  Future<Map<String, dynamic>> sendCallSignal({
    String? targetAccountId,
    String? targetDeviceId,
    required Map<String, dynamic> payload,
    String? requestId,
  }) async => {};

  @override
  Future<Map<String, dynamic>> getPendingCalls() async => {'calls': []};

  @override
  Future<Map<String, dynamic>> acceptPendingCall(String callId) async => {};

  @override
  Future<Map<String, dynamic>> declinePendingCall(String callId) async => {};

  @override
  Future<Map<String, dynamic>> cancelPendingCall(String callId) async => {};

  @override
  Future<Map<String, dynamic>> registerPushToken({
    required String pushToken,
    String tokenType = 'FCM',
  }) async => {'status': 'registered'};

  @override
  Future<Map<String, dynamic>> deregisterPushToken() async => {
    'status': 'deregistered',
  };

  @override
  Future<Map<String, dynamic>> getTurnCredentials() async => {};
}

class _ThrowingConversationListService extends RemoteMessagingService {
  _ThrowingConversationListService({
    required super.db,
    required super.syncEngine,
    required super.gateway,
    required super.protector,
    required super.restClient,
    required super.clock,
  });

  @override
  List<RemoteConversation> conversationList() =>
      throw StateError('simulated DB failure');
}

class _CountingMessagingService extends RemoteMessagingService {
  _CountingMessagingService({
    required super.db,
    required super.syncEngine,
    required super.gateway,
    required super.protector,
    required super.restClient,
    required super.clock,
  });

  int historyReads = 0;
  int singleMessageReads = 0;

  @override
  Future<List<RemoteDecryptedMessage>> messageHistory(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) {
    historyReads++;
    return super.messageHistory(conversationId, limit: limit, offset: offset);
  }

  @override
  Future<RemoteDecryptedMessage?> messageById(String messageId) {
    singleMessageReads++;
    return super.messageById(messageId);
  }
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
  late _CountingMessagingService service;
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
    service = _CountingMessagingService(
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
        localizationsDelegates: HelixLocalizations.localizationsDelegates,
        supportedLocales: HelixLocalizations.supportedLocales,
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

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'budget');
    await tester.pumpAndSettle();

    expect(find.text('budget marker from bob'), findsOneWidget);
    expect(find.text('plain hello'), findsNothing);
  });

  testWidgets('opening a conversation does not spiral into an unbounded '
      'self-triggering reload loop', (tester) async {
    // _loadMessages() calls markConversationRead() at the end of every
    // load, which used to emit a conversations-area change for this
    // conversation. If _onRemoteChange treated that as a reason to
    // reload messages too, it would call _loadMessages() again -> mark
    // read again -> emit again -> forever, spinning as fast as the event
    // loop allows (an ANR on-device; here it would show up as
    // pumpAndSettle() failing to settle).
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: HelixLocalizations.localizationsDelegates,
        supportedLocales: HelixLocalizations.supportedLocales,
        home: ConversationScreen(
          conversationId: 'dm_alice_bob',
          messagingService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // markConversationRead() no longer enqueues an outbox operation at
    // all: 'MARK_CONVERSATION_READ' was never in
    // RemoteOutboundOperation.values, so every instance of it failed
    // permanently - there's no server endpoint for it. Asserting zero
    // here (not "exactly one") covers both bugs: the reload loop, and
    // this dead-end outbox entry it kept multiplying.
    final markReadOps = db
        .getPendingOperations()
        .where((op) => op['type'] == 'MARK_CONVERSATION_READ')
        .toList();
    expect(markReadOps, isEmpty);
  });

  testWidgets('P09 open conversation reacts to inbound sync messages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: HelixLocalizations.localizationsDelegates,
        supportedLocales: HelixLocalizations.supportedLocales,
        home: ConversationScreen(
          conversationId: 'dm_alice_bob',
          messagingService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('live arrival'), findsNothing);
    final historyReadsBeforeInbound = service.historyReads;

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

    // See the identical comment in the P09 contacts test above: the change
    // reaches ConversationScreen through two chained broadcast streams, and
    // the second hop needs runAsync() to flush under flutter_test's
    // fake-async zone - pumpAndSettle() alone never observes it.
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(find.text('live arrival'), findsOneWidget);
    expect(service.historyReads, historyReadsBeforeInbound);
    expect(service.singleMessageReads, equals(1));
  });

  testWidgets('P12 conversation screen sends and mutates through service', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: HelixLocalizations.localizationsDelegates,
        supportedLocales: HelixLocalizations.supportedLocales,
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

    await tester.longPress(find.text('draft text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(String.fromCharCode(0x1F44D)));
    await tester.pumpAndSettle();
    expect(find.text(String.fromCharCode(0x1F44D)), findsOneWidget);

    await tester.longPress(find.text('draft text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit message'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'updated text');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('updated text'), findsOneWidget);

    await tester.longPress(find.text('updated text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete for me'));
    await tester.pumpAndSettle();
    expect(find.text('updated text'), findsNothing);
  });

  testWidgets('reply quote jumps to original message and highlights it', (
    tester,
  ) async {
    await service.sendText(
      conversationId: 'dm_alice_bob',
      messageId: 'msg_reply_to_bob',
      plaintext: 'reply body only',
      recipientDeviceIds: const [],
      replyTo: const RemoteReplyReference(
        messageId: 'msg_bob_1',
        senderAccountId: 'bob',
        snippet: 'budget marker from bob',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: HelixLocalizations.localizationsDelegates,
        supportedLocales: HelixLocalizations.supportedLocales,
        home: ConversationScreen(
          conversationId: 'dm_alice_bob',
          messagingService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('reply body only'), findsOneWidget);
    expect(find.byKey(const ValueKey('reply_quote_msg_bob_1')), findsOneWidget);

    final before = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('message_bubble_msg_bob_1')),
    );
    final beforeDecoration = before.decoration! as BoxDecoration;

    await tester.tap(find.byKey(const ValueKey('reply_quote_msg_bob_1')));
    // The reply quote's InkWell is nested inside the message tile's own
    // GestureDetector, which also registers onDoubleTap - so the single tap
    // doesn't resolve until Flutter's double-tap disambiguation window
    // elapses (kDoubleTapTimeout, 300ms), not on the very next frame.
    await tester.pump(kDoubleTapTimeout);

    final highlighted = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('message_bubble_msg_bob_1')),
    );
    final highlightedDecoration = highlighted.decoration! as BoxDecoration;

    expect(highlightedDecoration.color, isNot(beforeDecoration.color));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
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
        localizationsDelegates: HelixLocalizations.localizationsDelegates,
        supportedLocales: HelixLocalizations.supportedLocales,
        home: ContactsScreen(messagingService: service, root: root),
      ),
    );
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
    'P07 phone-book overrides feed into the contacts list and surface '
    'not-yet-added matches as suggestions',
    (tester) async {
      // Bob is already an accepted contact (nickname 'Bob' from setUp); a
      // phone-book match should override that display without touching the
      // persisted nickname. Dave has no contact row at all - he should show
      // up as a suggestion the user can add.
      service.recordPhoneContactMatches({
        'bob': 'Bobby (Phone)',
        'dave': 'Dave M.',
      });

      final dir = Directory.systemTemp.createTempSync('p07b_widget_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final root = RemoteCompositionRoot.production(
        databaseDirectory: dir.path,
        devConfig: _devConfig(dir.path),
      );
      addTearDown(root.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: ContactsScreen(messagingService: service, root: root),
        ),
      );
      await tester.pump();

      // Existing contact's tile now shows the phone-book name, not the
      // stored nickname - peerDisplayName()'s resolution order, applied
      // here without mutating the underlying contact record.
      expect(find.text('Bobby (Phone)'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
      expect(db.getContact('bob')!.nickname, equals('Bob'));

      // Dave isn't a contact yet - he appears as a phone-book suggestion.
      expect(find.text('From your phone book'), findsOneWidget);
      expect(find.text('Dave M.'), findsOneWidget);
      expect(db.getContact('dave'), isNull);

      await tester.tap(find.text('Add'));
      await tester.pump();

      expect(db.getContact('dave')!.status, 'PendingSent');
      expect(db.getContact('dave')!.nickname, equals('Dave M.'));
      // Now that Dave is a contact, he moves out of the suggestions section.
      expect(find.text('From your phone book'), findsNothing);
    },
  );

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
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: ContactsScreen(messagingService: service, root: root),
        ),
      );
      await tester.pump();
      expect(service.debugChangeListenerCount, equals(1));

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

      // The change reaches ContactsScreen through two chained broadcast
      // streams (syncEngine.changes -> RemoteMessagingService._emitChange ->
      // service.changes -> ContactsScreen's listener). The second hop's
      // delivery is a real scheduled callback that plain pump()/pumpAndSettle()
      // calls don't flush under flutter_test's fake-async zone; runAsync()
      // drains it the same way it's needed for real I/O elsewhere in this
      // suite.
      await tester.runAsync(() async {});
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
        localizationsDelegates: HelixLocalizations.localizationsDelegates,
        supportedLocales: HelixLocalizations.supportedLocales,
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
        localizationsDelegates: HelixLocalizations.localizationsDelegates,
        supportedLocales: HelixLocalizations.supportedLocales,
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
        localizationsDelegates: HelixLocalizations.localizationsDelegates,
        supportedLocales: HelixLocalizations.supportedLocales,
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
        localizationsDelegates: HelixLocalizations.localizationsDelegates,
        supportedLocales: HelixLocalizations.supportedLocales,
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

  testWidgets(
    'P17 conversation list renders empty state when conversationList() throws',
    (tester) async {
      // Regression: before the fix, _conversations was declared `late` and the
      // error path in _reload() called setState(() => _loaded = true) without
      // assigning _conversations, causing LateInitializationError on the next
      // build(). After the fix (_conversations = []), the screen should show
      // the empty-state placeholder instead of crashing.
      final throwingService = _ThrowingConversationListService(
        db: db,
        syncEngine: RemoteSyncEngine(db),
        gateway: gateway,
        protector: protector,
        restClient: _FakeRestClient(),
        clock: clock,
      );
      final dir = Directory.systemTemp.createTempSync('p17_late_field_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final root = RemoteCompositionRoot.production(
        databaseDirectory: dir.path,
        devConfig: _devConfig(dir.path),
      );
      addTearDown(root.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: ConversationListScreen(
            messagingService: throwingService,
            root: root,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('No conversations yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'starting a new chat from the New Chat picker actually creates the '
    'conversation, not just a screen for one that does not exist yet',
    (tester) async {
      // conversationIdForPeer only derives an ID string - it never writes a
      // conversation/membership row. Without _showNewChatPicker also
      // calling createDirectConversation for a contact with no prior chat,
      // picking them here opened ConversationScreen for a conversation
      // absent from the database entirely.
      service.addContact(peerAccountId: 'carol', nickname: 'Carol');

      final dir = Directory.systemTemp.createTempSync('new_chat_widget_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final root = RemoteCompositionRoot.production(
        databaseDirectory: dir.path,
        devConfig: _devConfig(dir.path),
      );
      addTearDown(root.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: ConversationListScreen(messagingService: service, root: root),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('New chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carol'));
      await tester.pumpAndSettle();

      final conversationId = service.conversationIdForPeer('carol');
      expect(conversationId, isNotNull);
      expect(
        service.conversationMemberIds(conversationId!),
        containsAll(['alice', 'carol']),
      );
    },
  );

  testWidgets(
    'starting a new chat with a contact already chatted with reuses the '
    'existing conversation instead of resetting its state',
    (tester) async {
      // createDirectConversation's upsert always resets last_sequence to
      // 0, so the picker must detect an existing conversation and reuse it
      // rather than blindly recreating it. dm_alice_bob (from setUp) isn't
      // usable to prove that here: it's a readable literal ID, not the
      // peer-derived one conversationIdForPeer() actually computes, so the
      // picker would never recognize it as "already exists" - this needs
      // its own conversation seeded under the real derived ID.
      final existingId = service.createDirectConversation(
        peerAccountId: 'bob',
        title: 'Bob',
      );
      db.saveMessage(
        RemoteMessage(
          messageId: 'msg_existing_direct',
          conversationId: existingId,
          senderAccountId: 'bob',
          senderDeviceId: 'bob_device',
          ciphertext: await cipher('prior history with bob'),
        ),
        1,
        clock().millisecondsSinceEpoch,
        RemoteMessageStatus.delivered,
      );

      final dir = Directory.systemTemp.createTempSync('new_chat_existing_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final root = RemoteCompositionRoot.production(
        databaseDirectory: dir.path,
        devConfig: _devConfig(dir.path),
      );
      addTearDown(root.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: ConversationListScreen(messagingService: service, root: root),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('New chat'));
      await tester.pumpAndSettle();
      // 'Bob' also matches the existing dm_alice_bob tile underneath the
      // picker sheet, so the tap must be scoped to the picker itself
      // (DraggableScrollableSheet) rather than matching either occurrence.
      await tester.tap(
        find.descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.text('Bob'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('prior history with bob'), findsOneWidget);

      // Reused, not recreated: last_sequence still reflects the seeded
      // message instead of being reset to 0 by a second createDirectConversation.
      expect(
        service.conversationMemberIds(existingId),
        containsAll(['alice', 'bob']),
      );
    },
  );
}
