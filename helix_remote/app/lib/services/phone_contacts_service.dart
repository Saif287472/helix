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
}

class DevicePhoneContactsService implements PhoneContactsService {
  const DevicePhoneContactsService();

  @override
  Future<PhoneContactsPermissionResult> requestPermission() async {
    final granted = await fc.FlutterContacts.requestPermission(readonly: true);
    return granted
        ? PhoneContactsPermissionResult.granted
        : PhoneContactsPermissionResult.denied;
  }

  @override
  Future<List<PhoneBookContact>> loadContacts() async {
    final contacts = await fc.FlutterContacts.getContacts(withProperties: true);
    return contacts
        .map(
          (c) => PhoneBookContact(
            displayName: c.displayName,
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
