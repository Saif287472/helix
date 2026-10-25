import 'dart:convert';
import 'dart:math';
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
/// `settings` one row per epoch, `group.key.<group id>.<epoch>`; only the
/// newest [GroupLimits.keptEpochKeys] are kept. An epoch may hold a second
/// key, `group.key.<group id>.<epoch>.candidate`, while the stored state
/// cannot say which of two arrivals is the group's (AUD-12f-3; the decision
/// is [GroupKeyAuthority]'s). The per-field rows make a key write one
/// upsert, so two rotations cannot drop each other's epoch (AUD-12e-2), and
/// the same holds for the group's metadata below. The database is
/// SQLCipher-protected like every other key here.
final class GroupKeyring {
  GroupKeyring(this._ctx);

  final EngineContext _ctx;

  static const _candidateSuffix = '.candidate';

  static String _keyPrefix(String groupId) => 'group.key.$groupId.';

  static String _metaPrefix(String groupId) => 'group.meta.$groupId.';

  /// The whole-map document written before AUD-12e-2.
  static Setting<String?> _legacyKeys(String groupId) =>
      Setting<String?>('group.keys.$groupId', null);

  /// The one-document metadata written before AUD-12e-2.
  static Setting<String?> _metaDoc(String groupId) =>
      Setting<String?>('group.meta.$groupId', null);

  static Setting<String?> _keyRow(String groupId, int epoch) =>
      Setting<String?>('${_keyPrefix(groupId)}$epoch', null);

  static Setting<String?> _candidateRow(String groupId, int epoch) =>
      Setting<String?>('${_keyPrefix(groupId)}$epoch$_candidateSuffix', null);

  static Setting<String?> _metaSettings(String groupId) =>
      Setting<String?>('${_metaPrefix(groupId)}settings', null);

  static Setting<String?> _metaDescription(String groupId) =>
      Setting<String?>('${_metaPrefix(groupId)}description', null);

  static Setting<String?> _metaHomeServer(String groupId) =>
      Setting<String?>('${_metaPrefix(groupId)}home_server', null);

  static Setting<String?> _metaAvatar(String groupId) =>
      Setting<String?>('${_metaPrefix(groupId)}avatar', null);

  SettingsDao get _settings => _ctx.db.settingsDao;

  // ---------------------------------------------------------------- keys

  /// Moves the pre-AUD-12e-2 epoch map into rows, then drops it.
  Future<void> _migrateKeys(String groupId) async {
    final stored = await _settings.get(_legacyKeys(groupId));
    if (stored == null) return;
    try {
      final json = (jsonDecode(stored) as Map).cast<String, Object?>();
      final now = _ctx.now();
      for (final entry in json.entries) {
        final epoch = int.tryParse(entry.key);
        if (epoch == null || entry.value is! String) continue;
        await _settings.set(
          _keyRow(groupId, epoch),
          entry.value! as String,
          now: now,
        );
      }
    } on Object {
      // A corrupt document holds no key, exactly as the old parser read it.
    }
    await _settings.reset(_legacyKeys(groupId));
  }

  /// The held keys of [groupId], by epoch.
  Future<Map<int, Uint8List>> keys(String groupId) async {
    await _migrateKeys(groupId);
    final prefix = _keyPrefix(groupId);
    final rows = await _settings.entriesWithPrefix(prefix);
    final held = <int, Uint8List>{};
    for (final row in rows.entries) {
      final epoch = int.tryParse(row.key.substring(prefix.length));
      if (epoch == null) continue; // A `.candidate` row is not the primary.
      final key = _decodeKey(row.value);
      if (key != null) held[epoch] = key;
    }
    return held;
  }

  /// The second key held for each epoch, by epoch.
  Future<Map<int, Uint8List>> _candidates(String groupId) async {
    final prefix = _keyPrefix(groupId);
    final rows = await _settings.entriesWithPrefix(prefix);
    final held = <int, Uint8List>{};
    for (final row in rows.entries) {
      final suffix = row.key.substring(prefix.length);
      if (!suffix.endsWith(_candidateSuffix)) continue;
      final epoch = int.tryParse(
        suffix.substring(0, suffix.length - _candidateSuffix.length),
      );
      if (epoch == null) continue;
      final key = _decodeKey(row.value);
      if (key != null) held[epoch] = key;
    }
    return held;
  }

