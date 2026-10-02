import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/events.dart';
import 'package:helix_remote_engine/src/messaging/kinds.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Keys fetched for an account and verified (certificates under the AIK,
/// signed-prekey signatures under the DSK).
final class FetchedKeys {
  const FetchedKeys(this.bundles, {required this.keyChanged});

  final List<VerifiedPrekeyBundle> bundles;

  /// The account's identity key differed from the pinned one; old sessions
  /// were dropped and the new key is pinned (CRYPTO_V2.md §2).
  final bool keyChanged;

  VerifiedPrekeyBundle? bundleOf(String deviceId) {
    for (final bundle in bundles) {
      if (bundle.identity.address.device == deviceId) return bundle;
    }
    return null;
  }
}

/// What this device knows about other accounts' devices: the cache in
/// `person_devices`, the AIK pin in `people`, and the only code that fetches
/// and verifies prekey bundles (`GET /v1/keys/{account}`).
///
/// Fetching consumes one one-time prekey per returned device on the server,
/// so the engine asks for bundles only when it must start a session, and
/// names the devices it needs (`?device=`).
final class PeerDirectory {
  PeerDirectory(this._ctx);

  final EngineContext _ctx;

  Future<PersonRow?> person(String account) =>
      _ctx.db.peopleDao.byAccount(account);

  /// Trusted devices of [account] with their certificates, from the cache.
  Future<List<PersonDeviceRow>> devicesOf(String account) =>
      _ctx.db.peopleDao.devicesOf(account);

  /// The cached identity of one device (certificate included), or null.
  Future<DeviceIdentity?> cachedIdentity(DeviceAddress device) async {
    final rows = await devicesOf(device.account);
    final row = rows.where((r) => r.deviceId == device.device).firstOrNull;
    if (row == null || row.certificate == null) return null;
    final Uint8List? aik = device.account == _ctx.identity.accountId
        ? _ctx.identity.accountKey.publicKey
        : (await person(device.account))?.identityKey;
    if (aik == null) return null;
    return DeviceIdentity(
      address: device,
      accountIdentityKey: aik,
      identityKey: row.identityKey,
      signingKey: row.signingKey,
      certificate: DeviceCertificate.fromJson(
        JsonReader.decode(utf8.decode(row.certificate!)),
      ),
    );
  }

  /// Fetches, verifies and caches bundles of [account] (only [devices] when
  /// given), pinning the account's AIK on first use and handling a key
  /// change. Network and API errors propagate; keys that do not verify
  /// throw [UntrustedPeerException].
  Future<FetchedKeys> fetch(
    String account, {
    Iterable<String> devices = const [],
  }) async {
    final self = _ctx.identity;
    final AccountKeys keys = await _ctx.api.keys.accountKeys(
      account,
      devices: devices,
    );
    final isSelf = account == self.accountId;
    final pinned = isSelf
        ? self.accountKey.publicKey
        : (await person(account))?.identityKey;
    final VerifiedAccountKeys verified;
    try {
      verified = await VerifiedAccountKeys.verify(
        account: account,
        keys: keys,
        pinnedAccountIdentityKey: pinned,
      );
    } on CryptoV2Exception {
      throw const UntrustedPeerException(
        'the keys the server returned do not verify',
      );
    }
    if (isSelf && verified.pin != AikPinResult.matches) {
      throw const UntrustedPeerException(
        'the server returned another identity key for this account',
      );
    }
    final changed = verified.pin == AikPinResult.changed;
    final now = _ctx.now();
    await _ctx.db.transaction(() async {
      if (changed) await _applyKeyChange(account, verified, now);
      if (verified.pin == AikPinResult.firstUse) {
        await _ctx.db.peopleDao.upsertPerson(
          PeopleCompanion.insert(
            accountId: account,
            identityKey: Value(verified.accountIdentityKey),
            updatedAt: now,
          ),
        );
      }
      final existing = {
        for (final d in await _ctx.db.peopleDao.devicesOf(
          account,
          includeStale: true,
        ))
          d.deviceId: d,
      };
      for (final bundle in verified.devices) {
        final id = bundle.identity;
        await _ctx.db.peopleDao.upsertDevice(
          PersonDevicesCompanion.insert(
            accountId: account,
            deviceId: id.address.device,
            identityKey: id.identityKey,
            signingKey: id.signingKey,
            certificate: Value(
              Uint8List.fromList(
                utf8.encode(jsonEncode(id.certificate.toJson())),
              ),
            ),
            trust: DeviceTrust.trusted,
            firstSeenAt: existing[id.address.device]?.firstSeenAt ?? now,
            updatedAt: now,
          ),
        );
      }
    });
    if (changed) _ctx.emit(KeyChangedEvent(account));
    return FetchedKeys(verified.devices, keyChanged: changed);
  }

