// The package exposes CRUD through `CrudApi`, which the barrel does not
// re-export, so its library is imported directly.
import 'package:flutter_contacts/api/crud_api.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';

/// The phone's address book, for discovery.
///
/// The engine never reads contacts itself: it hashes the numbers on the
/// device and asks the server which hashes belong to accounts
/// (`POST /v1/people/discover`). Nothing but hashes leaves the device.
///
/// Every method answers empty rather than throwing. Windows has no address
/// book, a person can refuse access, and discovery is an optimisation anyway:
/// anybody can still be found by number or `~Helix name`.
final class DevicePhoneBook implements PhoneBook {
  const DevicePhoneBook();

  static const _contacts = CrudApi.instance;

  @override
  Future<List<PhoneBookEntry>> entries() async {
    try {
      final contacts = await _contacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone},
      );
      final entries = <PhoneBookEntry>[];
      for (final contact in contacts) {
        final numbers = <String>[];
        for (final phone in contact.phones) {
          // `normalizedNumber` is the platform's own E.164 where it has one.
          final e164 = toE164(phone.normalizedNumber ?? phone.number);
          if (e164 != null) numbers.add(e164);
        }
        if (numbers.isEmpty) continue;
        entries.add(
          PhoneBookEntry(
            name: (contact.displayName ?? '').trim(),
            numbers: numbers,
          ),
        );
      }
      return entries;
    } on Object {
      return const [];
    }
  }

  @override
  Future<bool> saveName(String number, String name) async {
    try {
      final e164 = toE164(number);
      if (e164 == null) return false;
      final contacts = await _contacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone},
        filter: ContactFilter.phone(e164),
      );
      if (contacts.isEmpty) return false;
      await _contacts.update(contacts.first.copyWith(name: Name(first: name)));
      return true;
    } on Object {
      return false;
    }
  }

  /// Normalises a stored contact number to E.164, or null when it is not a
  /// number this app can match on.
  ///
  /// Contacts are stored in local formats (`01711000001`, `+880 1711-000001`),
  /// so this only trims, removes separators and expands an international
  /// prefix. It never guesses a country code: a bare national number cannot be
  /// matched against a server-side hash without knowing which country it is
  /// from, and guessing would find the wrong people.
  static String? toE164(String raw) {
    var digits = raw.trim().replaceAll(RegExp(r'[\s()\-.]'), '');
    if (digits.startsWith('00')) {
      digits = '+${digits.substring(2)}';
    } else if (digits.startsWith('+')) {
      // Already international.
    } else {
      return RegExp(r'^[1-9]\d{6,14}$').hasMatch(digits) ? '+$digits' : null;
    }
    return RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(digits) ? digits : null;
  }
}
