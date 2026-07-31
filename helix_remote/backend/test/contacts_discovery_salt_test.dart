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

  setUp(() {
    db = BackendDatabase(sqlite3.openInMemory());
    contacts = ContactsModule(db);
  });

  tearDown(() {
    db.close();
  });

  test(
    'discovery salt self-heals on first call and is unauthenticated',
    () async {
      final response = await contacts.router.call(
        Request('GET', Uri.parse('http://localhost/discovery-salt')),
      );
      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final salt = body['salt'] as String;
      expect(salt, isNotEmpty);
      // Must decode as valid base64 of 32 bytes.
      expect(base64.decode(salt).length, 32);
    },
  );

  test('discovery salt is stable across repeated calls', () async {
    Future<String> fetchSalt() async {
      final response = await contacts.router.call(
        Request('GET', Uri.parse('http://localhost/discovery-salt')),
      );
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      return body['salt'] as String;
    }

    final first = await fetchSalt();
    final second = await fetchSalt();
    expect(first, second);
  });

  test(
    'phoneHash is deterministic for the same salt and number, and differs across numbers',
    () {
      final salt = generateDiscoverySalt();
      final hashA1 = phoneHash(salt, '+15551234567');
      final hashA2 = phoneHash(salt, '+15551234567');
      final hashB = phoneHash(salt, '+15557654321');
      expect(hashA1, hashA2);
      expect(hashA1, isNot(equals(hashB)));
    },
  );

  test('phoneHash differs across salts for the same number', () {
    final saltOne = generateDiscoverySalt();
    final saltTwo = generateDiscoverySalt();
    expect(saltOne, isNot(equals(saltTwo)));
    final hashOne = phoneHash(saltOne, '+15551234567');
    final hashTwo = phoneHash(saltTwo, '+15551234567');
    expect(hashOne, isNot(equals(hashTwo)));
  });
}
