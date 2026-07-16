import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'test_registration.dart';

void main() {
  late BackendServer server;
  late int port;
  late HttpClient client;
  final ed25519 = crypto.Ed25519();

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'phase17_test_jwt_secret',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
    );
    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  test(
    'P17 device linking requires out-of-band approval before login',
    () async {
      final alice1 = await _registerAndLogin(
        client,
        port,
        ed25519,
        accountId: 'alice',
        username: 'alice_user',
        deviceId: 'alice_phone',
        deviceName: 'Alice Phone',
      );
      final alice2KeyPair = await ed25519.newKeyPair();
      final alice2Public = await alice2KeyPair.extractPublicKey();
      final aliceLaptopMaterial = await createTestRegistrationMaterial(
        accountId: 'alice',
        username: 'alice_user',
        deviceId: 'alice_laptop',
        deviceName: 'Alice Laptop',
      );

      final directRegister =
          await _postJson(client, port, '/api/v1/accounts/register', {
            ...registrationBody(
              accountId: 'alice',
              username: 'alice_user',
              deviceId: 'alice_laptop',
              deviceName: 'Alice Laptop',
              material: aliceLaptopMaterial,
            ),
          });
      expect(directRegister.statusCode, equals(403));

      final requestLink = await _postJson(
        client,
        port,
        '/api/v1/accounts/devices/link/request',
        {
          'device_id': 'alice_laptop',
          'device_public_key': _base64Url(alice2Public.bytes),
          'device_name': 'Alice Laptop',
        },
        token: alice1.accessToken,
      );
      expect(requestLink.statusCode, equals(200));
      final requestBody = jsonDecode(requestLink.body) as Map<String, dynamic>;
      final linkId = requestBody['link_id'] as String;
      final verificationCode = requestBody['verification_code'] as String;
      expect(verificationCode, hasLength(6));

      final wrongVerify = await _postJson(
        client,
        port,
        '/api/v1/accounts/devices/link/verify',
        {'link_id': linkId, 'verification_code': '000000'},
        token: alice1.accessToken,
      );
      expect(wrongVerify.statusCode, equals(403));

      final verify = await _postJson(
        client,
        port,
        '/api/v1/accounts/devices/link/verify',
        {'link_id': linkId, 'verification_code': verificationCode},
        token: alice1.accessToken,
      );
      expect(verify.statusCode, equals(200));

      final complete = await _postJson(
        client,
        port,
        '/api/v1/accounts/devices/link/complete',
        {'link_id': linkId},
        token: alice1.accessToken,
      );
      expect(complete.statusCode, equals(200));

      final devices = await _getJson(
        client,
        port,
        '/api/v1/accounts/devices',
        token: alice1.accessToken,
      );
      final deviceList =
          (jsonDecode(devices.body) as Map<String, dynamic>)['devices'] as List;
      expect(
        deviceList.map((d) => (d as Map<String, dynamic>)['device_id']),
        containsAll(['alice_phone', 'alice_laptop']),
      );

      final alice2Token = await _login(
        client,
        port,
        ed25519,
        accountId: 'alice',
        deviceId: 'alice_laptop',
        keyPair: alice2KeyPair,
      );
      expect(alice2Token.accessToken, isNotEmpty);

      final revoke = await _postJson(
        client,
        port,
        '/api/v1/accounts/devices/revoke',
        {'device_id': 'alice_laptop'},
        token: alice1.accessToken,
      );
      expect(revoke.statusCode, equals(200));
      expect(
        server.db.getDeviceRevocation('alice', 'alice_laptop')!['reason'],
        equals('USER_REVOKED'),
      );

      final revokedAccess = await _getJson(
        client,
        port,
        '/api/v1/accounts/devices',
        token: alice2Token.accessToken,
      );
      expect(revokedAccess.statusCode, equals(403));

      final revokedRefresh = await _postJson(
        client,
        port,
        '/api/v1/accounts/refresh',
        {'refresh_token': alice2Token.refreshToken},
      );
      expect(revokedRefresh.statusCode, equals(403));
    },
  );

  test(
    'F1 new-device onboarding links fresh keys only after trusted approval',
    () async {
      final alice1 = await _registerAndLogin(
        client,
        port,
        ed25519,
        accountId: 'alice_f1',
        username: 'alice_f1_user',
        deviceId: 'alice_f1_phone',
        deviceName: 'Alice Phone',
      );
      final newMaterial = await createTestRegistrationMaterial(
        accountId: 'alice_f1',
        username: 'alice_f1_user',
        deviceId: 'alice_f1_laptop',
        deviceName: 'Alice Laptop',
      );

      final preApprovalPrekeys = await _postJson(
        client,
        port,
        '/api/v1/prekeys/publish',
        {
          'signed_prekey_id': 1,
          'signed_prekey': 'spk_before_approval',
          'signature': 'sig_before_approval',
          'one_time_prekeys': [
            {'key_id': 1, 'public_key': 'otk_before_approval'},
          ],
        },
      );
      expect(preApprovalPrekeys.statusCode, equals(401));

      final requestLink = await _postJson(
        client,
        port,
        '/api/v1/accounts/devices/link/request-new',
        {
          'account_id': 'alice_f1',
          'device_id': 'alice_f1_laptop',
          'device_name': 'Alice Laptop',
          'device_signing_public_key': newMaterial.deviceSigningPublicKey,
          'device_agreement_public_key': newMaterial.deviceAgreementPublicKey,
        },
      );
      expect(requestLink.statusCode, equals(200));
      final requestBody = jsonDecode(requestLink.body) as Map<String, dynamic>;
      expect(requestBody['qr_payload'], isA<String>());
      final linkId = requestBody['link_id'] as String;
      final verificationCode = requestBody['verification_code'] as String;

      final wrongApproval = await _postJson(
        client,
        port,
        '/api/v1/accounts/devices/link/verify',
        {'link_id': linkId, 'verification_code': '000000'},
        token: alice1.accessToken,
      );
      expect(wrongApproval.statusCode, equals(403));

      final approve = await _postJson(
        client,
        port,
        '/api/v1/accounts/devices/link/verify',
        {'link_id': linkId, 'verification_code': verificationCode},
        token: alice1.accessToken,
      );
      expect(approve.statusCode, equals(200));
      final approveBody = jsonDecode(approve.body) as Map<String, dynamic>;
      final transcript = approveBody['approval_transcript'] as String;
      expect(approveBody['approval_transcript_hash'], isA<String>());

      final badComplete = await _postJson(
        client,
        port,
        '/api/v1/accounts/devices/link/complete-new',
        {'link_id': linkId, 'signature': 'bad_signature'},
      );
      expect(badComplete.statusCode, equals(403));

      final signature = await ed25519.sign(
        utf8.encode(transcript),
        keyPair: newMaterial.deviceSigningKeyPair,
      );
      final complete = await _postJson(
        client,
        port,
        '/api/v1/accounts/devices/link/complete-new',
        {'link_id': linkId, 'signature': _base64Url(signature.bytes)},
      );
      expect(complete.statusCode, equals(200));
      final completeBody = jsonDecode(complete.body) as Map<String, dynamic>;
      final alice2Access = completeBody['token'] as String;
      final alice2Refresh = completeBody['refresh_token'] as String;
      expect(alice2Access, isNotEmpty);
      expect(alice2Refresh, isNotEmpty);

      final replay = await _postJson(
        client,
        port,
        '/api/v1/accounts/devices/link/complete-new',
        {'link_id': linkId, 'signature': _base64Url(signature.bytes)},
      );
      expect(replay.statusCode, equals(403));

      final publishPrekeys = await _postJson(
        client,
        port,
        '/api/v1/prekeys/publish',
        {
          'signed_prekey_id': 1,
          'signed_prekey': 'spk_after_approval',
          'signature': 'sig_after_approval',
          'one_time_prekeys': [
            {'key_id': 1, 'public_key': 'otk_after_approval'},
          ],
        },
        token: alice2Access,
      );
      expect(publishPrekeys.statusCode, equals(200));

      final devices = await _getJson(
        client,
        port,
        '/api/v1/accounts/devices',
        token: alice2Access,
      );
      expect(devices.statusCode, equals(200));
      final deviceList =
          (jsonDecode(devices.body) as Map<String, dynamic>)['devices'] as List;
      expect(
        deviceList.map((d) => (d as Map<String, dynamic>)['device_id']),
        containsAll(['alice_f1_phone', 'alice_f1_laptop']),
      );

      final revoke = await _postJson(
        client,
        port,
        '/api/v1/accounts/devices/revoke',
        {'device_id': 'alice_f1_laptop'},
        token: alice1.accessToken,
      );
      expect(revoke.statusCode, equals(200));
      expect(
        server.db.getPrekeyBundleForDevice('alice_f1', 'alice_f1_laptop'),
        isNull,
      );

      final revokedAccess = await _getJson(
        client,
        port,
        '/api/v1/accounts/devices',
        token: alice2Access,
      );
      expect(revokedAccess.statusCode, equals(403));
      final revokedRefresh = await _postJson(
        client,
        port,
        '/api/v1/accounts/refresh',
        {'refresh_token': alice2Refresh},
      );
      expect(revokedRefresh.statusCode, equals(403));
    },
  );

  test(
    'P5 final active device cannot be revoked without recovery path',
    () async {
      final alice = await _registerAndLogin(
        client,
        port,
        ed25519,
        accountId: 'alice_final_device',
        username: 'alice_final_device_user',
        deviceId: 'alice_phone',
        deviceName: 'Alice Phone',
      );

      final finalRevoke = await _postJson(
        client,
        port,
        '/api/v1/accounts/devices/revoke',
        {'device_id': 'alice_phone'},
        token: alice.accessToken,
      );
      expect(finalRevoke.statusCode, equals(403));
      expect(
        server.db.isDeviceActive('alice_final_device', 'alice_phone'),
        isTrue,
      );

      await _linkDevice(
        client,
        port,
        ed25519,
        existingToken: alice.accessToken,
        accountId: 'alice_final_device',
        deviceId: 'alice_tablet',
        deviceName: 'Alice Tablet',
      );

      final allowed = await _postJson(
        client,
        port,
        '/api/v1/accounts/devices/revoke',
        {'device_id': 'alice_tablet'},
        token: alice.accessToken,
      );
      expect(allowed.statusCode, equals(200));
      expect(
        server.db.isDeviceActive('alice_final_device', 'alice_tablet'),
        isFalse,
      );
    },
  );

  test(
    'P17 per-device message fan-out requires each active target envelope',
    () async {
      final alice1 = await _registerAndLogin(
        client,
        port,
        ed25519,
        accountId: 'alice',
        username: 'alice_fanout',
        deviceId: 'alice_phone',
        deviceName: 'Alice Phone',
      );
      final alice2 = await _linkDevice(
        client,
        port,
        ed25519,
        existingToken: alice1.accessToken,
        accountId: 'alice',
        deviceId: 'alice_tablet',
        deviceName: 'Alice Tablet',
      );
      final bob = await _registerAndLogin(
        client,
        port,
        ed25519,
        accountId: 'bob',
        username: 'bob_fanout',
        deviceId: 'bob_phone',
        deviceName: 'Bob Phone',
      );
      await _linkDevice(
        client,
        port,
        ed25519,
        existingToken: bob.accessToken,
        accountId: 'bob',
        deviceId: 'bob_laptop',
        deviceName: 'Bob Laptop',
      );

      final create = await _postJson(
        client,
        port,
        '/api/v1/messages/conversations/create',
        {
          'conversation_id': 'conv_fanout',
          'type': 'DIRECT',
          'members': ['alice', 'bob'],
        },
        token: alice1.accessToken,
      );
      expect(create.statusCode, equals(200));

      final missing = await _postJson(client, port, '/api/v1/messages/send', {
        'message_id': 'msg_missing_target',
        'conversation_id': 'conv_fanout',
        'envelopes': [
          {
            'recipient_device_id': 'bob_phone',
            'ciphertext': 'ct_for_bob_phone',
          },
        ],
      }, token: alice1.accessToken);
      expect(missing.statusCode, equals(400));

      final plaintext = await _postJson(client, port, '/api/v1/messages/send', {
        'message_id': 'msg_plaintext_rejected',
        'conversation_id': 'conv_fanout',
        'envelopes': [
          {
            'recipient_device_id': 'bob_phone',
            'ciphertext': 'ct_for_bob_phone',
            'plaintext': 'do not store this',
          },
          {
            'recipient_device_id': 'bob_laptop',
            'ciphertext': 'ct_for_bob_laptop',
          },
          {
            'recipient_device_id': 'alice_tablet',
            'ciphertext': 'ct_for_alice_tablet',
          },
        ],
      }, token: alice1.accessToken);
      expect(plaintext.statusCode, equals(400));

      final sent = await _postJson(client, port, '/api/v1/messages/send', {
        'message_id': 'msg_fanout_ok',
        'conversation_id': 'conv_fanout',
        'envelopes': [
          {
            'recipient_device_id': 'bob_phone',
            'ciphertext': 'ct_for_bob_phone',
          },
          {
            'recipient_device_id': 'bob_laptop',
            'ciphertext': 'ct_for_bob_laptop',
          },
          {
            'recipient_device_id': 'alice_tablet',
            'ciphertext': 'ct_for_alice_tablet',
          },
        ],
      }, token: alice1.accessToken);
      expect(sent.statusCode, equals(200));
      expect(
        (jsonDecode(sent.body) as Map<String, dynamic>)['envelopes_count'],
        equals(3),
      );
      expect(
        server.db
            .getMessagesForDevice('bob_phone', 'conv_fanout', 0)
            .single['ciphertext'],
        equals('ct_for_bob_phone'),
      );
      expect(
        server.db
            .getMessagesForDevice('bob_laptop', 'conv_fanout', 0)
            .single['ciphertext'],
        equals('ct_for_bob_laptop'),
      );
      expect(
        server.db
            .getMessagesForDevice(alice2.deviceId, 'conv_fanout', 0)
            .single['ciphertext'],
        equals('ct_for_alice_tablet'),
      );
    },
  );

  test(
    'P17 backups are opaque, versioned, owned, and deletion-aware',
    () async {
      final alice = await _registerAndLogin(
        client,
        port,
        ed25519,
        accountId: 'alice',
        username: 'alice_backup',
        deviceId: 'alice_phone',
        deviceName: 'Alice Phone',
      );

      final rejected = await _postJson(client, port, '/api/v1/backups/', {
        'backup_id': 'backup_1',
        'version': 1,
        'kdf': 'PBKDF2-HMAC-SHA256-100000',
        'salt': 'salt_b64',
        'backup_data': 'opaque_ciphertext',
        'backup_key': 'server must never receive this',
      }, token: alice.accessToken);
      expect(rejected.statusCode, equals(400));

      final upload = await _postJson(client, port, '/api/v1/backups/', {
        'backup_id': 'backup_1',
        'version': 1,
        'kdf': 'PBKDF2-HMAC-SHA256-100000',
        'salt': 'salt_b64',
        'backup_key_hint': 'phrase stored by user',
        'backup_data': 'opaque_ciphertext',
      }, token: alice.accessToken);
      expect(upload.statusCode, equals(200));

      final download = await _getJson(
        client,
        port,
        '/api/v1/backups/',
        token: alice.accessToken,
      );
      final downloaded = jsonDecode(download.body) as Map<String, dynamic>;
      expect(downloaded['backup_data'], equals('opaque_ciphertext'));
      expect(downloaded['version'], equals(1));
      expect(downloaded.containsKey('backup_key'), isFalse);
      expect(downloaded['requires_reupload'], isFalse);

      await _postJson(
        client,
        port,
        '/api/v1/messages/conversations/create',
        {
          'conversation_id': 'conv_backup_delete',
          'type': 'DIRECT',
          'members': ['alice'],
        },
        token: alice.accessToken,
      );
      await _postJson(client, port, '/api/v1/messages/send', {
        'message_id': 'msg_backup_delete',
        'conversation_id': 'conv_backup_delete',
        'envelopes': [
          {
            'recipient_device_id': 'alice_phone',
            'ciphertext': 'ct_for_sender_archive',
          },
        ],
      }, token: alice.accessToken);
      final delete = await _postJson(client, port, '/api/v1/messages/delete', {
        'message_id': 'msg_backup_delete',
      }, token: alice.accessToken);
      expect(delete.statusCode, equals(200));

      final afterDelete = await _getJson(
        client,
        port,
        '/api/v1/backups/',
        token: alice.accessToken,
      );
      final marked = jsonDecode(afterDelete.body) as Map<String, dynamic>;
      expect(marked['backup_data'], equals('opaque_ciphertext'));
      expect(marked['requires_reupload'], isTrue);
      expect(marked['deletion_watermark'], isA<int>());
    },
  );

  test(
    'P17 lost-device response revokes device and purges its mailbox',
    () async {
      final alice = await _registerAndLogin(
        client,
        port,
        ed25519,
        accountId: 'alice',
        username: 'alice_lost',
        deviceId: 'alice_phone',
        deviceName: 'Alice Phone',
      );
      await _linkDevice(
        client,
        port,
        ed25519,
        existingToken: alice.accessToken,
        accountId: 'alice',
        deviceId: 'alice_lost_laptop',
        deviceName: 'Alice Lost Laptop',
      );

      server.db.createConversation('conv_lost', 'DIRECT', 'Lost', ['alice']);
      server.db.saveMessage(
        messageId: 'msg_for_lost_device',
        conversationId: 'conv_lost',
        senderAccountId: 'alice',
        senderDeviceId: 'alice_phone',
        recipientDeviceId: 'alice_lost_laptop',
        ciphertext: 'ct_waiting_for_lost_device',
      );
      expect(
        server.db.getMessagesForDevice('alice_lost_laptop', 'conv_lost', 0),
        isNotEmpty,
      );

      final lost = await _postJson(
        client,
        port,
        '/api/v1/accounts/devices/lost-device',
        {'device_id': 'alice_lost_laptop'},
        token: alice.accessToken,
      );
      expect(lost.statusCode, equals(200));
      expect(
        server.db.getMessagesForDevice('alice_lost_laptop', 'conv_lost', 0),
        isEmpty,
      );
      expect(
        server.db.getDeviceRevocation('alice', 'alice_lost_laptop')!['reason'],
        equals('LOST_DEVICE'),
      );
    },
  );
}

