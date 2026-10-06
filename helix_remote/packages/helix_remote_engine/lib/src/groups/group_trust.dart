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
/// Both sets live in the settings table as JSON, so nothing about the schema
/// changes and they are wiped with everything else.
final class GroupTrust {
  GroupTrust(this._ctx);

  final EngineContext _ctx;

  /// Accounts remembered as explained, per group: a roster change and the
  /// roster read that reveals it can arrive in either order.
  static const _maxExplained = 200;

  static Setting<String?> _pending(String groupId) =>
      Setting<String?>('group.pending.$groupId', null);

  static Setting<String?> _explained(String groupId) =>
      Setting<String?>('group.explained.$groupId', null);

  SettingsDao get _settings => _ctx.db.settingsDao;

  static Map<String, String> _decodePending(String? raw) {
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, String>();
    } on Object {
      return {};
    }
  }

  static List<String> _decodeExplained(String? raw) {
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } on Object {
      return [];
    }
  }

  /// The members waiting for confirmation, with the reason.
  Future<Map<String, String>> pending(String groupId) async =>
      _decodePending(await _settings.get(_pending(groupId)));

  Stream<Map<String, String>> watchPending(String groupId) =>
      _settings.watch(_pending(groupId)).map(_decodePending);

  Future<bool> isPending(String groupId, String account) async =>
      (await pending(groupId)).containsKey(account);

  /// Holds [account] back until [confirm].
  Future<void> addPending(String groupId, String account, String reason) async {
    final all = await pending(groupId);
    all[account] = reason;
    await _settings.set(_pending(groupId), jsonEncode(all), now: _ctx.now());
  }

  /// [accounts] are explained (this account added them, or an announcement
  /// attributes the addition to someone who may add). Members already
  /// waiting are released.
  Future<void> explain(String groupId, Iterable<String> accounts) async {
    final list = _decodeExplained(await _settings.get(_explained(groupId)));
    for (final a in accounts) {
      if (!list.contains(a)) list.add(a);
    }
    while (list.length > _maxExplained) {
      list.removeAt(0);
    }
    await _settings.set(_explained(groupId), jsonEncode(list), now: _ctx.now());
    final waiting = await pending(groupId);
    if (accounts.any(waiting.containsKey)) {
      for (final a in accounts) {
        waiting.remove(a);
      }
      await _settings.set(
        _pending(groupId),
        jsonEncode(waiting),
        now: _ctx.now(),
      );
    }
  }

  /// Whether [account] was explained; the explanation is used up.
  Future<bool> takeExplained(String groupId, String account) async {
    final list = _decodeExplained(await _settings.get(_explained(groupId)));
    if (!list.remove(account)) return false;
    await _settings.set(_explained(groupId), jsonEncode(list), now: _ctx.now());
    return true;
  }

  /// The user accepts [account]: keys may be handed to them. Returns false
  /// when they were not waiting.
  Future<bool> confirm(String groupId, String account) async {
    final waiting = await pending(groupId);
    if (waiting.remove(account) == null) return false;
    await _settings.set(
      _pending(groupId),
      jsonEncode(waiting),
      now: _ctx.now(),
    );
    return true;
  }

  /// Drops waiting members that are no longer in the roster.
  Future<void> retainOnly(String groupId, Set<String> members) async {
    final waiting = await pending(groupId);
    final before = waiting.length;
    waiting.removeWhere((a, _) => !members.contains(a));
    if (waiting.length != before) {
      await _settings.set(
        _pending(groupId),
        jsonEncode(waiting),
        now: _ctx.now(),
      );
    }
  }

  Future<void> forget(String groupId) async {
    await _settings.reset(_pending(groupId));
    await _settings.reset(_explained(groupId));
  }
}