  static Uint8List? _decodeKey(String? stored) {
    if (stored == null) return null;
    try {
      final encoded = jsonDecode(stored);
      return encoded is String ? decodeBytes(encoded) : null;
    } on FormatException {
      // A corrupt row holds no key; it must not fail every reader.
      return null;
    }
  }

  Future<Uint8List?> keyFor(String groupId, int epoch) async =>
      (await keys(groupId))[epoch];

  /// The second key held for [epoch], when the stored state could not say
  /// which of two arrivals is the group's.
  Future<Uint8List?> candidateFor(String groupId, int epoch) async =>
      (await _candidates(groupId))[epoch];

  /// Stores the key of [epoch] as its primary, dropping the oldest epochs
  /// beyond the kept count (both keys of a dropped epoch go).
  Future<void> put(String groupId, int epoch, List<int> key) async {
    await _migrateKeys(groupId);
    final now = _ctx.now();
    await _settings.set(_keyRow(groupId, epoch), encodeBytes(key), now: now);
    final candidate = await candidateFor(groupId, epoch);
    if (candidate != null && bytesEqual(candidate, key)) {
      await _settings.reset(_candidateRow(groupId, epoch));
    }
    final epochs = (await keys(groupId)).keys.toList()..sort();
    final excess = max(0, epochs.length - GroupLimits.keptEpochKeys);
    for (final stale in epochs.take(excess)) {
      await _settings.reset(_keyRow(groupId, stale));
      await _settings.reset(_candidateRow(groupId, stale));
    }
  }

  /// Keeps [key] as the second key of [epoch], beside the primary.
  Future<void> putCandidate(String groupId, int epoch, List<int> key) async {
    await _migrateKeys(groupId);
    final primary = await keyFor(groupId, epoch);
    if (primary != null && bytesEqual(primary, key)) return;
    await _settings.set(
      _candidateRow(groupId, epoch),
      encodeBytes(key),
      now: _ctx.now(),
    );
  }

  /// Makes [key] the primary of [epoch]; the key it replaces stays as the
  /// second one, since a later state write may still be sealed under it. The
  /// primary is written first so a crash between the two writes keeps the
  /// key that was just verified, never only the one it replaced.
  Future<void> promote(String groupId, int epoch, List<int> key) async {
    await _migrateKeys(groupId);
    final previous = await keyFor(groupId, epoch);
    if (previous != null && bytesEqual(previous, key)) return;
    final now = _ctx.now();
    await _settings.set(_keyRow(groupId, epoch), encodeBytes(key), now: now);
    if (previous != null) {
      await _settings.set(
        _candidateRow(groupId, epoch),
        encodeBytes(previous),
        now: now,
      );
    }
  }

  Future<void> forget(String groupId) async {
    await _settings.resetWithPrefix(_keyPrefix(groupId));
    await _settings.reset(_legacyKeys(groupId));
    await _settings.resetWithPrefix(_metaPrefix(groupId));
    await _settings.reset(_metaDoc(groupId));
  }

  // ---------------------------------------------------------------- meta

  /// Moves the pre-AUD-12e-2 metadata document into rows, then drops it.
  /// Fields that already have a row are kept: a write that landed while the
  /// migration ran is newer than the document.
  Future<void> _migrateMeta(String groupId) async {
    final raw = await _settings.get(_metaDoc(groupId));
    if (raw == null) return;
    final meta = GroupMeta.decode(raw);
    final now = _ctx.now();
    if (await _settings.get(_metaSettings(groupId)) == null) {
      await _settings.set(
        _metaSettings(groupId),
        jsonEncode(meta.settings.toJson()),
        now: now,
      );
    }
    if (meta.description != null &&
        await _settings.get(_metaDescription(groupId)) == null) {
      await _settings.set(
        _metaDescription(groupId),
        meta.description!,
        now: now,
      );
    }
    if (meta.homeServer != null &&
        await _settings.get(_metaHomeServer(groupId)) == null) {
      await _settings.set(_metaHomeServer(groupId), meta.homeServer!, now: now);
    }
    if (meta.avatar != null &&
        await _settings.get(_metaAvatar(groupId)) == null) {
      await _settings.set(
        _metaAvatar(groupId),
        jsonEncode(meta.avatar),
        now: now,
      );
    }
    await _settings.reset(_metaDoc(groupId));
  }

