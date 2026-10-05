import 'dart:typed_data';

import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/crypto/peer_directory.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/events.dart';
import 'package:helix_remote_engine/src/settings_keys.dart';
import 'package:helix_remote_engine/src/util/masking.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// This account's devices: the list, rename, revoke, and approving the
/// link of a new device (CRYPTO_V2.md §2a, this device as the approver).
/// The new device's side is in `AccountService`.
final class DeviceService {
  DeviceService(this._ctx, this._peers);

  final EngineContext _ctx;
  final PeerDirectory _peers;

  /// The device list, this device first. Updated by [refresh].
  Stream<List<SelfDeviceRow>> watch() => _ctx.db.accountDao.watchDevices();

  Future<List<SelfDeviceRow>> list() => _ctx.db.accountDao.devices();

  /// Reads `GET /v1/devices`, stores the list and forgets cached keys and
  /// sessions of devices that are gone. Returns the list.
  Future<List<SelfDeviceRow>> refresh() async {
    final list = await _ctx.api.identity.devices();
    final self = _ctx.identity;
    await _ctx.db.accountDao.replaceDevices([
      for (final d in list.devices)
        SelfDevicesCompanion.insert(
          deviceId: d.deviceId,
          name: Value(d.name),
          platform: Value(d.platform.wire),
          linkedAt: Value(d.createdAt),
          lastActiveAt: Value(d.lastSeenOn),
          isThisDevice: Value(d.deviceId == self.deviceId),
        ),
    ]);
    await _peers.retainDevices(self.accountId, {
      for (final d in list.devices) d.deviceId,
    });
    await _ctx.db.settingsDao.set(
      EngineState.lastOwnDevicesRefresh,
      _ctx.now().millisecondsSinceEpoch,
      now: _ctx.now(),
    );
    return _ctx.db.accountDao.devices();
  }

  /// Ids of this account's other devices (the sync targets of every send).
  /// Reads the stored list; fetches it when this device has never done so.
  Future<Set<String>> otherDeviceIds() async {
    var rows = await _ctx.db.accountDao.devices();
    if (rows.isEmpty) rows = await refresh();
    final self = _ctx.identity.deviceId;
    return {
      for (final row in rows)
        if (row.deviceId != self) row.deviceId,
    };
  }

  Future<void> rename(String deviceId, String name) async {
    await _ctx.api.identity.renameDevice(deviceId, name);
    await refresh();
  }

  /// Revokes another device (`lost`: it was lost or stolen). Its sessions
  /// and cached keys here are dropped. Revoking this device signs it out:
  /// use `Engine.signOut`.
  Future<void> revoke(String deviceId, {bool lost = false}) async {
    if (deviceId == _ctx.identity.deviceId) {
      throw const EngineStateException(
        'to revoke this device, sign out instead',
      );
    }
    await _ctx.api.identity.revokeDevice(deviceId, lost: lost);
    await refresh();
  }

  /// Revokes every device but this one; returns how many.
  Future<int> revokeOthers() async {
    final result = await _ctx.api.identity.revokeOtherDevices();
    await refresh();
    return result.revoked;
  }

  Future<List<SecurityEvent>> securityEvents({int limit = 50}) async {
    final page = await _ctx.api.identity.securityEvents(
      page: PageRequest(limit: limit),
    );
    return page.items;
  }

  /// Approves the link a new device shows as a QR code: checks that the
  /// code names this server, seals the account's identity key and profile
  /// key to the new device's ephemeral key, and posts it (the server cannot
  /// read it). The caller must have asked the user to confirm.
  Future<void> approveLink(String code) async {
    final LinkCode link;
    try {
      link = LinkCode.parse(code.trim());
    } on CryptoV2Exception {
      throw const SignInException(
        SignInFailure.badLinkCode,
        'this is not a Helix link code',
      );
    }
    final origin = _ctx.api.transport.baseUrl.origin;
    if (link.serverOrigin != origin) {
      throw const SignInException(
        SignInFailure.badLinkCode,
        'this link is for another server',
      );
    }
    final self = _ctx.identity;
    final profileKey = await _ownProfileKey();
    final row = await _ctx.db.accountDao.current();
    final phone = row?.phoneNumber;
    // Signed as this device, over this link and the new device's ephemeral
    // key; the account's masked number and `~name` ride along for the new
    // device's user to compare (CRYPTO_V2.md section 2a).
    final sealed = await Provisioning.seal(
      linkCode: link,
      approver: self.keys,
      accountKey: self.accountKey,
      profileKey: profileKey,
      phoneMask: phone == null ? null : maskPhone(phone),
      helixName: row?.helixName,
      random: _ctx.random,
    );
    await _ctx.api.identity.approveLink(
      link.linkId,
      LinkApproveRequest(provision: sealed),
    );
    _ctx.emit(const OwnDevicesChanged());
  }

  /// The account's profile key, made on first use (CRYPTO_V2.md §9).
  Future<Uint8List> _ownProfileKey() async {
    final row = await _ctx.db.accountDao.current();
    if (row?.profileKey != null) return row!.profileKey!;
    final key = newSymmetricKey(_ctx.random);
    await _ctx.db.accountDao.save(
      SelfAccountCompanion.insert(
        accountId: row!.accountId,
        deviceId: row.deviceId,
        serverDomain: row.serverDomain,
        registeredAt: row.registeredAt,
        profileKey: Value(key),
      ),
    );
    return key;
  }
}
