import 'package:meta/meta.dart';

/// One contact in the phone's address book.
@immutable
final class PhoneBookEntry {
  const PhoneBookEntry({required this.name, required this.numbers});

  final String name;

  /// Numbers in E.164 (`+8801711000001`); the host normalises them.
  final List<String> numbers;
}

/// The phone's address book, injected by the host (Android contacts,
/// Windows has none, the CLI a fake). The engine never reads contacts on its
/// own and never uploads them: it hashes the numbers on the device and asks
/// the server which hashes belong to accounts (`POST /v1/people/discover`).
abstract interface class PhoneBook {
  /// Every contact with at least one number.
  Future<List<PhoneBookEntry>> entries();

  /// Writes [name] for [number] into the phone's contacts (renaming someone
  /// in Helix renames them there too, AGENTS.md product rules). Returns
  /// false when the host cannot (no permission, no address book).
  Future<bool> saveName(String number, String name);
}

/// A phone book with nobody in it (CLI, tests, a user who denied access).
final class EmptyPhoneBook implements PhoneBook {
  const EmptyPhoneBook();

  @override
  Future<List<PhoneBookEntry>> entries() async => const [];

  @override
  Future<bool> saveName(String number, String name) async => false;
}
