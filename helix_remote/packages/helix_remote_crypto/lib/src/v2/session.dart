import 'dart:typed_data';

import 'package:helix_remote_crypto/src/v2/codec.dart';
import 'package:helix_remote_crypto/src/v2/errors.dart';
import 'package:helix_remote_crypto/src/v2/identity.dart';
import 'package:helix_remote_crypto/src/v2/prekeys.dart';
import 'package:helix_remote_crypto/src/v2/primitives.dart';
import 'package:helix_remote_crypto/src/v2/ratchet.dart';
import 'package:helix_remote_crypto/src/v2/x3dh.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Device-pair sessions (CRYPTO_V2.md §4-5, §13a).
///
/// One [DeviceSessions] record per remote device holds the active session
/// and up to [DeviceSessions.maxPrevious] previous ones. The
/// [DeviceSessionManager] reads records through [PairwiseSessionStore] and
/// returns the records to write; it never writes. The caller (the engine)
/// commits them in the same database transaction as the effect of the
/// message, and serialises operations per remote device.

/// X3DH parameters an initiator repeats in every message until the
/// responder's first reply decrypts.
final class PendingPrekey {
  const PendingPrekey({
    required this.ephemeralKey,
    required this.signedPrekeyId,
    this.oneTimePrekeyId,
  });

  final Uint8List ephemeralKey;
  final int signedPrekeyId;
  final int? oneTimePrekeyId;

  JsonMap toJson() => {
    'ek': encodeBytes(ephemeralKey),
    'spk': signedPrekeyId,
    'opk': ?oneTimePrekeyId,
  };

  factory PendingPrekey.fromJson(JsonReader json) => PendingPrekey(
    ephemeralKey: json.bytes('ek'),
    signedPrekeyId: json.integer('spk'),
    oneTimePrekeyId: json.optInt('opk'),
  );
}

/// One Double Ratchet session with one remote device.
final class PairwiseSession {
  const PairwiseSession({
    required this.remote,
    required this.remoteIdentityKey,
    required this.remoteAccountIdentityKey,
    required this.localIdentityKey,
    required this.associatedData,
    required this.baseKey,
    required this.initiator,
    required this.pendingPrekey,
    required this.ratchet,
    required this.createdAt,
  });

  final DeviceAddress remote;

  /// The remote DIK.
  final Uint8List remoteIdentityKey;

  /// The AIK the remote device's certificate verified under when the
  /// session was created. Compare with the pinned AIK to spot key changes.
  final Uint8List remoteAccountIdentityKey;

  /// This device's DIK when the session was created.
  final Uint8List localIdentityKey;

  /// X3DH `AD`.
  final Uint8List associatedData;

  /// The initiator's ephemeral key: identifies the session, so a repeated
  /// prekey message finds its session instead of starting a new one.
  final Uint8List baseKey;
  final bool initiator;

  /// Set while this device is the initiator and has not yet received a
  /// reply; outgoing messages are prekey messages meanwhile.
  final PendingPrekey? pendingPrekey;
  final RatchetState ratchet;
  final DateTime createdAt;

  PairwiseSession _withRatchet(
    RatchetState next, {
    bool clearPending = false,
  }) => PairwiseSession(
    remote: remote,
    remoteIdentityKey: remoteIdentityKey,
    remoteAccountIdentityKey: remoteAccountIdentityKey,
    localIdentityKey: localIdentityKey,
    associatedData: associatedData,
    baseKey: baseKey,
    initiator: initiator,
    pendingPrekey: clearPending ? null : pendingPrekey,
    ratchet: next,
    createdAt: createdAt,
  );

  JsonMap toJson() => {
    'v': 1,
    'remote': remote.toJson(),
    'remote_dik': encodeBytes(remoteIdentityKey),
    'remote_aik': encodeBytes(remoteAccountIdentityKey),
    'local_dik': encodeBytes(localIdentityKey),
    'ad': encodeBytes(associatedData),
    'base_key': encodeBytes(baseKey),
    'initiator': initiator,
    'pending': ?pendingPrekey?.toJson(),
    'ratchet': ratchet.toJson(),
    'created_at': toWireTime(createdAt),
  };

