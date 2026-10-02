import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/crypto/pairwise_crypto.dart';
import 'package:helix_remote_engine/src/crypto/peer_directory.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/groups/group_roster.dart';
import 'package:helix_remote_engine/src/groups/sender_key_store.dart';
import 'package:helix_remote_engine/src/util/keyed_lock.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Sends one content message to a group (CRYPTO_V2.md §7, REST_V2.md
/// "groups"), the group half of the outbound pipeline:
///
/// 1. **Roster.** The member devices from the stored roster (this device
///    left out) and their `membersDigest`.
/// 2. **Encrypt once.** The sender-key protocol encrypts the content under
///    this device's sender key; it creates a new key when none exists and
///    **rotates** when a member was removed, a member's or this account's
///    device list changed, the key is 7 days old or 10,000 messages old.
/// 3. **Distribute.** Member devices that do not hold the current key get
///    it, pairwise (`sender_key_distribution` over their session, a session
///    is started where there is none), in the same request. The server
///    stores distributions before the message so the key is there first.
/// 4. **Commit, then send.** The sender key's new state (and every ratchet
///    state used for the distributions) is committed before the request
///    leaves; a retry encrypts again, which skips an iteration the
///    receivers forward-skip.
/// 5. **Digest.** The server compares the digest with its member devices;
///    on `device_list_stale` it returns every member's devices, this device
///    adopts them (reading the group again if the accounts differ) and the
///    send is planned again. Devices are marked as holding the key only
///    after the request succeeded.
///
/// Sends of one group run one at a time (the sender key chain is one
/// sequence). Ephemeral sends (typing) carry no distributions: the server
/// delivers only the ciphertext to online devices.
final class GroupMessageSender {
  GroupMessageSender(
    this._ctx,
    this._peers,
    this._crypto,
    this._store,
    this._roster,
  );

  final EngineContext _ctx;
  final PeerDirectory _peers;
  final PairwiseCrypto _crypto;
  final DbSenderKeyStore _store;
  final GroupRosterSync _roster;
  final KeyedLock<String> _locks = KeyedLock();

  SenderKeyGroupProtocol get _protocol => SenderKeyGroupProtocol(
    self: _ctx.identity.address,
    store: _store,
    random: _ctx.random,
    clock: _ctx.clock,
  );

  /// Sends [content] to [groupId]. Throws what the API throws, plus
  /// [GroupException] (`notAMember`) when this device is not in the group.
  /// A member device whose keys do not verify is skipped (it cannot read
  /// until it asks for a re-send); [UntrustedPeerException] is for devices
  /// the server keeps listing but has no keys for.
  Future<void> send({
    required String groupId,
    required String requestId,
    required ContentMessage content,
    bool urgent = true,
    bool ephemeral = false,
    List<DeviceAddress> redistribute = const [],
  }) => _locks.run(groupId, () async {
    final bytes = content.encode();
    if (redistribute.isNotEmpty) {
      await _forgetDistribution(groupId, redistribute);
    }
    var attempts = _ctx.config.staleListRetries + 1;
    while (true) {
      final roster = await _roster.rosterForSend(groupId);
      if (roster == null) {
        throw const GroupException(GroupFailure.notAMember);
      }
      final protocol = _protocol;
      final encryption = await protocol.encrypt(
        roster: roster.crypto,
        content: bytes,
      );
      Distributions? distributions;
      if (!ephemeral && encryption.controlMessages.isNotEmpty) {
        distributions = await _distribute(groupId, encryption);
        if (distributions.gone.isNotEmpty) {
          // These devices no longer exist on the server: forget them and
          // plan again (nothing was committed yet).
          await _roster.dropDevices(groupId, distributions.gone);
          if (--attempts <= 0) {
            throw const UntrustedPeerException('member devices are gone');
          }
          continue;
        }
      }
      // Commit before the request leaves (the ratchet states of the
      // distributions were committed by `encryptFor`).
      await _store.commit(encryption.writes);
      final request = GroupMessageRequest(
        id: requestId,
        payload: encryption.payload.encode(),
        devicesDigest: roster.digest,
        distributions: distributions?.recipients ?? const [],
        urgent: urgent,
        ephemeral: ephemeral,
      );
      try {
        // Every attempt has its own HTTP idempotency key: the ciphertext
        // differs per attempt, and the message id (`requestId`) already
        // makes the delivery idempotent on the server.
        await _ctx.api.groups.sendMessage(
          groupId,
          request,
          idempotencyKey: '$requestId:${_ctx.ids.next()}',
        );
      } on ApiException catch (e) {
        final stale = e.staleDevices;
        if (stale == null || --attempts <= 0) rethrow;
        await _roster.adoptStale(groupId, stale);
        continue;
      }
      final delivered = distributions?.delivered ?? const <DeviceAddress>{};
      if (delivered.isNotEmpty) {
        await _store.commit(
          await protocol.markDelivered(
            groupId: groupId,
            keyId: encryption.keyId,
            devices: delivered,
          ),
        );
      }
      return;
    }
  });