class _AuthTokens {
  const _AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.deviceId,
  });

  final String accessToken;
  final String refreshToken;
  final String deviceId;
}

class _Response {
  const _Response(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

Future<_AuthTokens> _registerAndLogin(
  HttpClient client,
  int port,
  crypto.Ed25519 ed25519, {
  required String accountId,
  required String username,
  required String deviceId,
  required String deviceName,
}) async {
  final material = await createTestRegistrationMaterial(
    accountId: accountId,
    username: username,
    deviceId: deviceId,
    deviceName: deviceName,
  );
  final register = await _postJson(client, port, '/api/v1/accounts/register', {
    ...registrationBody(
      accountId: accountId,
      username: username,
      deviceId: deviceId,
      deviceName: deviceName,
      material: material,
    ),
  });
  expect(register.statusCode, equals(200));
  return _login(
    client,
    port,
    ed25519,
    accountId: accountId,
    deviceId: deviceId,
    keyPair: material.deviceSigningKeyPair,
  );
}

Future<_AuthTokens> _login(
  HttpClient client,
  int port,
  crypto.Ed25519 ed25519, {
  required String accountId,
  required String deviceId,
  required crypto.SimpleKeyPair keyPair,
}) async {
  final challengeRes = await _getJson(
    client,
    port,
    '/api/v1/accounts/challenge?account_id=$accountId&device_id=$deviceId',
  );
  expect(challengeRes.statusCode, equals(200));
  final challenge =
      (jsonDecode(challengeRes.body) as Map<String, dynamic>)['challenge']
          as String;
  final signature = await ed25519.sign(
    utf8.encode(challenge),
    keyPair: keyPair,
  );
  final login = await _postJson(client, port, '/api/v1/accounts/login', {
    'account_id': accountId,
    'device_id': deviceId,
    'signature': _base64Url(signature.bytes),
  });
  expect(login.statusCode, equals(200));
  final body = jsonDecode(login.body) as Map<String, dynamic>;
  return _AuthTokens(
    accessToken: body['token'] as String,
    refreshToken: body['refresh_token'] as String,
    deviceId: deviceId,
  );
}

Future<_AuthTokens> _linkDevice(
  HttpClient client,
  int port,
  crypto.Ed25519 ed25519, {
  required String existingToken,
  required String accountId,
  required String deviceId,
  required String deviceName,
}) async {
  final keyPair = await ed25519.newKeyPair();
  final publicKey = await keyPair.extractPublicKey();
  final requestLink =
      await _postJson(client, port, '/api/v1/accounts/devices/link/request', {
        'device_id': deviceId,
        'device_public_key': _base64Url(publicKey.bytes),
        'device_name': deviceName,
      }, token: existingToken);
  expect(requestLink.statusCode, equals(200));
  final requestBody = jsonDecode(requestLink.body) as Map<String, dynamic>;
  final linkId = requestBody['link_id'] as String;
  final verificationCode = requestBody['verification_code'] as String;
  final verify = await _postJson(
    client,
    port,
    '/api/v1/accounts/devices/link/verify',
    {'link_id': linkId, 'verification_code': verificationCode},
    token: existingToken,
  );
  expect(verify.statusCode, equals(200));
  final complete = await _postJson(
    client,
    port,
    '/api/v1/accounts/devices/link/complete',
    {'link_id': linkId},
    token: existingToken,
  );
  expect(complete.statusCode, equals(200));
  return _login(
    client,
    port,
    ed25519,
    accountId: accountId,
    deviceId: deviceId,
    keyPair: keyPair,
  );
}

Future<_Response> _postJson(
  HttpClient client,
  int port,
  String path,
  Map<String, dynamic> data, {
  String? token,
}) async {
  final request = await client.post('127.0.0.1', port, path);
  request.headers.contentType = ContentType.json;
  if (token != null) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  request.write(jsonEncode(data));
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  return _Response(response.statusCode, body);
}

Future<_Response> _getJson(
  HttpClient client,
  int port,
  String path, {
  String? token,
}) async {
  final request = await client.get('127.0.0.1', port, path);
  if (token != null) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  return _Response(response.statusCode, body);
}

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');
