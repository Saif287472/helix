import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// Subscribers other modules registered through [IdentityApi]. All run
/// inside identity's transaction, so a failure rolls the whole change back.
final class IdentityHooks {
  final List<DeviceAddedHook> _added = [];
  final List<DeviceRevokedHook> _revoked = [];
  final List<IdentityKeyChangedHook> _keyChanged = [];
  final List<AccountSignalHook> _signals = [];
  final List<DeviceListChangedHook> _listChanged = [];
  final List<AccountDeletedHook> _deleted = [];

  void onDeviceAdded(DeviceAddedHook hook) => _added.add(hook);

  void onDeviceRevoked(DeviceRevokedHook hook) => _revoked.add(hook);

  void onIdentityKeyChanged(IdentityKeyChangedHook hook) =>
      _keyChanged.add(hook);

  void onAccountSignal(AccountSignalHook hook) => _signals.add(hook);

  void onDeviceListChanged(DeviceListChangedHook hook) =>
      _listChanged.add(hook);

  void onAccountDeleted(AccountDeletedHook hook) => _deleted.add(hook);

  Future<void> deviceAdded(
    Tx tx,
    DeviceRecord device,
    PrekeyUpload prekeys,
  ) async {
    for (final h in _added) {
      await h(tx, device, prekeys);
    }
  }

  Future<void> deviceRevoked(Tx tx, DeviceRecord device) async {
    for (final h in _revoked) {
      await h(tx, device);
    }
  }

  Future<void> identityKeyChanged(
    Tx tx,
    String accountId,
    Uint8List key,
  ) async {
    for (final h in _keyChanged) {
      await h(tx, accountId, key);
    }
  }

  Future<void> accountSignal(
    Tx tx,
    String accountId,
    AccountSignalEvent event, {
    String? exceptDevice,
  }) async {
    for (final h in _signals) {
      await h(tx, accountId, event, exceptDevice: exceptDevice);
    }
  }

  Future<void> deviceListChanged(Tx tx, String accountId) async {
    for (final h in _listChanged) {
      await h(tx, accountId);
    }
  }

  Future<void> accountDeleted(Tx tx, String accountId) async {
    for (final h in _deleted) {
      await h(tx, accountId);
    }
  }
}
