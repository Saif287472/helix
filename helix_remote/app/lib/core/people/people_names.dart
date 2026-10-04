import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote_db/helix_remote_db.dart' show PersonRow;
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show PersonNaming, maskPhone, shortId;
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// How a person is named, everywhere in the app.
///
/// The order is the product rule (AGENTS.md): the **phone-book name**, then
/// the **nickname** the user gave, then the **number**, then `~Helix name`. The
/// engine's [PersonNaming] adds the two fallbacks that keep a row from ever
/// being blank - the name the person chose for themselves, then a short id -
/// and [PersonName.display] is exactly what it answers, so the chat list, a
/// group's member list, the call screen and a notification can never disagree.
///
/// Every feature that draws a person reads it from here:
///
/// ```dart
/// // In a mapper or a provider (application/):
/// final people = ref.watch(peopleDirectoryProvider).value;
/// final name = people?.nameOf(accountId) ?? PersonName.unknown(accountId);
///
/// // For one person, rebuilt only when that person's name changes:
/// final name = ref.watch(personNameProvider(accountId));
/// ```
///
/// Both are reactive: renaming someone, a phone-book sync that finds them or a
/// profile arriving changes the value, and everything watching it redraws.
final class PersonName {
  const PersonName({
    required this.accountId,
    required this.names,
    required this.display,
    this.profileName,
    this.phoneNumber,
    this.helixName,
    this.blocked = false,
    this.verified = false,
    this.image,
    this.avatarBytes,
  });

  /// A person this device knows nothing about yet (a stranger's message that
  /// arrived before their row, a deleted account): the id's short form, or
  /// the server for a federated `uuid@domain`.
  factory PersonName.unknown(String accountId) {
    final at = accountId.indexOf('@');
    final id = at < 0 ? accountId : accountId.substring(0, at);
    final domain = at < 0 ? null : accountId.substring(at + 1);
    final short = id.length <= 8 ? id : id.substring(0, 8);
    return PersonName(
      accountId: accountId,
      names: const HelixPersonNames(),
      display: domain == null
          ? 'Helix user $short'
          : 'Helix user $short ($domain)',
    );
  }

  /// Builds the name of [row] by the engine's naming order.
  factory PersonName.fromRow(PersonRow row, {PersonName? previous}) {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    }

    final bytes = row.avatarBlob;
    ImageProvider? image;
    if (bytes != null && bytes.isNotEmpty) {
      final before = previous?.avatarBytes;
      image = before != null && listEquals(before, bytes)
          ? previous!.image
          : MemoryImage(bytes);
    }
    final names = HelixPersonNames(
      phoneBookName: clean(row.phonebookName),
      nickname: clean(row.nickname),
      number: clean(row.phoneNumber),
      helixName: clean(row.helixName),
    );
    final profileName = clean(row.profileName);
    return PersonName(
      accountId: row.accountId,
      names: names,
      // The four rungs by the product's order, trimmed; below them the engine's
      // own fallbacks (the name the person chose, then a short id), and a
      // person on another server gets that server beside the short id so two
      // strangers are not confused.
      display: names.source != HelixNameSource.unknown
          ? names.display
          : profileName ??
                (row.accountId.contains('@')
                    ? PersonName.unknown(row.accountId).display
                    : PersonNaming.displayName(row)),
      profileName: profileName,
      phoneNumber: clean(row.phoneNumber),
      helixName: clean(row.helixName),
      blocked: row.blocked,
      verified: row.identityVerified,
      image: image,
      avatarBytes: bytes,
    );
  }

  final String accountId;

  /// The four rungs of the naming order, for the components that show a name
  /// with a line under it ([HelixPersonTile], [HelixPersonNames.secondary]).
  final HelixPersonNames names;

  /// The one name to show: never empty.
  final String display;

  /// The name the person chose for themselves (their encrypted profile). Not
  /// part of the product's naming order; only the last-resort fallback in
  /// [display].
  final String? profileName;
  final String? phoneNumber;
  final String? helixName;
  final bool blocked;
  final bool verified;

  /// Their picture, when this device has one.
  final ImageProvider? image;

  /// The picture's bytes, kept so a rebuild of the directory can reuse the
  /// decoded image when nothing changed.
  final Uint8List? avatarBytes;

  /// Which rung of the naming order produced [display].
  HelixNameSource get source => names.source;

  /// The avatar the components draw.
  HelixAvatarModel get avatar => HelixAvatarModel(
    name: display,
    image: image,
    colorIndex: HelixAvatarModel.colorIndexFor(accountId),
  );

  /// This person as a people-list row.
  HelixPersonItem toItem({bool online = false, String? about}) =>
      HelixPersonItem(
        id: accountId,
        names: names,
        image: image,
        about: about,
        online: online,
        blocked: blocked,
      );

  /// The number for a log line or an error: never the whole thing
  /// (`+88017*****01`). Screens show the full number to its owner; nothing
  /// else may.
  String? get maskedNumber {
    final number = phoneNumber;
    return number == null ? null : maskPhone(number);
  }

  /// [display], with the last four digits of the number or the `~Helix name`
  /// added when [collides] (two people the user knows by the same name).
  String labelWhen({required bool collides}) {
    if (!collides) return display;
    final number = phoneNumber;
    if (number != null && number.length >= 4) {
      return '$display (…${number.substring(number.length - 4)})';
    }
    final helix = helixName;
    if (helix != null) return '$display (~$helix)';
    return '$display (${shortId(accountId)})';
  }

  @override
  bool operator ==(Object other) =>
      other is PersonName &&
      other.accountId == accountId &&
      other.names == names &&
      other.display == display &&
      other.profileName == profileName &&
      other.blocked == blocked &&
      other.verified == verified &&
      other.image == image;

  @override
  int get hashCode => Object.hash(
    accountId,
    names,
    display,
    profileName,
    blocked,
    verified,
    image,
  );
}