  factory PairwiseSession.fromJson(JsonReader json) =>
      readState('pairwise session', () {
        requireVersion(json, 1, 'pairwise session');
        return PairwiseSession(
          remote: DeviceAddress.fromJson(json.object('remote')),
          remoteIdentityKey: json.bytes('remote_dik'),
          remoteAccountIdentityKey: json.bytes('remote_aik'),
          localIdentityKey: json.bytes('local_dik'),
          associatedData: json.bytes('ad'),
          baseKey: json.bytes('base_key'),
          initiator: json.boolean('initiator'),
          pendingPrekey: json.has('pending')
              ? PendingPrekey.fromJson(json.object('pending'))
              : null,
          ratchet: RatchetState.fromJson(json.object('ratchet')),
          createdAt: json.time('created_at'),
        );
      });

  @override
  String toString() => 'PairwiseSession($remote, <redacted>)';
}

/// Every session with one remote device.
final class DeviceSessions {
  const DeviceSessions({
    required this.remote,
    this.active,
    this.previous = const [],
    this.retiredBaseKeys = const [],
  });

  /// Previous sessions kept for in-flight messages and simultaneous
  /// initiation.
  static const maxPrevious = 5;

  /// Base keys of dropped sessions, so a replayed prekey message for one of
  /// them is refused even when it used no one-time prekey.
  static const maxRetiredBaseKeys = 100;

  final DeviceAddress remote;
  final PairwiseSession? active;

  /// Most recent first.
  final List<PairwiseSession> previous;

  /// Oldest first.
  final List<Uint8List> retiredBaseKeys;

  bool get isEmpty => active == null && previous.isEmpty;

  List<PairwiseSession> get all => [?active, ...previous];

  /// [session] becomes active; the old active one becomes the newest
  /// previous; sessions beyond [maxPrevious] are dropped.
  DeviceSessions withNewActive(PairwiseSession session) {
    final prev = [?active, ...previous];
    return _trim(session, prev);
  }

  /// The session at [index] in [all] is replaced by [session] and becomes
  /// active (a previous session that just decrypted is promoted).
  DeviceSessions withUpdated(int index, PairwiseSession session) {
    final rest = [...all]..removeAt(index);
    return _trim(session, rest);
  }

  DeviceSessions _trim(PairwiseSession active, List<PairwiseSession> prev) {
    final retired = [...retiredBaseKeys];
    while (prev.length > maxPrevious) {
      retired.add(prev.removeLast().baseKey);
    }
    if (retired.length > maxRetiredBaseKeys) {
      retired.removeRange(0, retired.length - maxRetiredBaseKeys);
    }
    return DeviceSessions(
      remote: remote,
      active: active,
      previous: List.unmodifiable(prev),
      retiredBaseKeys: List.unmodifiable(retired),
    );
  }

  /// Drops every session (key change, device revoked), keeping their base
  /// keys so their prekey messages cannot be replayed into a new session.
  DeviceSessions cleared() {
    final retired = [...retiredBaseKeys, for (final s in all) s.baseKey];
    if (retired.length > maxRetiredBaseKeys) {
      retired.removeRange(0, retired.length - maxRetiredBaseKeys);
    }
    return DeviceSessions(
      remote: remote,
      retiredBaseKeys: List.unmodifiable(retired),
    );
  }

  bool _isRetired(List<int> baseKey) =>
      retiredBaseKeys.any((k) => bytesEqual(k, baseKey));

  JsonMap toJson() => {
    'v': 1,
    'remote': remote.toJson(),
    'active': ?active?.toJson(),
    'previous': [for (final s in previous) s.toJson()],
    'retired': [for (final k in retiredBaseKeys) encodeBytes(k)],
  };

