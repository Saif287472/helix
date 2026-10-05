import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// Event-bus topics identity publishes after its transactions commit.
abstract final class IdentityTopics {
  /// `{device}`: the device was revoked (sockets close with 4003).
  static const deviceRevoked = 'device.revoked';

  /// `{device, before}`: every session of the device issued before
  /// `before` (epoch ms, the committed cut-off) ended: sign-out, refresh
  /// token reuse. Sockets whose token predates it close with 4001.
  static const sessionsEnded = 'identity.sessions_ended';

  /// `{account}`: an operator suspended the account (sockets close with
  /// 4004; the account may reconnect, read-only).
  static const accountSuspended = 'identity.account_suspended';
}

/// What other modules may know about an account (ADR-026: this file is the
/// only identity file other modules import).
final class AccountRecord {
  const AccountRecord({
    required this.id,
    required this.identityKey,
    required this.status,
    required this.createdAt,
    this.helixName,
    this.phoneLast4,
  });

  final String id;

  /// AIK public key.
  final Uint8List identityKey;
  final String status;
  final DateTime createdAt;
  final String? helixName;
  final String? phoneLast4;

  bool get isSuspended => status == 'suspended';
}

/// A device and its public identity material.
final class DeviceRecord {
  const DeviceRecord({
    required this.id,
    required this.accountId,
    required this.name,
    required this.platform,
    required this.identityKey,
    required this.signingKey,
    required this.certificate,
    required this.certificateCreatedAt,
    required this.active,
    required this.createdAt,
    this.lastSeenOn,
  });

  final String id;
  final String accountId;
  final String name;
  final DevicePlatform platform;

  /// DIK (X25519).
  final Uint8List identityKey;

  /// DSK (Ed25519).
  final Uint8List signingKey;
  final Uint8List certificate;
  final DateTime certificateCreatedAt;
  final bool active;
  final DateTime createdAt;
  final DateTime? lastSeenOn;
}

final class PushTarget {
  const PushTarget({
    required this.deviceId,
    required this.kind,
    required this.token,
  });

  final String deviceId;
  final PushTokenKind kind;
  final String token;
}

/// Runs inside the transaction that adds a device (keys: store prekeys).
typedef DeviceAddedHook =
    Future<void> Function(Tx tx, DeviceRecord device, PrekeyUpload prekeys);

/// Runs inside the transaction that revokes a device (keys, mailbox,
/// realtime purge their rows).
typedef DeviceRevokedHook = Future<void> Function(Tx tx, DeviceRecord device);

/// Runs inside the transaction that changes an account's AIK (messaging:
/// `key_change` envelopes; backup: delete the AIK-keyed history backup).
typedef IdentityKeyChangedHook =
    Future<void> Function(Tx tx, String accountId, Uint8List identityKey);

/// Runs inside the transaction that records a security signal for an
/// account's other devices (messaging: `account_signal` envelopes).
typedef AccountSignalHook =
    Future<void> Function(
      Tx tx,
      String accountId,
      AccountSignalEvent event, {
      String? exceptDevice,
    });

/// Runs inside the transaction that changes an account's device list
/// (messaging: `device_list_change` to people with sessions).
typedef DeviceListChangedHook =
    Future<void> Function(Tx tx, String accountId, {String? exceptDevice});

/// Runs inside the transaction that deletes an account.
typedef AccountDeletedHook = Future<void> Function(Tx tx, String accountId);

/// The identity module's facade.
abstract interface class IdentityApi {
  Future<AccountRecord?> account(SqlSession s, String accountId);

  Future<DeviceRecord?> device(SqlSession s, String deviceId);

  Future<List<DeviceRecord>> activeDevices(SqlSession s, String accountId);

  /// Active devices of many accounts at once (fan-out checks).
  Future<Map<String, List<DeviceRecord>>> activeDevicesOf(
    SqlSession s,
    Iterable<String> accountIds,
  );

