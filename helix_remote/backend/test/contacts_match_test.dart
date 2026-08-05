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

  test('meters distinct hashes, so chunk size does not change the cost', () {
    // The point of the redesign: a 2,100-contact phone book used to cost the
    // entire daily allowance no matter how it was chunked, because the cap
    // counted requests. It now costs 2,100 of 5,000 hashes, leaving room for
    // a retry, a second device, and tomorrow.
    expect(ContactsModule.contactsMatchDailyHashLimit, greaterThan(2100 * 2));
  });

  test('spends budget per hash and reports what is left', () async {
    final first = await match([
      phoneHash(salt, '+15550000002'),
      phoneHash(salt, '+15550000003'),
    ]);
    expect(first['statusCode'], 200);
    final body = first['body'] as Map<String, dynamic>;
    expect(body['hashes_charged'], 2);
    expect(
      body['hashes_remaining_today'],
      ContactsModule.contactsMatchDailyHashLimit - 2,
    );
  });

  test('a duplicate number inside one request is charged once', () async {
    final h = phoneHash(salt, '+15550000002');
    final result = await match([h, h, h]);
    expect((result['body'] as Map<String, dynamic>)['hashes_charged'], 1);
  });

  test('exhausting the budget answers 429 with a retry hint', () async {
    // Spend the whole allowance in batches, then confirm the next request is
    // refused with something the client can act on rather than a bare error.
    var spent = 0;
    var n = 0;
    while (spent < ContactsModule.contactsMatchDailyHashLimit) {
      final batch = List.generate(
        ContactsModule.contactsMatchBatchLimit,
        (i) => phoneHash(salt, '+1600${n}_$i'),
      );
      n++;
      final result = await match(batch);
      if (result['statusCode'] == 429) break;
      spent +=
          (result['body'] as Map<String, dynamic>)['hashes_charged'] as int;
    }
    final overflow = await match([phoneHash(salt, '+15559999999')]);
    expect(overflow['statusCode'], 429);
    final details =
        (overflow['body'] as Map<String, dynamic>)['details']
            as Map<String, dynamic>;
    expect(details['hashes_remaining_today'], 0);
    expect(details['retry_after_seconds'], greaterThan(0));
  });

  test(
    'a request larger than the remaining budget is answered partially',
    () async {
      // A whole sync failing on its last chunk is worse than a short answer:
      // the client keeps what it got and resumes when the window rolls over.
      // Spend an amount that does not divide evenly into the batch size, so
      // the budget runs out mid-request rather than exactly at a boundary.
      await match(List.generate(500, (i) => phoneHash(salt, '+1699_$i')));

      var n = 0;
      while (true) {
        final batch = List.generate(
          ContactsModule.contactsMatchBatchLimit,
          (i) => phoneHash(salt, '+1700${n}_$i'),
        );
        n++;
        final result = await match(batch);
        final body = result['body'] as Map<String, dynamic>;
        if (result['statusCode'] == 429) {
          fail('budget ran out before a partial');
        }
        if (body['partial'] == true) {
          expect(body['hashes_charged'], lessThan(batch.length));
          expect(body['hashes_charged'], greaterThan(0));
          expect(body['retry_after_seconds'], greaterThan(0));
          return;
        }
      }
    },
  );
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
