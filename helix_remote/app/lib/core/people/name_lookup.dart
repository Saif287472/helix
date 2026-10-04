import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote_db/helix_remote_db.dart' show PersonRow;
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Names for the people a screen mentions: the call log, a call in progress,
/// a group's members.
///
/// This is the **replaceable adapter** for the people-naming order (phone-book
/// name, then nickname, then number, then `~Helix name`). The people feature
/// owns the order for chats and search; features may not import each other, so
/// calls and groups read it through here. When the people feature publishes
/// its own provider, change only the body of [peopleNamesProvider] to map from
/// it - every caller keeps working.
final peopleNamesProvider = StreamProvider<PeopleNames>((ref) async* {
  final runtime = await ref.watch(runtimeProvider.future);
  yield* runtime.engine.people.watchAll().map(PeopleNames.fromRows);
});

/// A lookup from account id to the names this device has for that account.
final class PeopleNames {
  const PeopleNames(this._byAccount);

  factory PeopleNames.fromRows(Iterable<PersonRow> rows) =>
      PeopleNames({for (final row in rows) row.accountId: namesOf(row)});

  /// Nobody known: every account shows as a `Helix user`.
  static const empty = PeopleNames({});

  final Map<String, HelixPersonNames> _byAccount;

  /// The names for [account], or - for someone this device has no row for -
  /// [fallbackName] (a name the server or a roster gave, shown as a
  /// `~Helix name`), or just `Helix user`.
  HelixPersonNames of(String account, {String? fallbackName}) {
    final known = _byAccount[account];
    if (known != null) return known;
    final name = fallbackName?.trim();
    return HelixPersonNames(
      helixName: name == null || name.isEmpty ? null : name,
    );
  }

  /// [HelixPersonNames.display] of [account].
  String displayName(String account, {String? fallbackName}) =>
      of(account, fallbackName: fallbackName).display;

  /// Accounts with a stored row, in no particular order.
  Iterable<String> get accounts => _byAccount.keys;

  /// The people whose display name, secondary line or number contains
  /// [query] (case-insensitive), for a local filter.
  Iterable<String> matching(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return accounts;
    return [
      for (final entry in _byAccount.entries)
        if (_matches(entry.value, needle)) entry.key,
    ];
  }

  static bool _matches(HelixPersonNames names, String needle) =>
      names.display.toLowerCase().contains(needle) ||
      (names.number ?? '').toLowerCase().contains(needle) ||
      (names.helixName ?? '').toLowerCase().contains(needle) ||
      (names.nickname ?? '').toLowerCase().contains(needle) ||
      (names.phoneBookName ?? '').toLowerCase().contains(needle);
}

/// A row's four names, in the shape the UI package renders. A profile name
/// stands in for a missing `~Helix name` (the `~` marks a name the person
/// chose themselves rather than one this device knows them by).
HelixPersonNames namesOf(PersonRow row) {
  String? clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  return HelixPersonNames(
    phoneBookName: clean(row.phonebookName),
    nickname: clean(row.nickname),
    number: clean(row.phoneNumber),
    helixName: clean(row.helixName) ?? clean(row.profileName),
  );
}