  /// Accounts whose verified number has these client discovery hashes
  /// (`hex(HMAC(salt, E.164))`), keyed by the hash that matched. Accounts
  /// that turned phone discovery off have no index and never match.
  Future<Map<String, String>> accountsByDiscoveryHash(
    SqlSession s,
    Iterable<String> hashes,
  );

  /// Turns phone discovery on or off for an account. Off deletes its stored
  /// discovery index. On, if the index is gone, needs [phoneNumber], the
  /// account's own number, checked against its verified phone hash
  /// (`invalid_field` on `phone_number` otherwise).
  Future<void> setPhoneDiscoverable(
    Tx tx,
    String accountId, {
    required bool on,
    String? phoneNumber,
  });

  Future<String?> accountByHelixName(SqlSession s, String name);

  /// The server's phone discovery salt (people module serves it).
  Future<Uint8List> discoverySalt();

  Future<PushTarget?> pushTarget(SqlSession s, String deviceId);

  /// Removes a push token the provider reported as unknown.
  Future<void> dropPushToken(SqlSession s, String deviceId);

  /// Throws `invalid_credentials` (details `accepted`: which proofs would
  /// do) unless the caller proves it owns [accountId]: [authKey] for an
  /// account with a password, [verificationToken] (a fresh phone
  /// verification for the account's number, spent on success) for one with
  /// a password or a textable number, or [deviceProof] (a signature by
  /// [deviceId]'s key) only for an account with neither. Compliance asks
  /// before deleting an account.
  Future<void> confirmOwnership(
    String accountId,
    String deviceId, {
    Uint8List? authKey,
    String? verificationToken,
    DeviceKeyProof? deviceProof,
  });

  /// Deletes an account (compliance and admin modules call this).
  Future<void> deleteAccount(Tx tx, String accountId);

  void onDeviceAdded(DeviceAddedHook hook);

  void onDeviceRevoked(DeviceRevokedHook hook);

  void onIdentityKeyChanged(IdentityKeyChangedHook hook);

  void onAccountSignal(AccountSignalHook hook);

  void onDeviceListChanged(DeviceListChangedHook hook);

  void onAccountDeleted(AccountDeletedHook hook);

  /// Operator actions (admin module only).
  IdentityAdminApi get admin;
}

/// What the operator console may do with accounts, devices, invites and
/// recovery codes. Never exposes phone numbers (last four digits only),
/// codes after issue, or keys.
abstract interface class IdentityAdminApi {
  /// Newest first. [query] matches a `~Helix name` prefix, or the last four
  /// digits when it is four digits.
  Future<Page<AdminAccount>> accounts(
    SqlSession s, {
    required PageRequest page,
    AccountStatus? status,
    String? query,
  });

  /// The account, every device (active and revoked) and whether a password
  /// is set; null if there is no such account.
  Future<({AdminAccount account, List<AdminDevice> devices, bool hasPassword})?>
  accountDetail(SqlSession s, String accountId);

  /// False if there is no such account. Suspended accounts keep their
  /// devices but may only use routes registered with `allowSuspended`.
  Future<bool> setSuspended(Tx tx, String accountId, {required bool suspended});

  /// Bans the account's phone number from signing up again and deletes the
  /// account. False if there is no such account.
  Future<bool> ban(Tx tx, String accountId);

  /// Revokes and fully purges one device. False if it is not an active
  /// device of [accountId].
  Future<bool> revokeDevice(Tx tx, String accountId, String deviceId);

  /// A 48-hour single-use recovery code (replaces any unused one).
  Future<AdminRecoveryCode?> issueRecoveryCode(String accountId);

  Future<Page<AdminInvite>> invites(SqlSession s, {required PageRequest page});

  Future<CreatedInvite> createInvite();

  /// False unless the invite exists and is still open.
  Future<bool> cancelInvite(SqlSession s, String inviteId);

  /// Removes expired refresh tokens, challenges, invites and recovery
  /// codes; counts by kind.
  Future<Map<String, int>> purgeExpired(SqlSession s);
}