  factory DeviceSessions.fromJson(JsonReader json) =>
      readState('device sessions', () {
        requireVersion(json, 1, 'device sessions');
        return DeviceSessions(
          remote: DeviceAddress.fromJson(json.object('remote')),
          active: json.has('active')
              ? PairwiseSession.fromJson(json.object('active'))
              : null,
          previous: List.unmodifiable(
            json.objects('previous', PairwiseSession.fromJson),
          ),
          retiredBaseKeys: List.unmodifiable([
            for (final k in json.strings('retired')) decodeBytes(k),
          ]),
        );
      });

  Uint8List encode() => encodeStateJson(toJson());

  static DeviceSessions decode(List<int> bytes) =>
      DeviceSessions.fromJson(decodeStateJson(bytes, what: 'device sessions'));

  @override
  String toString() => 'DeviceSessions($remote, ${all.length} sessions)';
}

/// Read access to stored sessions. `helix_remote_db` implements it.
abstract interface class PairwiseSessionStore {
  Future<DeviceSessions?> load(DeviceAddress remote);
}

/// Resolves the verified identity of a device that sent a prekey message.
/// The engine answers from its cache of peer devices, or by fetching the
/// account's keys, and applies AIK pinning ([checkAikPin]); return null when
/// the device is unknown or no longer trusted. The manager still checks
/// that the certificate verifies and that the DIK matches the message.
abstract interface class DeviceIdentityResolver {
  Future<DeviceIdentity?> resolve(DeviceAddress device);
}

final class PairwiseEncryptResult {
  const PairwiseEncryptResult({required this.payload, required this.sessions});

  /// Goes into `Envelope.payload` via [SealedPayload.encode].
  final SealedPayload payload;

  /// Commit before the payload is sent.
  final DeviceSessions sessions;
}

final class PairwiseDecryptResult {
  const PairwiseDecryptResult({
    required this.content,
    required this.sessions,
    required this.remoteIdentity,
    this.newSession = false,
    this.consumedOneTimePrekeyId,
  });

  /// Unpadded content bytes (`ContentMessage.decode` input).
  final Uint8List content;

  /// Commit together with the message's effect.
  final DeviceSessions sessions;

  /// The sender's DIK and the AIK it was certified under.
  final ({Uint8List identityKey, Uint8List accountIdentityKey}) remoteIdentity;

  /// A prekey message created a new active session.
  final bool newSession;

  /// Delete this one-time prekey in the same commit.
  final int? consumedOneTimePrekeyId;
}

