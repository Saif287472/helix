import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart' hide GroupRole;
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/groups/group_ids.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// What the server stores about a group in plain form, plus what only the
/// members can read, kept next to the `groups` row. The schema has no
/// column for these, so they live in `settings` (plan §3.8: tables arrive
/// with the feature that needs them queryable).
final class GroupMeta {
  const GroupMeta({
    this.settings = const GroupSettings(),
    this.description,
    this.homeServer,
    this.avatar,
  });

  final GroupSettings settings;

  /// From the decrypted state; null until the group key has arrived.
  final String? description;

  /// The authoritative server's domain for a federated group.
  final String? homeServer;

  /// The group picture's `MediaPointer` JSON, from the decrypted state.
  final JsonMap? avatar;

  JsonMap toJson() => compact({
    'settings': settings.toJson(),
    'description': description,
    'home_server': homeServer,
    'avatar': avatar,
  });

  static GroupMeta decode(String? stored) {
    if (stored == null) return const GroupMeta();
    try {
      final json = JsonReader.decode(stored);
      return GroupMeta(
        settings: json.has('settings')
            ? GroupSettings.fromJson(json.object('settings'))
            : const GroupSettings(),
        description: json.optString('description'),
        homeServer: json.optString('home_server'),
        avatar: json.optObject('avatar')?.json,
      );
    } on FormatException {
      return const GroupMeta();
    }
  }
}

/// The group master keys (CRYPTO_V2.md §9) and the sealing of the group
/// state blob.
///
/// A group has one master key per epoch. The server stores the state blob
/// sealed under the epoch it was last written in, so after a removal bumps
/// the epoch the blob can still be under the old key until a member re-seals
/// it: opening tries the held epochs from the newest down. Keys live in
/// `settings` as `group.keys.<group id>` (epoch to key); only the newest
/// [GroupLimits.keptEpochKeys] are kept. The database is SQLCipher-protected
/// like every other key here.
final class GroupKeyring {
  GroupKeyring(this._ctx);

  final EngineContext _ctx;

  static Setting<String?> _keys(String groupId) =>
      Setting<String?>('group.keys.$groupId', null);

  static Setting<String?> _meta(String groupId) =>
      Setting<String?>('group.meta.$groupId', null);

  // ---------------------------------------------------------------- keys

  /// The held keys of [groupId], by epoch.
  Future<Map<int, Uint8List>> keys(String groupId) async {
    final stored = await _ctx.db.settingsDao.get(_keys(groupId));
    if (stored == null) return {};
    try {
      final json = (jsonDecode(stored) as Map).cast<String, Object?>();
      return {
        for (final e in json.entries)
          if (int.tryParse(e.key) != null && e.value is String)
            int.parse(e.key): decodeBytes(e.value! as String),
      };
    } on Object {
      return {};
    }
  }

  Future<Uint8List?> keyFor(String groupId, int epoch) async =>
      (await keys(groupId))[epoch];

  /// Stores the key of [epoch], dropping the oldest beyond the kept count.
  Future<void> put(String groupId, int epoch, List<int> key) async {
    final all = await keys(groupId);
    all[epoch] = Uint8List.fromList(key);
    final epochs = all.keys.toList()..sort();
    while (epochs.length > GroupLimits.keptEpochKeys) {
      all.remove(epochs.removeAt(0));
    }
    await _ctx.db.settingsDao.set(
      _keys(groupId),
      jsonEncode({
        for (final e in all.entries) '${e.key}': encodeBytes(e.value),
      }),
      now: _ctx.now(),
    );
  }

  Future<void> forget(String groupId) async {
    await _ctx.db.settingsDao.reset(_keys(groupId));
    await _ctx.db.settingsDao.reset(_meta(groupId));
  }

  // ---------------------------------------------------------------- meta

  Future<GroupMeta> meta(String groupId) async =>
      GroupMeta.decode(await _ctx.db.settingsDao.get(_meta(groupId)));

  Future<void> saveMeta(String groupId, GroupMeta meta) => _ctx.db.settingsDao
      .set(_meta(groupId), jsonEncode(meta.toJson()), now: _ctx.now());

  // --------------------------------------------------------------- state

  /// Seals [state] for [groupId] under the key of [epoch] (the group's
  /// current epoch) as the state of [version]. The server's version starts at
  /// [GroupLimits.initialStateVersion] and rises by one per accepted write, so
  /// a write over version `v` is sealed for `v + 1`; the version is part of
  /// the AAD (CRYPTO_V2.md section 9).
  Future<Uint8List> sealState(
    String groupId,
    int epoch,
    int version,
    List<int> key,
    GroupStateContent state,
  ) => SealedBlobCipher.groupState.seal(
    secret: key,
    plaintext: utf8.encode(jsonEncode(state.toJson())),
    aad: SealedBlobCipher.groupStateAad(groupId, epoch, version),
    random: _ctx.random,
  );

  /// Opens [blob] with the held keys, newest epoch at or below [epoch]
  /// first. Null when no held key opens it (the key has not arrived yet, or
  /// the blob is not ours to read).
  Future<GroupStateContent?> openState(
    String groupId,
    List<int> blob, {
    required int epoch,
    required int version,
  }) async {
    final held = await keys(groupId);
    final order = held.keys.toList()
      ..sort((a, b) {
        // At or below the group's epoch first, newest first; then the rest.
        final aOk = a <= epoch;
        final bOk = b <= epoch;
        if (aOk != bOk) return aOk ? -1 : 1;
        return b.compareTo(a);
      });
    for (final e in order) {
      final content = await tryOpen(groupId, blob, e, version, held[e]!);
      if (content != null) return content;
    }
    return null;
  }

  /// [blob] opened with [key] as the state of [epoch] and [version], or null.
  Future<GroupStateContent?> tryOpen(
    String groupId,
    List<int> blob,
    int epoch,
    int version,
    List<int> key,
  ) async {
    try {
      final plain = await SealedBlobCipher.groupState.open(
        secret: key,
        blob: blob,
        aad: SealedBlobCipher.groupStateAad(groupId, epoch, version),
      );
      return GroupStateContent.fromJson(JsonReader.decode(utf8.decode(plain)));
    } on CryptoV2Exception {
      return null;
    } on FormatException {
      return null;
    }
  }
}
