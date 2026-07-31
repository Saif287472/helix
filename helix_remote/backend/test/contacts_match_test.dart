import 'dart:convert';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/modules/contacts.dart';
import 'package:helix_remote_backend/src/phone_hash.dart';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late BackendDatabase db;
  late ContactsModule contacts;
  late String salt;

  setUp(() {
    db = BackendDatabase(sqlite3.openInMemory());
    contacts = ContactsModule(db);
    salt = generateDiscoverySalt();

    _seedAccountWithPhone(
      db,
      'alice',
      phoneHash: phoneHash(salt, '+15550000001'),
    );
    _seedAccountWithPhone(
      db,
      'bob',
      phoneHash: phoneHash(salt, '+15550000002'),
    );
    _seedAccountWithPhone(
      db,
      'carol',
      phoneHash: phoneHash(salt, '+15550000003'),
    );
  });

  tearDown(() {
    db.close();
  });

  Future<Map<String, dynamic>> match(
    List<String> phoneHashes, {
    String authAccount = 'alice',
  }) async {
    final response = await contacts.router.call(
      _request(
        'POST',
        '/match',
        authAccount: authAccount,
        authDevice: '${authAccount}_device',
        body: {'phone_hashes': phoneHashes},
      ),
    );
    return {
      'statusCode': response.statusCode,
      'body': jsonDecode(await response.readAsString()),
    };
  }

  test('returns only matched accounts, keyed by phone hash', () async {
    final bobHash = phoneHash(salt, '+15550000002');
    final carolHash = phoneHash(salt, '+15550000003');
    final unknownHash = phoneHash(salt, '+15559999999');

    final result = await match([bobHash, carolHash, unknownHash]);
    expect(result['statusCode'], 200);
    final matches =
        (result['body'] as Map<String, dynamic>)['matches']
            as Map<String, dynamic>;
    expect(matches.keys, containsAll([bobHash, carolHash]));
    expect(matches.containsKey(unknownHash), isFalse);
    expect((matches[bobHash] as Map<String, dynamic>)['account_id'], 'bob');
    expect((matches[carolHash] as Map<String, dynamic>)['account_id'], 'carol');
  });

  test('excludes accounts with phone_discoverable disabled', () async {
    final bobHash = phoneHash(salt, '+15550000002');
    db.setPrivacy(
      accountId: 'bob',
      searchDiscoverable: true,
      presenceVisibility: 'CONTACTS',
      lastSeenVisibility: 'CONTACTS',
      phoneDiscoverable: false,
    );

    final result = await match([bobHash]);
    final matches = (result['body'] as Map<String, dynamic>)['matches'] as Map;
    expect(matches.containsKey(bobHash), isFalse);
  });

  test('rejects unauthenticated requests', () async {
    final response = await contacts.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/match'),
        body: jsonEncode({
          'phone_hashes': [phoneHash(salt, '+15550000002')],
        }),
        headers: {'content-type': 'application/json'},
      ),
    );
    expect(response.statusCode, 403);
  });

  test('rejects a batch over the size limit', () async {
    final tooMany = List.generate(
      ContactsModule.contactsMatchBatchLimit + 1,
      (i) => phoneHash(salt, '+1555000$i'),
    );
    final result = await match(tooMany);
    expect(result['statusCode'], 400);
  });

  test('enforces the daily match-request quota', () async {
    for (var i = 0; i < ContactsModule.contactsMatchDailyLimit; i++) {
      final result = await match([phoneHash(salt, '+15550000002')]);
      expect(result['statusCode'], 200);
    }
    final overflow = await match([phoneHash(salt, '+15550000002')]);
    expect(overflow['statusCode'], 429);
  });
}

void _seedAccountWithPhone(
  BackendDatabase db,
  String accountId, {
  required String phoneHash,
  String? displayName,
}) {
  db.createAccount(
    accountId,
    'helix_$accountId',
    '${accountId}_identity',
    phoneHash: phoneHash,
  );
  db.upsertAccountProfile(
    accountId: accountId,
    displayName: displayName ?? accountId,
  );
  db.registerDevice(
    '${accountId}_device',
    accountId,
    '${accountId}_signing_key',
    '${accountId}_agreement_key',
    '$accountId Phone',
  );
}

Request _request(
  String method,
  String path, {
  required String authAccount,
  required String authDevice,
  Map<String, dynamic>? body,
}) {
  return Request(
    method,
    Uri.parse('http://localhost$path'),
    body: body == null ? null : jsonEncode(body),
    headers: {'content-type': 'application/json'},
    context: {
      'auth': {'account_id': authAccount, 'device_id': authDevice},
      'client_ip': '127.0.0.1',
    },
  );
}
