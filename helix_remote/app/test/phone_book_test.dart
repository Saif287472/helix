import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/platform/contacts_access.dart';
import 'package:helix_remote/core/platform/device_phone_book.dart';
import 'package:helix_remote/core/platform/phone_numbers.dart';
import 'package:helix_remote/features/people/application/people_gateway.dart';
import 'package:helix_remote/features/people/application/phone_book_sync.dart';
import 'package:helix_remote_api/v2.dart' show ApiException, NetworkException;
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show PhoneBookSyncResult;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;

import 'support/people_fakes.dart';

/// The phone-book integration: what the adapter reads and writes, the
/// permission flow, and how politely discovery is run.
void main() {
  group('DevicePhoneBook (the engine\'s PhoneBook over the address book)', () {
    final contacts = [
      const AddressBookContact(
        id: 'c1',
        name: ' Mum ',
        numbers: ['01711-000001', '+880 1711 000001', 'not a number'],
      ),
      const AddressBookContact(
        id: 'c2',
        name: 'Work',
        numbers: ['+44 20 7946 0958'],
      ),
      const AddressBookContact(id: 'c3', name: 'Junk', numbers: ['12']),
    ];

    test('reads names and E.164 numbers, once each, never raw text', () async {
      final access = FakeContactsAccess(
        state: ContactsPermission.granted,
        contacts: contacts,
      );
      final country = PhoneCountry()..callingCode = '880';
      final entries = await DevicePhoneBook(
        access: access,
        country: country,
      ).entries();
      expect(entries.map((e) => e.name), ['Mum', 'Work']);
      expect(entries[0].numbers, ['+8801711000001'], reason: 'deduplicated');
      expect(entries[1].numbers, ['+442079460958']);
    });

    test('a bare national number is skipped without a country', () async {
      final access = FakeContactsAccess(
        state: ContactsPermission.granted,
        contacts: contacts,
      );
      final entries = await DevicePhoneBook(access: access).entries();
      // 01711-000001 cannot be placed, but the same contact's international
      // form can.
      expect(entries.first.numbers, ['+8801711000001']);
    });

    test('without the permission the address book is empty', () async {
      for (final state in [
        ContactsPermission.notAsked,
        ContactsPermission.denied,
        ContactsPermission.permanentlyDenied,
      ]) {
        final access = FakeContactsAccess(state: state, contacts: contacts);
        expect(await DevicePhoneBook(access: access).entries(), isEmpty);
      }
    });

    test('rename updates the contact that already holds the number', () async {
      final access = FakeContactsAccess(
        state: ContactsPermission.granted,
        contacts: contacts,
      );
      final book = DevicePhoneBook(
        access: access,
        country: PhoneCountry()..callingCode = '880',
      );
      expect(await book.saveName('+8801711000001', '  Mother  '), isTrue);
      // Found through a differently written number, renamed in place.
      expect(access.lastWrite, (
        id: 'c1',
        number: '+8801711000001',
        name: 'Mother',
      ));
      expect(access.contacts.map((c) => c.name), ['Mother', 'Work', 'Junk']);
    });

    test('rename creates a contact when the phone has none', () async {
      final access = FakeContactsAccess(
        state: ContactsPermission.granted,
        contacts: contacts,
      );
      expect(
        await DevicePhoneBook(access: access).saveName('+8801811000009', 'Sam'),
        isTrue,
      );
      expect(access.lastWrite, (
        id: null,
        number: '+8801811000009',
        name: 'Sam',
      ));
      expect(access.contacts.last.name, 'Sam');
      expect(access.contacts.last.numbers, ['+8801811000009']);
    });

    test('rename answers false, and writes nothing, when it cannot', () async {
      DevicePhoneBook book(FakeContactsAccess access) =>
          DevicePhoneBook(access: access);
      final denied = FakeContactsAccess(state: ContactsPermission.denied);
      expect(await book(denied).saveName('+8801811000009', 'Sam'), isFalse);
      expect(denied.lastWrite, isNull);

      final readOnly = FakeContactsAccess(state: ContactsPermission.granted)
        ..refuseWrites = true;
      expect(await book(readOnly).saveName('+8801811000009', 'Sam'), isFalse);

      final granted = FakeContactsAccess(state: ContactsPermission.granted);
      expect(await book(granted).saveName('+8801811000009', '   '), isFalse);
      expect(await book(granted).saveName('garbage', 'Sam'), isFalse);
      expect(granted.lastWrite, isNull);
    });

    test('the real address book is unsupported off a phone', () async {
      // `flutter test` runs on a desktop: there is no address book, and
      // every call answers instead of throwing.
      const access = FlutterContactsAccess();
      expect(access.isSupported, isFalse);
      expect(await access.permission(), ContactsPermission.unsupported);
      expect(await access.request(), ContactsPermission.unsupported);
      expect(await access.readAll(), isEmpty);
      expect(await access.saveName(number: '+8801711000001', name: 'x'), false);
      await access.openSettings();
    });
  });

  group('the permission flow and discovery', () {
    late FakePeopleGateway gateway;
    late FakeContactsAccess access;
    late DateTime now;
    late ProviderContainer container;

    ProviderContainer build() => ProviderContainer(
      overrides: [
        peopleGatewayProvider.overrideWith((ref) async => gateway),
        contactsAccessProvider.overrideWithValue(access),
        peopleClockProvider.overrideWithValue(() => now),
      ],
    );

    int syncs() => gateway.calls.where((c) => c == 'syncPhoneBook').length;

    setUp(() {
      gateway = FakePeopleGateway();
      access = FakeContactsAccess(state: ContactsPermission.granted);
      now = DateTime.utc(2026, 10, 3, 8);
      container = build();
    });
    tearDown(() => container.dispose());

    PhoneBookSyncController sync() =>
        container.read(phoneBookSyncProvider.notifier);

    test('nothing is read or sent without the permission', () async {
      access.state = ContactsPermission.notAsked;
      await sync().syncIfDue();
      await sync().syncNow();
      expect(syncs(), 0);
      expect(
        container.read(phoneBookSyncProvider).status,
        PhoneBookStatus.needsPermission,
      );
    });

    test('asking shows the system dialog and, when granted, syncs', () async {
      access.state = ContactsPermission.notAsked;
      expect(
        await container.read(contactsPermissionProvider.future),
        ContactsPermission.notAsked,
      );
      final result = await container
          .read(contactsPermissionProvider.notifier)
          .request();
      expect(result, ContactsPermission.granted);
      expect(access.events, ['request']);
      expect(syncs(), 1);
      expect(
        container.read(contactsPermissionProvider).value,
        ContactsPermission.granted,
      );
      final state = container.read(phoneBookSyncProvider);
      expect(state.status, PhoneBookStatus.synced);
      expect(state.found, 2);
      expect(state.checked, 3);
    });

    test('a refusal is respected: no sync, and the state says so', () async {
      access
        ..state = ContactsPermission.notAsked
        ..grantOnRequest = false;
      final result = await container
          .read(contactsPermissionProvider.notifier)
          .request();
      expect(result, ContactsPermission.denied);
      expect(syncs(), 0);
      expect(
        container.read(contactsPermissionProvider).value,
        ContactsPermission.denied,
      );
    });

    test('a permanent refusal is sent to the system settings', () async {
      access.state = ContactsPermission.permanentlyDenied;
      await container.read(contactsPermissionProvider.notifier).openSettings();
      expect(access.events, ['openSettings']);
    });

    test('Windows has no address book, and nothing is asked', () async {
      access.supported = false;
      expect(
        await container.read(contactsPermissionProvider.future),
        ContactsPermission.unsupported,
      );
      await sync().syncIfDue();
      expect(syncs(), 0);
    });

    test('the own number\'s country is handed to the adapter first', () async {
      await sync().syncNow();
      expect(container.read(phoneCountryProvider).callingCode, '880');
    });

    test('a due sync runs once, then waits twelve hours', () async {
      await sync().syncIfDue();
      expect(syncs(), 1);
      expect(gateway.syncLog!.at, now);
      expect(gateway.syncLog!.checked, 3);
      expect(gateway.syncLog!.remainingToday, 4997);

      now = now.add(const Duration(hours: 11));
      await sync().syncIfDue();
      expect(syncs(), 1, reason: 'resuming again within hours is free');

      now = now.add(const Duration(hours: 2));
      await sync().syncIfDue();
      expect(syncs(), 2);
    });

    test(
      'a changed address book is synced after an hour, not twelve',
      () async {
        await sync().syncIfDue();
        now = now.add(const Duration(minutes: 30));
        await sync().syncIfDue(addressBookChanged: true);
        expect(syncs(), 1);
        now = now.add(const Duration(minutes: 31));
        await sync().syncIfDue(addressBookChanged: true);
        expect(syncs(), 2);
      },
    );

    test('a day that cannot afford another sync does not start one', () async {
      gateway.syncResult = const PhoneBookSyncResult(
        checked: 4000,
        found: 10,
        remainingToday: 1000,
      );
      await sync().syncIfDue();
      expect(syncs(), 1);

      // Thirteen hours later, still the same UTC day: 1,000 left, 4,000 needed.
      now = DateTime.utc(2026, 10, 3, 21);
      await sync().syncIfDue();
      expect(syncs(), 1);

      // Tomorrow the budget is back.
      now = DateTime.utc(2026, 10, 4, 9);
      await sync().syncIfDue();
      expect(syncs(), 2);
    });

    test('the server\'s limit is remembered until tomorrow', () async {
      gateway.syncError = const ApiException(
        status: 429,
        code: ErrorCode.rateLimited,
      );
      await sync().syncNow();
      expect(
        container.read(phoneBookSyncProvider).status,
        PhoneBookStatus.budgetExhausted,
      );
      expect(gateway.syncLog!.remainingToday, 0);

      gateway.syncError = null;
      now = now.add(const Duration(hours: 13));
      await sync().syncIfDue();
      expect(syncs(), 1, reason: 'same day, spent');
    });

    test('offline is a quiet failure that the next resume retries', () async {
      gateway.syncError = const NetworkException();
      await sync().syncNow();
      expect(
        container.read(phoneBookSyncProvider).status,
        PhoneBookStatus.failed,
      );
      expect(gateway.syncLog, isNull, reason: 'nothing was spent');
      gateway.syncError = null;
      await sync().syncIfDue();
      expect(syncs(), 2);
      expect(
        container.read(phoneBookSyncProvider).status,
        PhoneBookStatus.synced,
      );
    });
  });
}