  /// Marks [devices] as not holding this device's current sender key, so
  /// the next send distributes it to them again (§13a: a device reported
  /// that it cannot read this sender's messages).
  Future<void> _forgetDistribution(
    String groupId,
    List<DeviceAddress> devices,
  ) async {
    final key = await _store.ownKey(groupId);
    if (key == null) return;
    await _store.commit([
      OwnSenderKeyWrite(
        key.copyWith(distributedTo: {...key.distributedTo}..removeAll(devices)),
      ),
    ]);
  }

  /// Seals the sender-key distribution for the devices that need it. Starts
  /// sessions where there are none. Devices whose keys do not verify are
  /// skipped; devices the server has no keys for are reported in
  /// [Distributions.gone].
  Future<Distributions> _distribute(
    String groupId,
    GroupEncryption encryption,
  ) async {
    final targets = encryption.controlMessages.keys.toList()..sort();
    final distribution = ContentMessage(
      id: _ctx.ids.next(),
      sentAt: _ctx.now(),
      conversation: GroupConversation(group: groupId),
      body: encryption.controlMessages[targets.first]!,
    ).encode();

    final withoutSession = await _crypto.withoutSession(targets);
    final bundles = <DeviceAddress, VerifiedPrekeyBundle>{};
    final skipped = <DeviceAddress>{};
    final gone = <DeviceAddress>[];
    final byAccount = <String, List<String>>{};
    for (final d in withoutSession) {
      (byAccount[d.account] ??= []).add(d.device);
    }
    for (final entry in byAccount.entries) {
      try {
        final keys = await _peers.fetch(entry.key, devices: entry.value);
        for (final bundle in keys.bundles) {
          bundles[bundle.identity.address] = bundle;
        }
      } on UntrustedPeerException {
        skipped.addAll([
          for (final d in entry.value) DeviceAddress(entry.key, d),
        ]);
        continue;
      } on ApiException catch (e) {
        if (e.code != ErrorCode.notFound) rethrow;
      }
      for (final d in entry.value) {
        final address = DeviceAddress(entry.key, d);
        if (!bundles.containsKey(address)) gone.add(address);
      }
    }
    if (gone.isNotEmpty) {
      return Distributions(const [], const {}, gone);
    }
    final reachable = [
      for (final d in targets)
        if (!skipped.contains(d)) d,
    ];
    final payloads = await _crypto.encryptFor(
      reachable,
      distribution,
      bundles: bundles,
    );
    final perAccount = <String, List<DevicePayload>>{};
    for (final d in reachable) {
      (perAccount[d.account] ??= []).add(
        DevicePayload(device: d.device, payload: payloads[d]!),
      );
    }
    return Distributions(
      [
        for (final e in perAccount.entries)
          Recipient(account: e.key, devices: e.value),
      ],
      reachable.toSet(),
      const [],
    );
  }
}

/// The pairwise sender-key distributions of one group send.
final class Distributions {
  const Distributions(this.recipients, this.delivered, this.gone);

  final List<Recipient> recipients;

  /// Devices whose payload is in [recipients].
  final Set<DeviceAddress> delivered;

  /// Devices the server has no keys for any more.
  final List<DeviceAddress> gone;
}
