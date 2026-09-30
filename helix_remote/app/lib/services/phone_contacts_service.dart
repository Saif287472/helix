import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:helix_remote/app/phone_hashing.dart';
import 'package:helix_remote/app/remote_account_validation.dart';

/// A single phone-book entry: a contact's display name plus every raw phone
/// number found on it. Numbers are normalized/hashed later, not here, so
/// this stays a thin, easily-fakeable read of the OS contact list.
class PhoneBookContact {
  const PhoneBookContact({
    required this.displayName,
    required this.phoneNumbers,
  });

  final String displayName;
  final List<String> phoneNumbers;
}

enum PhoneContactsPermissionResult { granted, denied }

/// Abstraction over the OS phone book so the sync flow - and its tests -
/// never depend on the flutter_contacts platform channel directly.
abstract class PhoneContactsService {
  Future<PhoneContactsPermissionResult> requestPermission();
  Future<List<PhoneBookContact>> loadContacts();

  /// Names [phoneNumber] [name] in the phone's contacts: renames the entry
  /// that has this number, or creates one. False when the user refused
  /// permission or the entry belongs to a read-only account.
  Future<bool> saveName({required String phoneNumber, required String name});
}

class DevicePhoneContactsService implements PhoneContactsService {
  const DevicePhoneContactsService();

  @override
  Future<PhoneContactsPermissionResult> requestPermission() async {
    final status = await fc.FlutterContacts.permissions.request(
      fc.PermissionType.read,
    );
    return switch (status) {
      fc.PermissionStatus.granted ||
      fc.PermissionStatus.limited => PhoneContactsPermissionResult.granted,
      _ => PhoneContactsPermissionResult.denied,
    };
  }

  @override
  Future<bool> saveName({
    required String phoneNumber,
    required String name,
  }) async {
    final wanted = RemoteAccountValidation.normalizePhoneNumber(phoneNumber);
    if (!RemoteAccountValidation.isValidPhoneNumber(wanted) ||
        name.trim().isEmpty) {
      return false;
    }
    final status = await fc.FlutterContacts.permissions.request(
      fc.PermissionType.readWrite,
    );
    if (status != fc.PermissionStatus.granted &&
        status != fc.PermissionStatus.limited) {
      return false;
    }
    final newName = fc.Name(first: name.trim());
    final contacts = await fc.FlutterContacts.getAll(
      properties: {fc.ContactProperty.name, fc.ContactProperty.phone},
    );
    final existing = contacts.where(
      (c) => c.phones.any(
        (p) => RemoteAccountValidation.normalizePhoneNumber(p.number) == wanted,
      ),
    );
    try {
      if (existing.isNotEmpty) {
        await fc.FlutterContacts.update(existing.first.copyWith(name: newName));
      } else {
        await fc.FlutterContacts.create(
          fc.Contact(
            name: newName,
            phones: [fc.Phone(number: wanted)],
          ),
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<PhoneBookContact>> loadContacts() async {
    final contacts = await fc.FlutterContacts.getAll(
      properties: {fc.ContactProperty.phone},
    );
    return contacts
        .map(
          (c) => PhoneBookContact(
            displayName: c.displayName ?? '',
            phoneNumbers: c.phones.map((p) => p.number).toList(growable: false),
          ),
        )
        .where((c) => c.displayName.isNotEmpty && c.phoneNumbers.isNotEmpty)
        .toList(growable: false);
  }
}

/// Normalizes and hashes every phone number across [contacts], mapping each
/// resulting hash to the phone-book display name of the contact it came
/// from. Pure and platform-independent so it can be exercised with the same
/// fixed test vector as the signup flow's phoneHash() - app and backend must
/// never diverge on this computation. Invalid numbers are skipped; when the
/// same hash is reached from two different phone-book entries, the first
/// one wins.
Map<String, String> hashPhoneBookContacts({
  required List<PhoneBookContact> contacts,
  required String discoverySaltBase64,
}) {
  final hashToName = <String, String>{};
  for (final contact in contacts) {
    final name = contact.displayName.trim();
    if (name.isEmpty) continue;
    for (final rawNumber in contact.phoneNumbers) {
      final normalized = RemoteAccountValidation.normalizePhoneNumber(
        rawNumber,
      );
      if (!RemoteAccountValidation.isValidPhoneNumber(normalized)) continue;
      final hash = phoneHash(discoverySaltBase64, normalized);
      hashToName.putIfAbsent(hash, () => name);
    }
  }
  return hashToName;
}

/// Groups every valid, hashed phone number on each phone-book contact by
/// that contact's display name. [hashPhoneBookContacts] collapses to one
/// name per hash for the match request, which loses which hashes belong to
/// the same person; this keeps that grouping so a caller can tell whether
/// *any* of a person's numbers matched, not just a single one - someone
/// with two numbers where only one is registered on Helix must not also
/// show up as "not on Helix" for the other.
Map<String, Set<String>> groupPhoneBookHashesByName({
  required List<PhoneBookContact> contacts,
  required String discoverySaltBase64,
}) {
  final hashesByName = <String, Set<String>>{};
  for (final contact in contacts) {
    final name = contact.displayName.trim();
    if (name.isEmpty) continue;
    for (final rawNumber in contact.phoneNumbers) {
      final normalized = RemoteAccountValidation.normalizePhoneNumber(
        rawNumber,
      );
      if (!RemoteAccountValidation.isValidPhoneNumber(normalized)) continue;
      final hash = phoneHash(discoverySaltBase64, normalized);
      (hashesByName[name] ??= <String>{}).add(hash);
    }
  }
  return hashesByName;
}

/// The normalized number behind each phone-book hash, so a match can be
/// remembered with its number (for renaming it back into the phone book).
Map<String, String> phoneBookNumbersByHash({
  required List<PhoneBookContact> contacts,
  required String discoverySaltBase64,
}) {
  final numbers = <String, String>{};
  for (final contact in contacts) {
    for (final rawNumber in contact.phoneNumbers) {
      final normalized = RemoteAccountValidation.normalizePhoneNumber(
        rawNumber,
      );
      if (!RemoteAccountValidation.isValidPhoneNumber(normalized)) continue;
      numbers.putIfAbsent(
        phoneHash(discoverySaltBase64, normalized),
        () => normalized,
      );
    }
  }
  return numbers;
}
