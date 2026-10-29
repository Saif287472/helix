import 'package:helix_remote_db/helix_remote_db.dart';

/// The user-facing settings the engine itself reads (typed through
/// `helix_remote_db`'s [Setting]). Features declare more next to their own
/// code; the app adds UI-only settings in its own settings feature.
abstract final class EngineSettings {
  /// Send `read` receipts to the author when a message is read (CONTENT_V2.md
  /// §3). Receipts to this account's own devices are always sent.
  static const sendReadReceipts = Setting<bool>('privacy.read_receipts', true);

  /// Send typing indicators.
  static const sendTyping = Setting<bool>('privacy.typing_indicators', true);

  /// Calls from someone this account does not know do not ring: they are
  /// logged as missed and nothing else happens (the caller is not told). A
  /// person is known when they are in the phone's contacts, were renamed here,
  /// or were ever written to from this account.
  static const silenceUnknownCallers = Setting<bool>(
    'privacy.silence_unknown_callers',
    false,
  );

  /// New chats start with this disappearing-message timer (seconds), or off.
  static const defaultDisappearingSeconds = Setting<int?>(
    'chat.default_disappearing_seconds',
    null,
  );
}

/// What the engine knows about one other person, kept next to the settings
/// (no table of its own).
abstract final class PersonState {
  /// [account] has blocked this account. Blocks are not secret: the server
  /// says so with a `block_change` envelope, `blocked_by` on a send and a
  /// refused call offer. Cleared when they unblock (the envelope, or a send
  /// or offer that reaches them again).
  static Setting<bool> blocksMe(String account) =>
      Setting<bool>('people.blocks_me:$account', false);

  /// [account] had a verified safety number and then changed key: messages to
  /// them wait (`KeyChangeHeldException`) until the user verifies the new
  /// number or sends anyway. Direct chats only; a group message still goes out
  /// and the group chat shows the change.
  static Setting<bool> keyHold(String account) =>
      Setting<bool>('people.key_hold:$account', false);

  /// Sets [blocksMe] for [account], writing only when it changes (every send
  /// reports it).
  static Future<void> markBlocksMe(
    HelixDb db,
    String account, {
    required bool blocked,
    required DateTime now,
  }) async {
    final setting = blocksMe(account);
    if (await db.settingsDao.get(setting) == blocked) return;
    await db.settingsDao.set(setting, blocked, now: now);
  }
}

/// Engine bookkeeping stored next to the user's settings. Not for UI.
abstract final class EngineState {
  /// The device session (access and refresh token) as JSON. Protected by the
  /// SQLCipher key like everything else in the database.
  static const session = Setting<String?>('account.session', null);

  /// The last one-time prekey id issued; ids are never reused (CRYPTO_V2.md
  /// §3), so the counter lives here and not in the table of live keys.
  static const oneTimePrekeyCounter = Setting<int>('crypto.otk_counter', 0);

  static const signedPrekeyCounter = Setting<int>('crypto.spk_counter', 0);

  /// Epoch ms of the last prekey status check.
  static const lastPrekeyCheck = Setting<int>('crypto.last_prekey_check', 0);

  /// This account's own number and name have been reported for the operator
  /// console (ADR-030; `PeopleService.reportForConsole`).
  static const consoleDetailsReported = Setting<bool>(
    'account.console_details_reported',
    false,
  );

  /// Epoch ms of the last own-device-list refresh.
  static const lastOwnDevicesRefresh = Setting<int>(
    'account.last_devices_refresh',
    0,
  );

  /// Cached discovery salt (base64url) and its version.
  static const discoverySalt = Setting<String?>('people.discovery_salt', null);
}
