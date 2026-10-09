import 'dart:typed_data';

import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/crypto/peer_directory.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// How many times [PairwiseCrypto.locked] reloads and retries after the stored
/// session state moved (another engine committed it first). Three is enough
/// for two engines alternating; a fourth refusal is the caller's problem.
const staleAttempts = 3;

/// Pairwise encryption glue between the engine and `helix_remote_crypto`:
/// the session manager over the database stores, the per-device lock, and
/// the rule that state is committed before ciphertext leaves the device
/// (CRYPTO_V2.md §14).
///
/// The crypto layer never writes. Outbound, [encryptFor] commits the new
/// ratchet states in one transaction before it returns the payloads. Inbound,
/// the pipeline calls [locked], [decrypt] and commits the returned
/// sessions in the transaction that applies the message. Both go through
/// [locked] rather than [runLocked]: a stored state that another engine moved
/// is reloaded and worked on again, never committed (C-01).
final class PairwiseCrypto {
  PairwiseCrypto(this._ctx, this.peers);

  final EngineContext _ctx;
  final PeerDirectory peers;

  DeviceSessionManager? _manager;
  String? _managerDevice;

  /// The session manager for the signed-in device.
  DeviceSessionManager get manager {
    final identity = _ctx.identity;
    if (_manager == null || _managerDevice != identity.deviceId) {
      _manager = DeviceSessionManager(
        local: identity.keys,
        sessions: _ctx.sessionStore,
        prekeys: _ctx.prekeyStore,
        identities: PeerIdentityResolver(peers),
        random: _ctx.random,
        clock: _ctx.clock,
      );
      _managerDevice = identity.deviceId;
    }
    return _manager!;
  }

  /// Forgets the manager (sign-out).
  void reset() {
    _manager = null;
    _managerDevice = null;
  }

  /// Runs [action] holding the lock of [device]: everything that reads and
  /// then writes that device's ratchet state goes through here.
  Future<T> runLocked<T>(DeviceAddress device, Future<T> Function() action) =>
      _ctx.deviceLocks.run(device, action);

  /// Runs [action] holding the lock of [device] and retries it when the stored
  /// state moved under it ([StaleSessionState], review finding C-01).
  ///
  /// The lock is per engine, so two engines on one database file can still
  /// interleave; the version on the stored record (see [DbSessionStore]) is
  /// what turns that into a refusal instead of a lost update. [action] must
  /// therefore read the state it works from *inside* the call (reload, don't
  /// reuse a record loaded earlier), so a retry starts from what the winning
  /// engine committed. After [attempts] refusals the last one is rethrown: the
  /// other engine is still working, and the caller's own retry (an inbound
  /// re-delivery, an outbox backoff) takes over.
  Future<T> locked<T>(
    DeviceAddress device,
    Future<T> Function() action, {
    int attempts = staleAttempts,
  }) => runLocked(device, () async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await action();
      } on StaleSessionState {
        if (attempt >= attempts) rethrow;
      }
    }
  });

  /// Decrypts a pairwise payload. Call inside [locked]; commit
  /// `result.sessions` (and delete `consumedOneTimePrekeyId`) in the
  /// transaction that applies the content.
  Future<PairwiseDecryptResult> decrypt(
    DeviceAddress sender,
    SealedPayload payload,
  ) => manager.decrypt(sender: sender, payload: payload);

  /// The devices of [devices] this device cannot send to yet (no active
  /// session that can send).
  Future<List<DeviceAddress>> withoutSession(
    Iterable<DeviceAddress> devices,
  ) async {
    final missing = <DeviceAddress>[];
    for (final device in devices) {
      final record = await _ctx.sessionStore.load(device);
      final active = record?.active;
      if (active == null || !active.ratchet.canSend) missing.add(device);
    }
    return missing;
  }

  /// Pads and encrypts [content] for every device in [devices], starting a
  /// session first (from [bundles]) where there is none. Returns the sealed
  /// payloads, ready for `DevicePayload`. All ratchet states are committed
  /// in one transaction before this returns; a bundle missing for a device
  /// that needs one throws [ArgumentError].
  Future<Map<DeviceAddress, Uint8List>> encryptFor(
    List<DeviceAddress> devices,
    Uint8List content, {
    Map<DeviceAddress, VerifiedPrekeyBundle> bundles = const {},
  }) async {
    // The whole fan-out is one compare-and-set per device inside one
    // transaction, so a refusal anywhere rolls the whole attempt back and it
    // runs again from the stored state (C-01).
    for (var attempt = 1; ; attempt++) {
      try {
        return await _encryptFor(devices, content, bundles: bundles);
      } on StaleSessionState {
        if (attempt >= staleAttempts) rethrow;
      }
    }
  }

  Future<Map<DeviceAddress, Uint8List>> _encryptFor(
    List<DeviceAddress> devices,
    Uint8List content, {
    required Map<DeviceAddress, VerifiedPrekeyBundle> bundles,
  }) => _ctx.deviceLocks.runAll(devices, () async {
    final manager = this.manager;
    final updated = <DeviceSessions>[];
    final payloads = <DeviceAddress, Uint8List>{};
    for (final device in devices) {
      if ((await withoutSession([device])).isNotEmpty) {
        final bundle = bundles[device];
        if (bundle == null) {
          throw ArgumentError('no bundle to start a session with $device');
        }
        final started = await manager.startSession(bundle);
        await _ctx.sessionStore.save(started, now: _ctx.now());
      }
      final result = await manager.encrypt(device, content);
      updated.add(result.sessions);
      payloads[device] = result.payload.encode();
    }
    final now = _ctx.now();
    await _ctx.db.transaction(() async {
      for (final sessions in updated) {
        await _ctx.sessionStore.save(sessions, now: now);
      }
    });
    return payloads;
  });

  /// Starts a fresh session with [bundle]'s device and commits it, unless an
  /// unanswered session this device started less than [within] ago already
  /// exists (CRYPTO_V2.md §13a: answering a burst of undecryptable messages
  /// must not start a session per message).
  Future<bool> startFreshSession(
    VerifiedPrekeyBundle bundle, {
    required Duration within,
  }) => locked(bundle.identity.address, () async {
    final record = await _ctx.sessionStore.load(bundle.identity.address);
    final active = record?.active;
    final now = _ctx.now();
    if (active != null &&
        active.initiator &&
        active.pendingPrekey != null &&
        now.difference(active.createdAt) < within) {
      return false;
    }
    final started = await manager.startSession(bundle);
    await _ctx.sessionStore.save(started, now: now);
    return true;
  });

  /// True if this device recently started a session with [remote] that the
  /// remote has not answered (see [startFreshSession]).
  Future<bool> hasFreshUnansweredSession(
    DeviceAddress remote, {
    required Duration within,
  }) async {
    final active = (await _ctx.sessionStore.load(remote))?.active;
    return active != null &&
        active.initiator &&
        active.pendingPrekey != null &&
        _ctx.now().difference(active.createdAt) < within;
  }
}
