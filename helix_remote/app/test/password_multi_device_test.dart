// The whole point of password sign-in: a second device, knowing only the
// phone number and password, becomes the *same* account - it unlocks the
// account identity key and publishes prekeys that verify against it - while
// the first device stays signed in.

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/history_backup_codec.dart';
import 'package:helix_remote/app/phone_hashing.dart';
import 'package:helix_remote/app/remote_config.dart';

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// Stands in for the server's password endpoints and records what a device
/// publishes. Everything else answers an empty success.
class _FakeServer {
  _FakeServer._(this._server);
  final HttpServer _server;
  final salt = base64.encode(List<int>.filled(32, 3));
  Map<String, dynamic>? password;
  String? identityPublicKey;
  Map<String, dynamic>? publishedPrekeys;
  String? historyBlob;

  int get port => _server.port;

  static Future<_FakeServer> start() async {
    final fake = _FakeServer._(await HttpServer.bind('127.0.0.1', 0));
    fake._server.listen(fake._handle);
    return fake;
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    final raw = await utf8.decoder.bind(request).join();
    final body = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
    Object reply = <String, dynamic>{};
    var status = 200;
    if (path.endsWith('/contacts/discovery-salt')) {
      reply = {'salt': salt};
    } else if (path.endsWith('/accounts/password') &&
        request.method == 'POST') {
      password = body as Map<String, dynamic>;
    } else if (path.endsWith('/accounts/password/params')) {
      final p = password;
      reply = {
        'account_exists': true,
        'has_password': p != null,
        if (p != null) 'kdf_params': p['kdf_params'],
        if (p != null) 'kdf_salt': p['kdf_salt'],
      };
    } else if (path.endsWith('/accounts/password/login')) {
      final login = body as Map<String, dynamic>;
      if (login['auth_key'] != password?['auth_key']) {
        status = 403;
        reply = {'error': 'Wrong', 'code': 'password_incorrect'};
      } else {
        reply = {
          'account_id': 'acc_multi',
          'device_id': login['device_id'],
          'account_identity_public_key': identityPublicKey,
          'wrapped_identity_key': password!['wrapped_identity_key'],
          'display_name': 'Alice',
          'token': 'tablet-access',
          'refresh_token': 'tablet-refresh',
        };
      }
    } else if (path.endsWith('/prekeys/publish')) {
      publishedPrekeys = body as Map<String, dynamic>;
    } else if (path.endsWith('/backups/history')) {
      if (request.method == 'PUT') {
        historyBlob = (body as Map<String, dynamic>)['blob'] as String;
      } else if (historyBlob == null) {
        status = 404;
      } else {
        reply = {'blob': historyBlob};
      }
    } else if (path.endsWith('/accounts/refresh')) {
      reply = {'token': 'access', 'refresh_token': 'refresh'};
    }
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(reply));
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The binding swaps in an HttpClient that answers 400 to everything; these
  // tests talk to a real local server.
  HttpOverrides.global = null;
  FlutterSecureStorage.setMockInitialValues({});
  late _FakeServer server;
  late Directory dir;

  setUp(() async {
    server = await _FakeServer.start();
    dir = Directory.systemTemp.createTempSync('password_multi_device_');
  });

  tearDown(() async {
    await server.close();
    dir.deleteSync(recursive: true);
  });

  RemoteCompositionRoot rootFor(String name, KeyValueStore store) {
    final path = '${dir.path}/$name';
    Directory(path).createSync();
    return RemoteCompositionRoot.withConfig(
      RemoteProductConfig(
        displayName: 'Helix Remote',
        packageId: 'com.helix.remote',
        secureStoragePrefix: 'helix_remote_v1_',
        methodChannelNamespace: 'com.helix.remote',
        logNamespace: 'helix_remote',
        databaseDirectory: path,
      ),
      devConfig: RemoteDevelopmentConfig(
        profile: RemoteRuntimeProfile.localWindows,
        restBaseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        webSocketUri: Uri.parse('ws://127.0.0.1:9/api/v1/ws'),
        allowInsecureTransport: true,
        backendHostMode: 'same-pc',
        requestTimeoutMs: 2000,
        reconnectPolicy: const ReconnectPolicy(),
        databaseDirectory: path,
        attachmentCacheDir: '$path/attachments_cache',
        diagnosticLevel: DiagnosticLevel.info,
      ),
      keyValueStore: store,
    );
  }