  Future<GroupMeta> meta(String groupId) async {
    await _migrateMeta(groupId);
    return GroupMeta(
      settings: _decodeSettings(await _settings.get(_metaSettings(groupId))),
      description: await _settings.get(_metaDescription(groupId)),
      homeServer: await _settings.get(_metaHomeServer(groupId)),
      avatar: _decodeMap(await _settings.get(_metaAvatar(groupId))),
    );
  }

  /// The fields the server states in plain form (they arrive with every
  /// roster read, so they are the server's to set, not the state's).
  Future<void> saveServerMeta(
    String groupId, {
    required GroupSettings settings,
    String? homeServer,
  }) async {
    await _migrateMeta(groupId);
    final now = _ctx.now();
    await _settings.set(
      _metaSettings(groupId),
      jsonEncode(settings.toJson()),
      now: now,
    );
    if (homeServer == null) {
      await _settings.reset(_metaHomeServer(groupId));
    } else {
      await _settings.set(_metaHomeServer(groupId), homeServer, now: now);
    }
  }

  /// The fields that come from the decrypted state. Null clears the stored
  /// value: the state, which only members can read, says there is none.
  ///
  /// Separate from [saveServerMeta] so a roster read and a state re-open
  /// write disjoint rows rather than read-modify-writing one document
  /// (AUD-12e-2: the loser restored an old description).
  Future<void> saveContentMeta(
    String groupId, {
    String? description,
    JsonMap? avatar,
  }) async {
    await _migrateMeta(groupId);
    final now = _ctx.now();
    if (description == null) {
      await _settings.reset(_metaDescription(groupId));
    } else {
      await _settings.set(_metaDescription(groupId), description, now: now);
    }
    if (avatar == null) {
      await _settings.reset(_metaAvatar(groupId));
    } else {
      await _settings.set(_metaAvatar(groupId), jsonEncode(avatar), now: now);
    }
  }

  static GroupSettings _decodeSettings(String? stored) {
    if (stored == null) return const GroupSettings();
    try {
      return GroupSettings.fromJson(JsonReader.decode(stored));
    } on FormatException {
      return const GroupSettings();
    }
  }

  static JsonMap? _decodeMap(String? stored) {
    if (stored == null) return null;
    try {
      return JsonReader.decode(stored).json;
    } on FormatException {
      return null;
    }
  }

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
    final opened = await openStateWithKey(
      groupId,
      blob,
      epoch: epoch,
      version: version,
    );
    return opened?.content;
  }

  /// [openState] and the key that opened [blob]: the primary of an epoch is
  /// tried before its second key.
  Future<({GroupStateContent content, int epoch, Uint8List key})?>
  openStateWithKey(
    String groupId,
    List<int> blob, {
    required int epoch,
    required int version,
  }) async {
    final held = await keys(groupId);
    final candidates = await _candidates(groupId);
    final order = {...held.keys, ...candidates.keys}.toList()
      ..sort((a, b) {
        // At or below the group's epoch first, newest first; then the rest.
        final aOk = a <= epoch;
        final bOk = b <= epoch;
        if (aOk != bOk) return aOk ? -1 : 1;
        return b.compareTo(a);
      });
    for (final e in order) {
      for (final key in [held[e], candidates[e]]) {
        if (key == null) continue;
        final content = await tryOpen(groupId, blob, e, version, key);
        if (content != null) return (content: content, epoch: e, key: key);
      }
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
