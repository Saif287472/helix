import 'dart:async';
import 'dart:io';

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the phone's address book permission stands.
enum ContactsPermission {
  /// This platform has no address book (Windows).
  unsupported,

  /// Never asked.
  notAsked,
  granted,

  /// Refused once; the system dialog may be shown again.
  denied,

  /// Refused for good; only the system settings can change it.
  permanentlyDenied,
}

/// One contact as the address book stores it: its id, the name it is shown
/// under, and every number it has, exactly as written.
final class AddressBookContact {
  const AddressBookContact({
    required this.id,
    required this.name,
    required this.numbers,
  });

  final String id;
  final String name;
  final List<String> numbers;
}

/// The platform's address book, behind one interface so that the permission
/// flow, discovery and the rename-writes-to-phone rule can all be tested
/// without a phone (a fake lives in `test/support`).
///
/// Every method answers rather than throws: a person can refuse access at any
/// moment, and the address book is an optimisation (anybody can still be
/// found by number or `~Helix name`).
abstract interface class ContactsAccess {
  bool get isSupported;

  /// The current state, without asking.
  Future<ContactsPermission> permission();

  /// Shows the system permission dialog when it may be shown. Asks for
  /// **read** only: reading finds people. Write access is asked for at the
  /// moment of a rename (see [saveName]), never up front.
  Future<ContactsPermission> request();

  /// Opens the app's page in the system settings.
  Future<void> openSettings();

  /// Every contact with its numbers. Empty without permission.
  Future<List<AddressBookContact>> readAll();

  /// Gives a contact the name [name]: the contact [contactId] is renamed, or,
  /// with no id, a new contact is created holding [number]. False when the
  /// phone refused.
  Future<bool> saveName({
    String? contactId,
    required String number,
    required String name,
  });

  /// Fires when the address book changes.
  Stream<void> get changes;
}

/// The real address book (Android; iOS and macOS would work too).
final class FlutterContactsAccess implements ContactsAccess {
  const FlutterContactsAccess();

  static const _type = PermissionType.read;

  @override
  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  @override
  Future<ContactsPermission> permission() async {
    if (!isSupported) return ContactsPermission.unsupported;
    try {
      return _map(await FlutterContacts.permissions.check(_type));
    } on Object {
      return ContactsPermission.unsupported;
    }
  }

  @override
  Future<ContactsPermission> request() async {
    if (!isSupported) return ContactsPermission.unsupported;
    try {
      return _map(await FlutterContacts.permissions.request(_type));
    } on Object {
      return ContactsPermission.denied;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await FlutterContacts.permissions.openSettings();
    } on Object {
      // Nothing to open on this platform.
    }
  }

  static bool _isGranted(PermissionStatus status) =>
      status == PermissionStatus.granted || status == PermissionStatus.limited;

  static ContactsPermission _map(PermissionStatus status) => switch (status) {
    PermissionStatus.granted ||
    PermissionStatus.limited => ContactsPermission.granted,
    PermissionStatus.denied => ContactsPermission.denied,
    PermissionStatus.permanentlyDenied ||
    PermissionStatus.restricted => ContactsPermission.permanentlyDenied,
    PermissionStatus.notDetermined => ContactsPermission.notAsked,
  };

  @override
  Future<List<AddressBookContact>> readAll() async {
    if (await permission() != ContactsPermission.granted) return const [];
    try {
      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone},
      );
      return [
        for (final contact in contacts)
          if (contact.phones.isNotEmpty)
            AddressBookContact(
              id: contact.id ?? '',
              name: (contact.displayName ?? '').trim(),
              numbers: [
                // The platform's own E.164 where it has one.
                for (final phone in contact.phones)
                  phone.normalizedNumber ?? phone.number,
              ],
            ),
      ];
    } on Object {
      return const [];
    }
  }

  @override
  Future<bool> saveName({
    String? contactId,
    required String number,
    required String name,
  }) async {
    if (await permission() != ContactsPermission.granted) return false;
    try {
      // Saving a name is the one thing that needs write access, so it is
      // asked for now, with the person's rename as the reason. A refusal
      // leaves the name in Helix only.
      final write = await FlutterContacts.permissions.check(
        PermissionType.readWrite,
      );
      if (!_isGranted(write)) {
        final asked = await FlutterContacts.permissions.request(
          PermissionType.readWrite,
        );
        if (!_isGranted(asked)) return false;
      }
      if (contactId != null && contactId.isNotEmpty) {
        final contact = await FlutterContacts.get(
          contactId,
          properties: {ContactProperty.name, ContactProperty.phone},
        );
        if (contact != null) {
          await FlutterContacts.update(
            contact.copyWith(name: Name(first: name)),
          );
          return true;
        }
      }
      await FlutterContacts.create(
        Contact(
          name: Name(first: name),
          phones: [Phone(number: number)],
        ),
      );
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Stream<void> get changes {
    if (!isSupported) return const Stream<void>.empty();
    return FlutterContacts.onDatabaseChange;
  }
}

/// The address book the app uses. Tests override it with a fake.
final contactsAccessProvider = Provider<ContactsAccess>(
  (ref) => const FlutterContactsAccess(),
);