  test(
    'a second device signs in as the same account with the password',
    () async {
      // The phone: already signed in, holding the account identity key.
      final identity = await Ed25519().newKeyPair();
      final identityPublic = _b64((await identity.extractPublicKey()).bytes);
      server.identityPublicKey = identityPublic;
      final phoneStore = _MemoryStore()
        ..values.addAll({
          'account_id': 'acc_multi',
          'phone_number': '+8801700000000',
          'identity_public_key': identityPublic,
          'identity_private_key': _b64(await identity.extractPrivateKeyBytes()),
        });
      final phone = rootFor('phone', phoneStore);
      addTearDown(phone.dispose);
      await phone.initialize();

      await phone.setAccountPassword(newPassword: 'correct horse battery');
      expect(server.password, isNotNull);
      expect(
        jsonEncode(server.password),
        isNot(contains('correct horse')),
        reason: 'the password itself never leaves the device',
      );

      // The tablet: knows nothing but the number and the password.
      final tabletStore = _MemoryStore();
      final tablet = rootFor('tablet', tabletStore);
      addTearDown(tablet.dispose);
      await tablet.initialize();

      final lookup = await tablet.lookupPasswordAccount('+8801700000000');
      expect(lookup.hasPassword, isTrue);
      expect(lookup.phoneHash, phoneHash(server.salt, '+8801700000000'));
      await tablet.signInWithPassword(
        lookup: lookup,
        password: 'correct horse battery',
      );

      // Same account identity as the phone...
      expect(tabletStore.values['account_id'], 'acc_multi');
      expect(
        tabletStore.values['identity_private_key'],
        phoneStore.values['identity_private_key'],
      );
      // ...with its own device keys...
      expect(tabletStore.values['device_signing_private_key'], isNotNull);
      expect(tabletStore.values['refresh_token'], isNotEmpty);

      // ...and prekeys that verify against the account identity key, which is
      // what lets contacts encrypt to it.
      final published = server.publishedPrekeys!;
      final signedPrekey = base64Url.decode(
        base64Url.normalize(published['signed_prekey'] as String),
      );
      final signature = base64Url.decode(
        base64Url.normalize(published['signature'] as String),
      );
      expect(
        await Ed25519().verify(
          signedPrekey,
          signature: Signature(
            signature,
            publicKey: await identity.extractPublicKey(),
          ),
        ),
        isTrue,
      );
    },
  );

  test('a password sign-in restores the text history backup', () async {
    final identity = await Ed25519().newKeyPair();
    final identityPublic = _b64((await identity.extractPublicKey()).bytes);
    final identityPrivate = await identity.extractPrivateKeyBytes();
    server.identityPublicKey = identityPublic;
    final phoneStore = _MemoryStore()
      ..values.addAll({
        'account_id': 'acc_multi',
        'phone_number': '+8801700000000',
        'identity_public_key': identityPublic,
        'identity_private_key': _b64(identityPrivate),
      });
    final phone = rootFor('phone', phoneStore);
    addTearDown(phone.dispose);
    await phone.initialize();
    await phone.setAccountPassword(newPassword: 'correct horse battery');

    // What the phone backed up earlier, under the account identity key.
    server.historyBlob = await HistoryBackupCodec.encrypt(
      key: await HistoryBackupCodec.deriveKey(identityPrivate),
      identityPublicKey: identityPublic,
      snapshot: {
        'v': 1,
        'conversations': {
          'dm_bob': {
            'title': 'Bob',
            'type': 'DIRECT',
            'members': ['acc_multi', 'acc_bob'],
          },
        },
        'messages': [
          {
            'id': 'old_1',
            'conversation_id': 'dm_bob',
            'sender_account_id': 'acc_bob',
            'sender_device_id': 'bob_phone',
            'ts': 1000,
            'status': 'DELIVERED',
            'text': 'from last year',
          },
        ],
      },
    );

    final tablet = rootFor('tablet', _MemoryStore());
    addTearDown(tablet.dispose);
    await tablet.initialize();
    await tablet.signInWithPassword(
      lookup: await tablet.lookupPasswordAccount('+8801700000000'),
      password: 'correct horse battery',
    );

    final history = await tablet.messagingService.messageHistory('dm_bob');
    expect(history.map((m) => m.text), ['from last year']);
  });

  test('a wrong password leaves the new device signed out', () async {
    final identity = await Ed25519().newKeyPair();
    server.identityPublicKey = _b64((await identity.extractPublicKey()).bytes);
    final phoneStore = _MemoryStore()
      ..values.addAll({
        'account_id': 'acc_multi',
        'phone_number': '+8801700000000',
        'identity_public_key': server.identityPublicKey!,
        'identity_private_key': _b64(await identity.extractPrivateKeyBytes()),
      });
    final phone = rootFor('phone', phoneStore);
    addTearDown(phone.dispose);
    await phone.initialize();
    await phone.setAccountPassword(newPassword: 'correct horse battery');

    final tabletStore = _MemoryStore();
    final tablet = rootFor('tablet', tabletStore);
    addTearDown(tablet.dispose);
    await tablet.initialize();
    final lookup = await tablet.lookupPasswordAccount('+8801700000000');

    await expectLater(
      tablet.signInWithPassword(lookup: lookup, password: 'wrong horse'),
      throwsA(isA<Exception>()),
    );
    expect(tabletStore.values['identity_private_key'], isNull);
    expect(tablet.startupState, RemoteStartupState.unauthenticated);
  });
}