  /// A different AIK is a key change (CRYPTO_V2.md §2): drop every session
  /// with the account's devices (keeping the retired base keys so their
  /// prekey messages cannot be replayed), mark the devices stale, reset the
  /// verified flag, pin the new key and tell the user in the chat.
  Future<void> _applyKeyChange(
    String account,
    VerifiedAccountKeys verified,
    DateTime now,
  ) async {
    final dao = _ctx.db.peopleDao;
    for (final device in await dao.devicesOf(account, includeStale: true)) {
      await _clearSessions(DeviceAddress(account, device.deviceId), now);
    }
    await dao.markDevicesStale(account);
    await dao.upsertPerson(
      PeopleCompanion.insert(
        accountId: account,
        identityKey: Value(verified.accountIdentityKey),
        identityVerified: const Value(false),
        identityChangedAt: Value(now),
        updatedAt: now,
      ),
    );
    final chat = await _ctx.db.conversationsDao.byId(
      directConversationId(account),
    );
    if (chat != null) {
      await _localNotice(
        chat.id,
        account,
        MessageKinds.safetyNumberChanged,
        now,
      );
    }
  }

  /// A local, never-sent `system` row in [conversationId].
  Future<void> _localNotice(
    String conversationId,
    String account,
    String kind,
    DateTime now,
  ) async {
    final id = _ctx.ids.next();
    await _ctx.db.messagesDao.insertMessage(
      MessagesCompanion.insert(
        messageId: id,
        conversationId: conversationId,
        sender: account,
        outgoing: false,
        sortKey: SortKey.of(now, id),
        sentAt: now,
        receivedAt: now,
        kind: SystemBody.typeName,
        payload: Value(jsonEncode(SystemBody(kind: kind).toJson())),
        status: MessageStatus.read,
      ),
    );
  }

  /// Forgets a device that is gone (revoked, or listed as `extra` in a
  /// `device_list_stale`): its cached keys and its sessions.
  Future<void> dropDevice(String account, String deviceId) =>
      _ctx.db.transaction(() async {
        await _ctx.db.peopleDao.removeDevice(account, deviceId);
        await _clearSessions(DeviceAddress(account, deviceId), _ctx.now());
      });

  /// Keeps only [keepIds] among the cached devices of [account].
  Future<void> retainDevices(String account, Set<String> keepIds) async {
    for (final d in await _ctx.db.peopleDao.devicesOf(
      account,
      includeStale: true,
    )) {
      if (!keepIds.contains(d.deviceId)) await dropDevice(account, d.deviceId);
    }
  }

  /// Drops every cached session of [remote]. Retired base keys stay.
  Future<void> _clearSessions(DeviceAddress remote, DateTime now) async {
    final sessions = await _ctx.sessionStore.load(remote);
    if (sessions == null) return;
    await _ctx.sessionStore.save(sessions.cleared(), now: now);
  }
}

/// Answers the session layer's question "who is this device?" for prekey
/// messages from devices it has not talked to before: from the cache, or by
/// fetching that device's bundle. The session manager still verifies the
/// certificate and the DIK; this applies AIK pinning on the way.
final class PeerIdentityResolver implements DeviceIdentityResolver {
  PeerIdentityResolver(this._peers);

  final PeerDirectory _peers;

  @override
  Future<DeviceIdentity?> resolve(DeviceAddress device) async {
    final cached = await _peers.cachedIdentity(device);
    if (cached != null) return cached;
    try {
      final fetched = await _peers.fetch(
        device.account,
        devices: [device.device],
      );
      return fetched.bundleOf(device.device)?.identity;
    } on NetworkException catch (e) {
      throw TransientEngineException('could not look up a device', cause: e);
    } on ApiException catch (e) {
      if (e.isRetryable) {
        throw TransientEngineException('could not look up a device', cause: e);
      }
      return null;
    } on UntrustedPeerException {
      return null;
    }
  }
}
