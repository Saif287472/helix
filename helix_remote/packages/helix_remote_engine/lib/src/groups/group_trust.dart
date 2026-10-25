import 'dart:convert';

import 'package:helix_remote_db/helix_remote_db.dart' hide GroupRole;
import 'package:helix_remote_engine/src/context.dart';

/// Why a member waits for this account's confirmation.
abstract final class PendingReasons {
  /// The server's roster gained the member and no announcement (or one
  /// attributed to someone who may not add members) explains it.
  static const unattributed = 'unattributed';

  /// The member joined through an invite link by themselves; the server's
  /// word is all there is, so this account has to confirm them.
  static const linkJoin = 'link_join';
}

/// Which members of a group this account has not accepted (CRYPTO_V2.md §14,
/// "server-driven membership").
///
/// A group's roster is the server's. If the server adds a member that no
/// admin's action explains, that member is *pending*: this device does not
/// hand them its sender key or the group key, so they cannot read anything
/// sent from here, until the user confirms them
/// (`GroupsService.confirmMember`). The server still lists them and still
/// delivers ciphertext to them (the send digest covers every member), which
/// is why the keys, not the delivery, are what is withheld.
///
/// A member is *explained* when this account added them, or when a
/// `roster_change` of kind `added` names a member who may add people (an
/// admin, or anyone when the group allows it) as the actor. An attribution
/// the server forges looks the same: signed membership changes are the open
/// item in CRYPTO_V2.md §14.
///
/// Every entry is one settings row - `group.pending.<group>.<account>` and
/// `group.explained.<group>.<account>` - so a mutation is a single-row upsert
/// or delete and two writers cannot drop each other's entries (AUD-12e-2: a
/// document read-modify-written from four actors, where a confirm landing
/// after a roster apply released a member the apply had just held back). The
/// one-document shape used before is migrated on first read. Nothing about
/// the schema changes and the rows are wiped with everything else.
final class GroupTrust {
  GroupTrust(this._ctx);

  final EngineContext _ctx;

  /// Accounts remembered as explained, per group: a roster change and the
  /// roster read that reveals it can arrive in either order.
  static const _maxExplained = 200;

  static String _pendingPrefix(String groupId) => 'group.pending.$groupId.';

  static String _explainedPrefix(String groupId) => 'group.explained.$groupId.';

  /// The whole-map documents written before AUD-12e-2.
  static Setting<String?> _legacyPending(String groupId) =>
      Setting<String?>('group.pending.$groupId', null);

  static Setting<String?> _legacyExplained(String groupId) =>
      Setting<String?>('group.explained.$groupId', null);

  static Setting<String?> _pendingRow(String groupId, String account) =>
      Setting<String?>('${_pendingPrefix(groupId)}$account', null);

  static Setting<String?> _explainedRow(String groupId, String account) =>
      Setting<String?>('${_explainedPrefix(groupId)}$account', '1');

  SettingsDao get _settings => _ctx.db.settingsDao;

  static String? _decodeString(String stored) {
    try {
      final json = jsonDecode(stored);
      return json is String ? json : null;
    } on FormatException {
      return null;
    }
  }

  static Map<String, String> _decodePending(String raw) {
    try {
      return (jsonDecode(raw) as Map).cast<String, String>();
    } on Object {
      return {};
    }
  }

  static List<String> _decodeExplained(String raw) {
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } on Object {
      return [];
    }
  }

  /// Moves the pre-AUD-12e-2 documents into rows, then drops them. Running
  /// twice is a no-op. A pass that interleaves with a mutation can put an
  /// entry back (its read was taken before the release landed); that errs
  /// toward withholding - the member waits again - never toward releasing.
  Future<void> _migrate(String groupId) async {
    final pending = await _settings.get(_legacyPending(groupId));
    if (pending != null) {
      final now = _ctx.now();
      for (final entry in _decodePending(pending).entries) {
        await _settings.set(
          _pendingRow(groupId, entry.key),
          entry.value,
          now: now,
        );
      }
      await _settings.reset(_legacyPending(groupId));
    }
    final explained = await _settings.get(_legacyExplained(groupId));
    if (explained != null) {
      final now = _ctx.now();
      for (final account in _decodeExplained(explained)) {
        await _settings.set(_explainedRow(groupId, account), '1', now: now);
      }
      await _settings.reset(_legacyExplained(groupId));
    }
  }

  /// The members waiting for confirmation, with the reason.
  Future<Map<String, String>> pending(String groupId) async {
    await _migrate(groupId);
    final prefix = _pendingPrefix(groupId);
    final rows = await _settings.entriesWithPrefix(prefix);
    return {
      for (final row in rows.entries)
        row.key.substring(prefix.length): ?_decodeString(row.value),
    };
  }

  Stream<Map<String, String>> watchPending(String groupId) async* {
    await _migrate(groupId);
    final prefix = _pendingPrefix(groupId);
    yield* _settings
        .watchEntriesWithPrefix(prefix)
        .map(
          (rows) => {
            for (final row in rows.entries)
              row.key.substring(prefix.length): ?_decodeString(row.value),
          },
        );
  }

  Future<bool> isPending(String groupId, String account) async {
    await _migrate(groupId);
    return await _settings.get(_pendingRow(groupId, account)) != null;
  }

  /// Holds [account] back until [confirm].
  Future<void> addPending(String groupId, String account, String reason) async {
    await _migrate(groupId);
    await _settings.set(_pendingRow(groupId, account), reason, now: _ctx.now());
  }

  /// [accounts] are explained (this account added them, or an announcement
  /// attributes the addition to someone who may add). Members already
  /// waiting are released.
  Future<void> explain(String groupId, Iterable<String> accounts) async {
    await _migrate(groupId);
    final now = _ctx.now();
    for (final account in accounts) {
      await _settings.set(_explainedRow(groupId, account), '1', now: now);
      await _settings.reset(_pendingRow(groupId, account));
    }
    await _settings.pruneWithPrefix(
      _explainedPrefix(groupId),
      keepNewest: _maxExplained,
    );
  }

  /// Whether [account] was explained; the explanation is used up.
  Future<bool> takeExplained(String groupId, String account) async {
    await _migrate(groupId);
    return _settings.remove(_explainedRow(groupId, account));
  }

  /// The user accepts [account]: keys may be handed to them. Returns false
  /// when they were not waiting.
  Future<bool> confirm(String groupId, String account) async {
    await _migrate(groupId);
    return _settings.remove(_pendingRow(groupId, account));
  }

  /// Drops waiting members that are no longer in the roster.
  Future<void> retainOnly(String groupId, Set<String> members) async {
    await _migrate(groupId);
    final prefix = _pendingPrefix(groupId);
    final rows = await _settings.entriesWithPrefix(prefix);
    for (final key in rows.keys) {
      if (members.contains(key.substring(prefix.length))) continue;
      await _settings.reset(Setting<String?>(key, null));
    }
  }

  Future<void> forget(String groupId) async {
    await _settings.resetWithPrefix(_pendingPrefix(groupId));
    await _settings.resetWithPrefix(_explainedPrefix(groupId));
    await _settings.reset(_legacyPending(groupId));
    await _settings.reset(_legacyExplained(groupId));
  }
}
