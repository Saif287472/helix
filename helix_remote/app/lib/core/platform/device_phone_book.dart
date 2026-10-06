import 'package:helix_remote/core/platform/contacts_access.dart';
import 'package:helix_remote/core/platform/phone_numbers.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';

/// The phone's address book, for discovery.
///
/// The engine never reads contacts itself: it hashes the numbers on the
/// device and asks the server which hashes belong to accounts
/// (`POST /v1/people/discover`). Nothing but hashes leaves the device.
///
/// This is the engine's [PhoneBook] over a [ContactsAccess]. It never shows a
/// permission dialog: the people feature asks first (with an explanation), and
/// without the permission this answers empty - discovery is an optimisation
/// and anybody can still be found by number or `~Helix name`.
final class DevicePhoneBook implements PhoneBook {
  const DevicePhoneBook({
    ContactsAccess access = const FlutterContactsAccess(),
    PhoneCountry? country,
  }) : _access = access,
       _country = country;

  final ContactsAccess _access;

  /// Where bare national numbers are read; null reads only international ones.
  final PhoneCountry? _country;

  @override
  Future<List<PhoneBookEntry>> entries() async {
    final entries = <PhoneBookEntry>[];
    for (final contact in await _access.readAll()) {
      final numbers = {
        for (final raw in contact.numbers)
          ?PhoneNumbers.normalize(
            raw,
            defaultCallingCode: _country?.callingCode,
          ),
      };
      if (numbers.isEmpty) continue;
      entries.add(
        PhoneBookEntry(name: contact.name.trim(), numbers: numbers.toList()),
      );
    }
    return entries;
  }

  /// Renames the contact that holds [number], or creates one. False when the
  /// phone refused (no permission, no address book).
  @override
  Future<bool> saveName(String number, String name) async {
    final e164 = PhoneNumbers.normalize(
      number,
      defaultCallingCode: _country?.callingCode,
    );
    if (e164 == null || name.trim().isEmpty) return false;
    String? existing;
    for (final contact in await _access.readAll()) {
      final holds = contact.numbers.any(
        (raw) =>
            PhoneNumbers.normalize(
              raw,
              defaultCallingCode: _country?.callingCode,
            ) ==
            e164,
      );
      if (holds) {
        existing = contact.id;
        break;
      }
    }
    return _access.saveName(
      contactId: existing,
      number: e164,
      name: name.trim(),
    );
  }
}
