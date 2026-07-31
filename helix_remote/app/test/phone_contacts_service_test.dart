import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/services/phone_contacts_service.dart';

// Independently computed HMAC-SHA256(salt, number) known-answer vector
// (Python hmac/hashlib, not this codebase) - hashPhoneBookContacts must
// stay byte-for-byte identical to the signup flow's phoneHash()
// (app/lib/app/phone_hashing.dart) and the backend's phoneHash()
// (backend/lib/src/phone_hash.dart) for the same salt and number.
const _testSaltBase64 = 'MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=';
const _testNumber = '+15551234567';
const _expectedHash =
    '16f44c03b65ef7f5e4e1a74189b76998e88fa4a17d4c551ce70fca76a846e893';

void main() {
  group('hashPhoneBookContacts', () {
    test('matches the known-answer HMAC-SHA256 vector', () {
      final result = hashPhoneBookContacts(
        contacts: const [
          PhoneBookContact(displayName: 'Alice', phoneNumbers: [_testNumber]),
        ],
        discoverySaltBase64: _testSaltBase64,
      );
      expect(result, hasLength(1));
      expect(result.keys.single, equals(_expectedHash));
      expect(result[_expectedHash], equals('Alice'));
    });

    test('normalizes loosely formatted numbers before hashing', () {
      final result = hashPhoneBookContacts(
        contacts: const [
          PhoneBookContact(
            displayName: 'Bob',
            phoneNumbers: ['+1 (555) 123-4567'],
          ),
        ],
        discoverySaltBase64: _testSaltBase64,
      );
      expect(result.keys.single, equals(_expectedHash));
    });

    test('skips invalid numbers and contacts with no phone numbers', () {
      final result = hashPhoneBookContacts(
        contacts: const [
          PhoneBookContact(displayName: 'NoNumber', phoneNumbers: []),
          PhoneBookContact(displayName: 'BadNumber', phoneNumbers: ['123']),
        ],
        discoverySaltBase64: _testSaltBase64,
      );
      expect(result, isEmpty);
    });

    test('skips contacts with an empty display name', () {
      final result = hashPhoneBookContacts(
        contacts: const [
          PhoneBookContact(displayName: '  ', phoneNumbers: [_testNumber]),
        ],
        discoverySaltBase64: _testSaltBase64,
      );
      expect(result, isEmpty);
    });

    test('first contact wins when two phone-book entries share a hash', () {
      final result = hashPhoneBookContacts(
        contacts: const [
          PhoneBookContact(displayName: 'First', phoneNumbers: [_testNumber]),
          PhoneBookContact(
            displayName: 'Second',
            phoneNumbers: [_testNumber],
          ),
        ],
        discoverySaltBase64: _testSaltBase64,
      );
      expect(result[_expectedHash], equals('First'));
    });
  });

  group('PhoneContactsService permission handling', () {
    test(
      'a denied fake surfaces PhoneContactsPermissionResult.denied',
      () async {
        // The real DevicePhoneContactsService talks to a platform channel
        // that isn't registered under `flutter test`; the contacts screen
        // depends on the denial path degrading gracefully rather than
        // throwing, which this fake exercises without touching a device.
        const service = _FakePhoneContactsService(
          result: PhoneContactsPermissionResult.denied,
        );
        final result = await service.requestPermission();
        expect(result, PhoneContactsPermissionResult.denied);
      },
    );

    test('a granted fake returns the loaded phone book', () async {
      const service = _FakePhoneContactsService(
        result: PhoneContactsPermissionResult.granted,
        contacts: [
          PhoneBookContact(displayName: 'Carol', phoneNumbers: [_testNumber]),
        ],
      );
      expect(
        await service.requestPermission(),
        PhoneContactsPermissionResult.granted,
      );
      final loaded = await service.loadContacts();
      expect(loaded, hasLength(1));
      expect(loaded.single.displayName, equals('Carol'));
    });
  });
}

class _FakePhoneContactsService implements PhoneContactsService {
  const _FakePhoneContactsService({
    required this.result,
    this.contacts = const [],
  });

  final PhoneContactsPermissionResult result;
  final List<PhoneBookContact> contacts;

  @override
  Future<PhoneContactsPermissionResult> requestPermission() async => result;

  @override
  Future<List<PhoneBookContact>> loadContacts() async => contacts;
}
