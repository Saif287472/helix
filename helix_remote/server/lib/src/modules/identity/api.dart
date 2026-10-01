import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

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
typedef DeviceListChangedHook = Future<void> Function(Tx tx, String accountId);

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

  /// Accounts whose verified number has these discovery hashes.
  Future<Map<String, String>> accountsByDiscoveryHash(
    SqlSession s,
    Iterable<String> hashes,
  );

  Future<String?> accountByHelixName(SqlSession s, String name);

  /// The server's phone discovery salt (people module serves it).
  Future<Uint8List> discoverySalt();

  Future<PushTarget?> pushTarget(SqlSession s, String deviceId);

  /// Removes a push token the provider reported as unknown.
  Future<void> dropPushToken(SqlSession s, String deviceId);

  /// Deletes an account (compliance and admin modules call this).
  Future<void> deleteAccount(Tx tx, String accountId);

  void onDeviceAdded(DeviceAddedHook hook);

  void onDeviceRevoked(DeviceRevokedHook hook);

  void onIdentityKeyChanged(IdentityKeyChangedHook hook);

  void onAccountSignal(AccountSignalHook hook);

  void onDeviceListChanged(DeviceListChangedHook hook);

  void onAccountDeleted(AccountDeletedHook hook);
}