/// Pairwise encryption with every remote device of every account.
final class DeviceSessionManager {
  DeviceSessionManager({
    required this.local,
    required this.sessions,
    required this.prekeys,
    required this.identities,
    required this.random,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LocalDeviceKeys local;
  final PairwiseSessionStore sessions;
  final LocalPrekeyStore prekeys;
  final DeviceIdentityResolver identities;
  final CryptoRandom random;
  final DateTime Function() _clock;

  Future<bool> hasSession(DeviceAddress remote) async =>
      (await sessions.load(remote))?.active != null;

  /// A fresh X3DH session from a verified bundle, made active. Used for the
  /// first message to a device and, per CRYPTO_V2.md §13a, to answer a
  /// decryption failure over a new session.
  Future<DeviceSessions> startSession(VerifiedPrekeyBundle bundle) async {
    final remote = bundle.identity.address;
    if (remote == local.address) {
      throw ArgumentError('cannot start a session with this device');
    }
    final x3dh = await X3dh.initiate(
      local: local,
      bundle: bundle,
      random: random,
    );
    final ratchet = await RatchetState.initiator(
      sharedSecret: x3dh.sharedSecret,
      remoteSignedPrekey: x3dh.signedPrekey,
      random: random,
    );
    final session = PairwiseSession(
      remote: remote,
      remoteIdentityKey: bundle.identity.identityKey,
      remoteAccountIdentityKey: bundle.identity.accountIdentityKey,
      localIdentityKey: local.identityKey.publicKey,
      associatedData: x3dh.associatedData,
      baseKey: x3dh.ephemeralKey,
      initiator: true,
      pendingPrekey: PendingPrekey(
        ephemeralKey: x3dh.ephemeralKey,
        signedPrekeyId: x3dh.signedPrekeyId,
        oneTimePrekeyId: x3dh.oneTimePrekeyId,
      ),
      ratchet: ratchet,
      createdAt: _clock().toUtc(),
    );
    final existing =
        await sessions.load(remote) ?? DeviceSessions(remote: remote);
    return existing.withNewActive(session);
  }

  /// Pads and encrypts [content] with the active session.
  Future<PairwiseEncryptResult> encrypt(
    DeviceAddress remote,
    List<int> content,
  ) async {
    final record = await sessions.load(remote);
    final session = record?.active;
    if (record == null || session == null || !session.ratchet.canSend) {
      throw NoSessionException('no session with $remote');
    }
    final out = await DoubleRatchet.encrypt(
      session.ratchet,
      padPlaintext(content),
      associatedData: session.associatedData,
    );
    final pending = session.pendingPrekey;
    final SealedPayload payload = pending == null
        ? RatchetMessage(header: out.header, ciphertext: out.ciphertext)
        : PrekeyMessage(
            senderIdentityKey: session.localIdentityKey,
            ephemeralKey: pending.ephemeralKey,
            signedPrekeyId: pending.signedPrekeyId,
            oneTimePrekeyId: pending.oneTimePrekeyId,
            header: out.header,
            ciphertext: out.ciphertext,
          );
    return PairwiseEncryptResult(
      payload: payload,
      sessions: record.withUpdated(0, session._withRatchet(out.state)),
    );
  }

  /// Decrypts a pairwise payload from [sender] (the server-attested
  /// `Envelope.from`). Throws a [CryptoV2Exception]; nothing needs rolling
  /// back on failure.
  Future<PairwiseDecryptResult> decrypt({
    required DeviceAddress sender,
    required SealedPayload payload,
  }) async {
    final record =
        await sessions.load(sender) ?? DeviceSessions(remote: sender);
    return switch (payload) {
      PrekeyMessage() => _decryptPrekey(record, payload),
      RatchetMessage() => _decryptExisting(
        record,
        record.all,
        payload.header,
        payload.ciphertext,
      ),
      SenderKeyMessage() => throw const MalformedCryptoInputException(
        'a sender-key message is not a pairwise payload',
      ),
    };
  }

  Future<PairwiseDecryptResult> _decryptPrekey(
    DeviceSessions record,
    PrekeyMessage message,
  ) async {
    final sender = record.remote;
    if (message.senderIdentityKey.length != 32 ||
        message.ephemeralKey.length != 32) {
      throw const MalformedCryptoInputException('prekey message key lengths');
    }

    // A repeat of a prekey message whose session already exists.
    final existing = [
      for (final s in record.all)
        if (bytesEqual(s.baseKey, message.ephemeralKey)) s,
    ];
    if (existing.isNotEmpty) {
      if (!bytesEqual(
        existing.first.remoteIdentityKey,
        message.senderIdentityKey,
      )) {
        throw const UntrustedIdentityException(
          'prekey message identity does not match its session',
        );
      }
      return _decryptExisting(
        record,
        existing,
        message.header,
        message.ciphertext,
      );
    }
    if (record._isRetired(message.ephemeralKey)) {
      throw const DuplicateOrExpiredMessageException(
        'prekey message for a dropped session',
      );
    }

    // A new session: the sender's identity must be certified and match.
    final identity = await identities.resolve(sender);
    if (identity == null || identity.address != sender) {
      throw UntrustedIdentityException('no trusted identity for $sender');
    }
    await identity.requireCertified();
    if (!bytesEqual(identity.identityKey, message.senderIdentityKey)) {
      throw UntrustedIdentityException(
        'prekey message identity key is not the key of $sender',
      );
    }
    final spk = await prekeys.signedPrekey(message.signedPrekeyId);
    if (spk == null) {
      throw const UnknownPrekeyException('unknown signed prekey');
    }
    OneTimePrekeyRecord? opk;
    if (message.oneTimePrekeyId != null) {
      opk = await prekeys.oneTimePrekey(message.oneTimePrekeyId!);
      if (opk == null) {
        throw const UnknownPrekeyException('unknown one-time prekey');
      }
    }
    final sharedSecret = await X3dh.respond(
      local: local,
      signedPrekey: spk.keyPair,
      oneTimePrekey: opk?.keyPair,
      initiatorIdentityKey: message.senderIdentityKey,
      ephemeralKey: message.ephemeralKey,
    );
    final ad = X3dh.associatedData(
      initiator: sender,
      initiatorIdentityKey: message.senderIdentityKey,
      responder: local.address,
      responderIdentityKey: local.identityKey.publicKey,
    );
    final decrypted = await DoubleRatchet.decrypt(
      RatchetState.responder(
        sharedSecret: sharedSecret,
        signedPrekey: spk.keyPair,
      ),
      message.header,
      message.ciphertext,
      associatedData: ad,
      now: _clock(),
      random: random,
    );
    final session = PairwiseSession(
      remote: sender,
      remoteIdentityKey: identity.identityKey,
      remoteAccountIdentityKey: identity.accountIdentityKey,
      localIdentityKey: local.identityKey.publicKey,
      associatedData: ad,
      baseKey: copyBytes(message.ephemeralKey),
      initiator: false,
      pendingPrekey: null,
      ratchet: decrypted.state,
      createdAt: _clock().toUtc(),
    );
    return PairwiseDecryptResult(
      content: _unpad(decrypted.plaintext),
      sessions: record.withNewActive(session),
      remoteIdentity: (
        identityKey: identity.identityKey,
        accountIdentityKey: identity.accountIdentityKey,
      ),
      newSession: true,
      consumedOneTimePrekeyId: opk?.id,
    );
  }

  /// Tries [candidates] in order (active first). The one that decrypts is
  /// committed and becomes active.
  Future<PairwiseDecryptResult> _decryptExisting(
    DeviceSessions record,
    List<PairwiseSession> candidates,
    RatchetHeader header,
    Uint8List ciphertext,
  ) async {
    if (candidates.isEmpty) {
      throw NoSessionException('no session with ${record.remote}');
    }
    CryptoV2Exception? failure;
    final all = record.all;
    for (final session in candidates) {
      try {
        final out = await DoubleRatchet.decrypt(
          session.ratchet,
          header,
          ciphertext,
          associatedData: session.associatedData,
          now: _clock(),
          random: random,
        );
        final updated = session._withRatchet(out.state, clearPending: true);
        return PairwiseDecryptResult(
          content: _unpad(out.plaintext),
          sessions: record.withUpdated(all.indexOf(session), updated),
          remoteIdentity: (
            identityKey: session.remoteIdentityKey,
            accountIdentityKey: session.remoteAccountIdentityKey,
          ),
        );
      } on MalformedCryptoInputException {
        rethrow;
      } on CryptoV2Exception catch (e) {
        // Prefer the most specific reason: expired/duplicate or skip cap
        // over a plain authentication failure from a non-matching session.
        if (failure == null || failure is DecryptionFailedException) {
          failure = e;
        }
      }
    }
    // A plain authentication failure is most likely tampering, not lost
    // state, so it does not request a session reset (§13a).
    throw failure!;
  }

  static Uint8List _unpad(Uint8List padded) {
    try {
      return unpadPlaintext(padded);
    } on FormatException {
      throw const MalformedCryptoInputException('bad plaintext padding');
    }
  }
}
