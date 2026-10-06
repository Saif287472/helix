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

  /// New chats start with this disappearing-message timer (seconds), or off.
  static const defaultDisappearingSeconds = Setting<int?>(
    'chat.default_disappearing_seconds',
    null,
  );
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

  /// Epoch ms of the last own-device-list refresh.
  static const lastOwnDevicesRefresh = Setting<int>(
    'account.last_devices_refresh',
    0,
  );

  /// Cached discovery salt (base64url) and its version.
  static const discoverySalt = Setting<String?>('people.discovery_salt', null);
}
