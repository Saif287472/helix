import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One account this device remembers on the sign-in page: enough to prefill
/// the number, never enough to sign in. The password is not here, and the
/// list survives sign-out, which wipes the account's data but not this.
///
/// The full account-switching design grows this entry (account id, database
/// file, keystore key name); until then it only feeds the sign-in page.
class SavedAccountEntry {
  const SavedAccountEntry({
    required this.e164,
    required this.server,
    this.name = '',
  });

  /// The number in E.164, as typed for sign-in.
  final String e164;

  /// The server the account is on; only entries for the server the person
  /// is signing in to are offered.
  final String server;

  /// The name the account went by, when it is known.
  final String name;

  SavedAccountEntry withName(String name) => SavedAccountEntry(
    e164: e164,
    server: server,
    name: name.isEmpty ? this.name : name,
  );

  factory SavedAccountEntry.fromJson(Map<String, Object?> json) =>
      SavedAccountEntry(
        e164: json['n'] as String? ?? '',
        server: json['s'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );

  Map<String, Object?> toJson() => {'n': e164, 's': server, 'name': name};
}

/// The sign-in page's remembered numbers, one JSON list in the keystore.
///
/// Most recent first; numbers are unique. Only this class writes it, so the
/// shape stays an implementation detail.
final class SavedAccountsStore {
  SavedAccountsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = keystoreKey;

  /// The keystore key the list lives under; tests seed it with
  /// `FlutterSecureStorage.setMockInitialValues`.
  static const keystoreKey = 'helix_remote_saved_accounts';

  final FlutterSecureStorage _storage;

  Future<List<SavedAccountEntry>> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, Object?>>();
      return [
        for (final json in list)
          if ((json['n'] as String? ?? '').isNotEmpty)
            SavedAccountEntry.fromJson(json),
      ];
    } on Object {
      // Something unreadable was never written by this code; start over
      // rather than failing sign-in.
      return const [];
    }
  }

  /// Puts [entry] first, replacing an entry with the same number.
  Future<void> remember(SavedAccountEntry entry) async {
    final rest = (await load()).where((e) => e.e164 != entry.e164).toList();
    await _write([entry, ...rest]);
  }

  Future<void> forget(String e164) async =>
      _write((await load()).where((e) => e.e164 != e164).toList());

  Future<void> _write(List<SavedAccountEntry> entries) => entries.isEmpty
      ? _storage.delete(key: _key)
      : _storage.write(
          key: _key,
          value: jsonEncode([for (final e in entries) e.toJson()]),
        );
}

/// "+880 ••••• 0001": the country code and the last four, nothing between.
String maskNumber(String e164, {required String countryCode}) =>
    e164.length <= 4
    ? '•' * e164.length
    : '$countryCode ••••• ${e164.substring(e164.length - 4)}';