/// Everyone this device knows, by account id.
final class PeopleDirectory {
  const PeopleDirectory(this.byId);

  static const empty = PeopleDirectory({});

  final Map<String, PersonName> byId;

  /// Maps the engine's people rows, reusing [previous] images that did not
  /// change.
  factory PeopleDirectory.fromRows(
    Iterable<PersonRow> rows, {
    PeopleDirectory? previous,
  }) => PeopleDirectory({
    for (final row in rows)
      row.accountId: PersonName.fromRow(
        row,
        previous: previous?.byId[row.accountId],
      ),
  });

  /// The name of [accountId]; [PersonName.unknown] for a stranger.
  PersonName nameOf(String accountId) =>
      byId[accountId] ?? PersonName.unknown(accountId);

  /// The name of the other person in a direct conversation id
  /// (`direct:<account>`), or null for a group or anything else.
  PersonName? nameOfConversation(String conversationId) {
    const prefix = 'direct:';
    if (!conversationId.startsWith(prefix)) return null;
    return nameOf(conversationId.substring(prefix.length));
  }

  /// Whether another person is shown under the same name as [accountId], so a
  /// list can add something to tell them apart (see
  /// [PersonName.labelWhen]).
  bool collides(String accountId) {
    final mine = byId[accountId];
    if (mine == null) return false;
    for (final other in byId.values) {
      if (other.accountId != accountId &&
          other.display.toLowerCase() == mine.display.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  /// [PersonName.display], disambiguated when two people share it.
  String labelOf(String accountId) =>
      nameOf(accountId).labelWhen(collides: collides(accountId));

  /// Everyone, in naming order.
  Iterable<PersonName> get all => byId.values;
}

/// The engine's people rows, live: the one query behind every name in the
/// app. Tests override this with a stream of rows.
final peopleRowsProvider = StreamProvider<List<PersonRow>>((ref) async* {
  final runtime = await ref.watch(runtimeProvider.future);
  yield* runtime.engine.people.watchAll();
});

/// The directory of everyone this device knows, live.
///
/// One stream over the engine's people watch query, however many rows read it
/// (a chat list of 5,000 rows must not open 5,000 queries).
final peopleDirectoryProvider = StreamProvider<PeopleDirectory>((ref) {
  final controller = StreamController<PeopleDirectory>();
  // Each emission maps from the previous directory, so an avatar that did not
  // change is not decoded again.
  var current = PeopleDirectory.empty;
  ref.listen<AsyncValue<List<PersonRow>>>(peopleRowsProvider, (_, next) {
    switch (next) {
      case AsyncData(:final value):
        current = PeopleDirectory.fromRows(value, previous: current);
        controller.add(current);
      case AsyncError(:final error, :final stackTrace):
        controller.addError(error, stackTrace);
      case AsyncLoading():
        break;
    }
  }, fireImmediately: true);
  ref.onDispose(controller.close);
  return controller.stream;
});

/// One person's name. Only rebuilds the watcher when **that** person's name,
/// avatar, block or verified state changes, not on every change to the
/// directory. A stranger gets [PersonName.unknown] until the row exists.
final personNameProvider = Provider.family<PersonName, String>((ref, id) {
  final found = ref.watch(
    peopleDirectoryProvider.select((directory) => directory.value?.byId[id]),
  );
  return found ?? PersonName.unknown(id);
});
