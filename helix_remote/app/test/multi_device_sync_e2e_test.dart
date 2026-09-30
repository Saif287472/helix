// End to end against a real in-process backend: two devices signed in to one
// account (the second with the password) must both show every chat and
// message - what either of them sends, and what the other person sends.

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/services/inbound_message_notifier.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/invite_codes.dart';
import 'package:helix_remote_backend/src/sms_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _RecordingSms implements SmsProvider {
  final sent = <String>[];
  @override
  bool get isConfigured => true;
  @override
  String get displayName => 'Recording';
  @override
  Future<void> send({
    required String phoneNumber,
    required String message,
  }) async => sent.add(message);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  FlutterSecureStorage.setMockInitialValues({});

  late BackendServer server;
  late _RecordingSms sms;
  late Directory dir;

  setUp(() async {
    sms = _RecordingSms();
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'multi_device_sync_e2e_secret_for_tests_only',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 100,
      smsProvider: sms,
    );
    await server.start('127.0.0.1', 0);
    dir = Directory.systemTemp.createTempSync('multi_device_sync_');
  });

  tearDown(() async {
    await server.stop();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  RemoteCompositionRoot rootFor(String name, KeyValueStore store) {
    final path = '${dir.path}/$name';
    Directory(path).createSync();
    final port = server.httpServer!.port;
    return RemoteCompositionRoot.withConfig(
      RemoteProductConfig(
        displayName: 'Helix Remote',
        packageId: 'com.helix.remote',
        secureStoragePrefix: 'helix_remote_v1_${name}_',
        methodChannelNamespace: 'com.helix.remote',
        logNamespace: 'helix_remote',
        databaseDirectory: path,
      ),
      devConfig: RemoteDevelopmentConfig(
        profile: RemoteRuntimeProfile.localWindows,
        restBaseUri: Uri.parse('http://127.0.0.1:$port'),
        webSocketUri: Uri.parse('ws://127.0.0.1:$port/api/v1/ws'),
        allowInsecureTransport: true,
        backendHostMode: 'same-pc',
        requestTimeoutMs: 5000,
        reconnectPolicy: const ReconnectPolicy(),
        databaseDirectory: path,
        attachmentCacheDir: '$path/attachments_cache',
        diagnosticLevel: DiagnosticLevel.info,
      ),
      keyValueStore: store,
    );
  }

  String seedInvite() {
    final code = generateInviteCode();
    final now = DateTime.now().millisecondsSinceEpoch;
    server.db.createInviteCredential(
      inviteId: generateInviteId(),
      inviteCodeHash: hashInviteCode(code),
      serverAddress: 'https://test.local',
      issuerType: 'ADMIN',
      issuerLabel: 'multi-device-e2e',
      createdAt: now,
      expiresAt: now + const Duration(days: 7).inMilliseconds,
    );
    return code;
  }

  Future<RemoteCompositionRoot> register(
    String name,
    String phone,
    _MemoryStore store,
  ) async {
    final root = rootFor(name, store);
    addTearDown(root.dispose);
    await root.initialize();
    final otp = await root.requestOtp(phone);
    final code = RegExp(r'\d{6}').firstMatch(sms.sent.last)!.group(0)!;
    await root.verifyOtp(
      phoneHash: otp.phoneHash,
      otpCode: code,
      challengeId: otp.challengeId,
    );
    await root.registerAndLogin(
      phoneNumber: phone,
      displayName: name,
      otpCode: code,
      otpChallengeId: otp.challengeId,
      inviteCode: seedInvite(),
      tosAccepted: true,
      tosVersion: '1',
    );
    return root;
  }

  /// Pushes what [root] has queued, then pulls what is waiting for it.
  Future<void> sync(RemoteCompositionRoot root) async {
    final ms = root.messagingService;
    await ms.processOutboundQueue();
    await ms.syncInbound();
  }

  Future<List<String>> texts(RemoteCompositionRoot root, String convId) async {
    final history = await root.messagingService.messageHistory(convId);
    return history.map((m) => m.text).toList();
  }

  test(
    'a password-signed-in second device sees both sides of every chat',
    () async {
      final aliceStore = _MemoryStore();
      final alicePhone = await register(
        'alice_phone',
        '+8801711111111',
        aliceStore,
      );
      await alicePhone.setAccountPassword(newPassword: 'correct horse battery');

      final pcStore = _MemoryStore();
      final alicePc = rootFor('alice_pc', pcStore);
      addTearDown(alicePc.dispose);
      await alicePc.initialize();
      final lookup = await alicePc.lookupPasswordAccount('+8801711111111');
      await alicePc.signInWithPassword(
        lookup: lookup,
        password: 'correct horse battery',
      );
      expect(pcStore.values['account_id'], aliceStore.values['account_id']);

      final bobStore = _MemoryStore();
      final bob = await register('bob', '+8801722222222', bobStore);

      final aliceId = aliceStore.values['account_id']!;
      final bobId = bobStore.values['account_id']!;

      // Each device as if it were in the background: what would it announce?
      final shown = <String, List<String>>{};
      for (final (name, root) in [
        ('phone', alicePhone),
        ('pc', alicePc),
        ('bob', bob),
      ]) {
        final notifier = InboundMessageNotifier(
          root.messagingService,
          isInForeground: () => false,
          show:
              ({
                required String notificationKey,
                required String title,
                required String body,
              }) async => (shown[name] ??= []).add(body),
        )..start();
        addTearDown(notifier.dispose);
      }

      // 1. Alice's phone starts the chat and sends.
      final phoneMs = alicePhone.messagingService;
      final convId = phoneMs.createDirectConversation(peerAccountId: bobId);
      await phoneMs.sendText(
        conversationId: convId,
        plaintext: 'hello from the phone',
        recipientDeviceIds: phoneMs.recipientDeviceIdsForConversation(convId),
      );
      await sync(alicePhone);

      await sync(bob);
      expect(await texts(bob, convId), contains('hello from the phone'));

      await sync(alicePc);
      final pcConvs = alicePc.messagingService.conversationList();
      expect(
        pcConvs.map((c) => c.conversationId),
        contains(convId),
        reason: 'the chat started on the phone appears on the PC',
      );
      expect(
        alicePc.messagingService.conversationMemberIds(convId),
        containsAll([aliceId, bobId]),
      );
      expect(
        await texts(alicePc, convId),
        contains('hello from the phone'),
        reason: 'what the phone sent shows on the PC',
      );

      // 2. Bob replies: both of Alice's devices get it.
      final bobMs = bob.messagingService;
      await bobMs.sendText(
        conversationId: convId,
        plaintext: 'hi alice',
        recipientDeviceIds: bobMs.recipientDeviceIdsForConversation(convId),
      );
      await sync(bob);
      await sync(alicePhone);
      await sync(alicePc);
      expect(await texts(alicePhone, convId), contains('hi alice'));
      expect(await texts(alicePc, convId), contains('hi alice'));

      // 3. The PC answers: Bob and the phone both get it.
      final pcMs = alicePc.messagingService;
      await pcMs.sendText(
        conversationId: convId,
        plaintext: 'answering from the PC',
        recipientDeviceIds: pcMs.recipientDeviceIdsForConversation(convId),
      );
      await sync(alicePc);
      await sync(bob);
      await sync(alicePhone);
      expect(await texts(bob, convId), contains('answering from the PC'));
      expect(
        await texts(alicePhone, convId),
        contains('answering from the PC'),
        reason: 'what the PC sent shows on the phone',
      );

      // Notifications: only for the other person's messages, once each.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(shown['bob'], ['hello from the phone', 'answering from the PC']);
      expect(shown['phone'], ['hi alice']);
      expect(shown['pc'], ['hi alice']);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'a chat from before the second device signed in reaches it too',
    () async {
      // The phone's daily backup ran when it registered - before this chat -
      // so only a backup made for the new device can carry it.
      final saved = RemoteCompositionHistoryBackup.followUpRestoreDelays;
      RemoteCompositionHistoryBackup.followUpRestoreDelays = const [
        Duration(seconds: 2),
      ];
      addTearDown(
        () => RemoteCompositionHistoryBackup.followUpRestoreDelays = saved,
      );

      final aliceStore = _MemoryStore();
      final alicePhone = await register(
        'alice_phone',
        '+8801733333333',
        aliceStore,
      );
      await alicePhone.setAccountPassword(newPassword: 'correct horse battery');
      final bobStore = _MemoryStore();
      final bob = await register('bob', '+8801744444444', bobStore);

      final phoneMs = alicePhone.messagingService;
      final convId = phoneMs.createDirectConversation(
        peerAccountId: bobStore.values['account_id']!,
      );
      await phoneMs.sendText(
        conversationId: convId,
        plaintext: 'said before the PC existed',
        recipientDeviceIds: phoneMs.recipientDeviceIdsForConversation(convId),
      );
      await sync(alicePhone);
      await sync(bob);

      final alicePc = rootFor('alice_pc', _MemoryStore());
      addTearDown(alicePc.dispose);
      await alicePc.initialize();
      await alicePc.signInWithPassword(
        lookup: await alicePc.lookupPasswordAccount('+8801733333333'),
        password: 'correct horse battery',
      );

      // The phone hears about the sign-in (socket, or its next sync) and
      // backs up; the PC's follow-up restore then brings the chat in.
      await sync(alicePhone);
      var pcTexts = <String>[];
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        pcTexts = await texts(alicePc, convId);
        if (pcTexts.contains('said before the PC existed')) break;
      }
      expect(pcTexts, contains('said before the PC existed'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
