// Password sign-in: one account per phone number, reachable from any number
// of devices with the password, without an SMS code per sign-in.

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'test_registration.dart';

class _Res {
  _Res(this.statusCode, this.body);
  final int statusCode;
  final String body;
  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;
}

const _kdf = {
  'alg': 'argon2id',
  'memory_kib': 19456,
  'iterations': 2,
  'parallelism': 1,
  'length': 64,
};

String _key(int fill) => testBase64Url(List<int>.filled(32, fill));

void main() {
  late BackendServer server;
  late HttpClient client;
  late int port;
  var now = DateTime.utc(2026, 9, 27, 12);

  setUp(() async {
    now = DateTime.utc(2026, 9, 27, 12);
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'password_login_test_secret_at_least_32_bytes',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
      now: () => now,
    );
    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  Future<_Res> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final request = await client.open(method, '127.0.0.1', port, path);
    request.headers.contentType = ContentType.json;
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    return _Res(
      response.statusCode,
      await response.transform(utf8.decoder).join(),
    );
  }

  /// Registers `alice` (phone hash `alice_phone`) and returns her first
  /// device's access token.
  Future<String> registerAlice() async {
    final material = await registerTestAccount(
      client: client,
      host: '127.0.0.1',
      port: port,
      db: server.db,
      accountId: 'alice',
      username: 'alice_phone',
      deviceId: 'alice_phone_1',
      deviceName: 'Alice Phone',
    );
    final login = await loginTestAccount(
      client: client,
      host: '127.0.0.1',
      port: port,
      accountId: 'alice',
      deviceId: 'alice_phone_1',
      deviceSigningKeyPair: material.deviceSigningKeyPair,
    );
    return login['token'] as String;
  }

  Future<_Res> setPassword(
    String token, {
    required String authKey,
    String wrapped = 'wrapped-identity-v1',
    String? currentAuthKey,
  }) => send(
    'POST',
    '/api/v1/accounts/password',
    token: token,
    body: {
      'kdf_params': _kdf,
      'kdf_salt': testBase64Url(List<int>.filled(16, 7)),
      'auth_key': authKey,
      'wrapped_identity_key': wrapped,
      'current_auth_key': ?currentAuthKey,
    },
  );

  Future<_Res> passwordLogin(
    String authKey, {
    String deviceId = 'alice_tab',
  }) async {
    final signing = await crypto.Ed25519().newKeyPair();
    final agreement = await crypto.X25519().newKeyPair();
    final signingPub = testBase64Url((await signing.extractPublicKey()).bytes);
    final agreementPub = testBase64Url(
      (await agreement.extractPublicKey()).bytes,
    );
    final transcript = [
      'helix.remote.password-login.v1',
      'alice_phone',
      deviceId,
      signingPub,
      agreementPub,
      'Alice Tablet',
    ].join('\n');
    final signature = await crypto.Ed25519().sign(
      utf8.encode(transcript),
      keyPair: signing,
    );
    return send(
      'POST',
      '/api/v1/accounts/password/login',
      body: {
        'phone_hash': 'alice_phone',
        'auth_key': authKey,
        'device_id': deviceId,
        'device_name': 'Alice Tablet',
        'device_signing_public_key': signingPub,
        'device_agreement_public_key': agreementPub,
        'device_signature': testBase64Url(signature.bytes),
      },
    );
  }

  test('params say whether the number has an account and a password', () async {
    final unknown = await send(
      'POST',
      '/api/v1/accounts/password/params',
      body: {'phone_hash': 'nobody_phone'},
    );
    expect(unknown.json, {'account_exists': false, 'has_password': false});

    final token = await registerAlice();
    final noPassword = await send(
      'POST',
      '/api/v1/accounts/password/params',
      body: {'phone_hash': 'alice_phone'},
    );
    expect(noPassword.json['account_exists'], isTrue);
    expect(noPassword.json['has_password'], isFalse);

    expect((await setPassword(token, authKey: _key(1))).statusCode, 200);
    final withPassword = await send(
      'POST',
      '/api/v1/accounts/password/params',
      body: {'phone_hash': 'alice_phone'},
    );
    expect(withPassword.json['has_password'], isTrue);
    expect(withPassword.json['kdf_params'], _kdf);
    expect(withPassword.json['kdf_salt'], isNotEmpty);

    final status = await send('GET', '/api/v1/accounts/password', token: token);
    expect(status.json['has_password'], isTrue);
  });

  test('a new device signs in with the password next to the old one', () async {
    final token = await registerAlice();
    await setPassword(token, authKey: _key(1), wrapped: 'wrapped-blob');

    final login = await passwordLogin(_key(1));
    expect(login.statusCode, 200, reason: login.body);
    expect(login.json['account_id'], 'alice');
    expect(login.json['wrapped_identity_key'], 'wrapped-blob');
    expect(login.json['account_identity_public_key'], isNotEmpty);
    expect(login.json['token'], isNotEmpty);
    expect(login.json['refresh_token'], isNotEmpty);

    // Nobody was signed out.
    expect(server.db.isDeviceActive('alice', 'alice_phone_1'), isTrue);
    expect(server.db.isDeviceActive('alice', 'alice_tab'), isTrue);

    // The phone is told - durably, so it sees it even if it was offline -
    // and a push is queued for it, never for the tablet itself.
    final phoneEvents = server.db
        .getDeviceEvents('alice_phone_1', 0)
        .where((e) => e['event_type'] == 'device_linked')
        .toList();
    expect(phoneEvents, hasLength(1));
    final alert = jsonDecode(phoneEvents.single['payload'] as String) as Map;
    expect(alert['device_id'], 'alice_tab');
    expect(alert['device_name'], 'Alice Tablet');
    expect(alert['method'], 'password');
    final pushes = server.db
        .getPendingOutbox()
        .map((o) => jsonDecode(o['payload'] as String) as Map)
        .where((p) => p['notification_type'] == 'new_sign_in')
        .toList();
    expect(pushes.map((p) => p['recipient_device_id']), ['alice_phone_1']);
    expect(pushes.single.containsKey('device_name'), isFalse);

    final devices = await send(
      'GET',
      '/api/v1/accounts/devices',
      token: login.json['token'] as String,
    );
    expect(devices.statusCode, 200);
    expect((devices.json['devices'] as List), hasLength(2));
  });

  test('wrong passwords are refused and then locked out', () async {
    final token = await registerAlice();
    await setPassword(token, authKey: _key(1));

    for (var i = 0; i < 4; i++) {
      final wrong = await passwordLogin(_key(9), deviceId: 'try_$i');
      expect(wrong.statusCode, 403);
      expect(wrong.json['code'], 'password_incorrect');
    }
    final fifth = await passwordLogin(_key(9), deviceId: 'try_4');
    expect(fifth.statusCode, 403);

    // Locked: even the right password waits.
    final locked = await passwordLogin(_key(1), deviceId: 'try_5');
    expect(locked.statusCode, 429);
    expect(locked.json['code'], 'password_locked');

    now = now.add(const Duration(minutes: 16));
    final afterLock = await passwordLogin(_key(1), deviceId: 'try_6');
    expect(afterLock.statusCode, 200, reason: afterLock.body);
  });

  test('verify checks the password without adding a device', () async {
    final token = await registerAlice();
    await setPassword(token, authKey: _key(1));

    Future<_Res> verify(String authKey) => send(
      'POST',
      '/api/v1/accounts/password/verify',
      body: {'phone_hash': 'alice_phone', 'auth_key': authKey},
    );
    expect((await verify(_key(1))).json, {'valid': true});
    final wrong = await verify(_key(2));
    expect(wrong.statusCode, 403);
    expect(wrong.json['code'], 'password_incorrect');
    expect(server.db.getActiveDevices('alice'), hasLength(1));
  });

  test('an unknown number looks exactly like a wrong password', () async {
    final login = await send(
      'POST',
      '/api/v1/accounts/password/login',
      body: {
        'phone_hash': 'nobody_phone',
        'auth_key': _key(1),
        'device_id': 'd1',
        'device_name': 'X',
        'device_signing_public_key': _key(2),
        'device_agreement_public_key': _key(3),
        'device_signature': 'sig',
      },
    );
    expect(login.statusCode, 403);
    expect(login.json['code'], 'password_incorrect');
  });

  test('changing the password needs the current one', () async {
    final token = await registerAlice();
    await setPassword(token, authKey: _key(1));

    final noProof = await setPassword(token, authKey: _key(2));
    expect(noProof.statusCode, 403);

    final wrongProof = await setPassword(
      token,
      authKey: _key(2),
      currentAuthKey: _key(5),
    );
    expect(wrongProof.statusCode, 403);
    expect(wrongProof.json['code'], 'password_incorrect');

    final changed = await setPassword(
      token,
      authKey: _key(2),
      currentAuthKey: _key(1),
    );
    expect(changed.statusCode, 200, reason: changed.body);
    expect((await passwordLogin(_key(1))).statusCode, 403);
    expect((await passwordLogin(_key(2), deviceId: 'd2')).statusCode, 200);
  });

  test('set-password refuses a weak key-stretching setting', () async {
    final token = await registerAlice();
    final weak = await send(
      'POST',
      '/api/v1/accounts/password',
      token: token,
      body: {
        'kdf_params': {..._kdf, 'memory_kib': 1024},
        'kdf_salt': testBase64Url(List<int>.filled(16, 7)),
        'auth_key': _key(1),
        'wrapped_identity_key': 'w',
      },
    );
    expect(weak.statusCode, 400);
  });

  test('each device can store and read the account history backup', () async {
    final token = await registerAlice();
    await setPassword(token, authKey: _key(1));
    final tablet = await passwordLogin(_key(1));

    expect(
      (await send('GET', '/api/v1/backups/history', token: token)).statusCode,
      404,
    );
    final put = await send(
      'PUT',
      '/api/v1/backups/history',
      token: token,
      body: {'blob': 'encrypted-history-1'},
    );
    expect(put.statusCode, 200, reason: put.body);

    // The tablet, signed in with the password, reads what the phone wrote.
    final got = await send(
      'GET',
      '/api/v1/backups/history',
      token: tablet.json['token'] as String,
    );
    expect(got.json['blob'], 'encrypted-history-1');

    // A new identity (SMS takeover) can never decrypt it: it is dropped.
    server.db.updateAccountIdentityKey('alice', _key(4));
    expect(server.db.getHistoryBackup('alice'), isNull);
  });

  test(
    'rotating the identity key (SMS takeover) clears the password',
    () async {
      final token = await registerAlice();
      await setPassword(token, authKey: _key(1));
      expect(server.db.accountHasPassword('alice'), isTrue);

      server.db.updateAccountIdentityKey('alice', _key(4));
      expect(server.db.accountHasPassword('alice'), isFalse);
    },
  );

  test('sign out all other devices keeps only this one', () async {
    final token = await registerAlice();
    await setPassword(token, authKey: _key(1));
    final tablet = await passwordLogin(_key(1));
    expect(tablet.statusCode, 200);

    final result = await send(
      'POST',
      '/api/v1/accounts/devices/revoke-others',
      token: token,
    );
    expect(result.statusCode, 200);
    expect(result.json['revoked_count'], 1);
    expect(server.db.isDeviceActive('alice', 'alice_phone_1'), isTrue);
    expect(server.db.isDeviceActive('alice', 'alice_tab'), isFalse);

    final tabletRefresh = await send(
      'POST',
      '/api/v1/accounts/refresh',
      body: {'refresh_token': tablet.json['refresh_token']},
    );
    expect(tabletRefresh.statusCode, 403);
    expect(tabletRefresh.json['code'], 'device_revoked');
  });
}
