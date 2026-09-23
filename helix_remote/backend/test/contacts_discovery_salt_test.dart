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
      expect(body['algorithm'], 'hardened_hmac_sha256');
      expect(body['iterations'], 10000);
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

  test('discovery salt enforces IP rate limit when flooded', () async {
    final ip = '198.51.100.42';
    // Consume quota up to limit
    for (var i = 0; i < ContactsModule.discoverySaltMinuteLimit; i++) {
      final res = await contacts.router.call(
        Request(
          'GET',
          Uri.parse('http://localhost/discovery-salt'),
          headers: {'x-forwarded-for': ip},
        ),
      );
      expect(res.statusCode, 200);
    }
    // Next request must be rate limited (429)
    final blocked = await contacts.router.call(
      Request(
        'GET',
        Uri.parse('http://localhost/discovery-salt'),
        headers: {'x-forwarded-for': ip},
      ),
    );
    expect(blocked.statusCode, 429);
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

  test('phoneHashHardened provides iterative key stretching', () {
    final salt = generateDiscoverySalt();
    final number = '+15551234567';
    final legacy = phoneHash(salt, number);
    final hardened = phoneHashHardened(salt, number, iterations: 100);
    expect(hardened, isNot(equals(legacy)));
    expect(hardened, equals(phoneHashHardened(salt, number, iterations: 100)));
  });

  test('verifyPhoneHash supports both hardened and legacy hashes', () {
    final salt = generateDiscoverySalt();
    final number = '+15551234567';
    final legacy = phoneHash(salt, number);
    final hardened = phoneHashHardened(salt, number, iterations: 50);

    expect(verifyPhoneHash(salt, number, legacy), isTrue);
    expect(verifyPhoneHash(salt, number, hardened, iterations: 50), isTrue);
    expect(verifyPhoneHash(salt, '+15559999999', legacy), isFalse);
  });
}
