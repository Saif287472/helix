import 'dart:typed_data';

import 'package:helix_remote_crypto/src/v2/codec.dart';
import 'package:helix_remote_crypto/src/v2/errors.dart';
import 'package:helix_remote_crypto/src/v2/primitives.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The Double Ratchet with DH steps (CRYPTO_V2.md §5), following the Signal
/// specification:
///
/// ```
/// KDF_RK(rk, dh) = HKDF(ikm = dh, salt = rk, info = "helix.v2.ratchet.root", 64)
///                  -> rk' = [0:32], ck = [32:64]
/// KDF_CK(ck)     -> mk = HMAC(ck, 0x01), ck' = HMAC(ck, 0x02)
/// message key    =  HKDF(mk, salt = 0x00*32, info = "helix.v2.message", 44)
/// ciphertext     =  AES-256-GCM(key, nonce, plaintext, aad = AD ‖ header_bytes)
/// ```
///
/// [RatchetState] is immutable plain data. [DoubleRatchet.encrypt] and
/// [DoubleRatchet.decrypt] return the next state and never change their
/// input, so a failed decryption leaves nothing to roll back
/// (decrypt-before-commit).
abstract final class RatchetLimits {
  /// `MAX_SKIP`: keys skipped in one chain for one message.
  static const maxSkipPerChain = 1000;

  /// Skipped keys stored per session; the oldest are evicted.
  static const maxStoredSkippedKeys = 2000;

  /// Skipped keys older than this are discarded.
  static const skippedKeyLifetime = Duration(days: 30);

  /// Past remote ratchet keys remembered so a message from a finished chain
  /// is reported as expired rather than as tampering.
  static const rememberedRemoteRatchetKeys = 20;
}

/// A message key kept for a message that has not arrived yet.
final class SkippedMessageKey {
  const SkippedMessageKey({
    required this.ratchetKey,
    required this.index,
    required this.messageKey,
    required this.storedAt,
  });

  final Uint8List ratchetKey;
  final int index;
  final Uint8List messageKey;
  final DateTime storedAt;

  JsonMap toJson() => {
    'dh': encodeBytes(ratchetKey),
    'n': index,
    'mk': encodeBytes(messageKey),
    'at': toWireTime(storedAt),
  };

  factory SkippedMessageKey.fromJson(JsonReader json) => SkippedMessageKey(
    ratchetKey: json.bytes('dh'),
    index: json.integer('n'),
    messageKey: json.bytes('mk'),
    storedAt: json.time('at'),
  );
}

final class RatchetState {
  const RatchetState({
    required this.rootKey,
    required this.sendingRatchetKey,
    required this.remoteRatchetKey,
    required this.sendingChainKey,
    required this.sendCount,
    required this.previousSendCount,
    required this.receivingChainKey,
    required this.receiveCount,
    required this.skipped,
    required this.retiredRemoteRatchetKeys,
  });

  /// Alice: `DHs = new; DHr = SPK_B; RK, CKs = KDF_RK(SK, DH(DHs, DHr))`.
  static Future<RatchetState> initiator({
    required List<int> sharedSecret,
    required List<int> remoteSignedPrekey,
    required CryptoRandom random,
  }) async {
    requireLength(sharedSecret, 32, 'shared secret');
    final dhs = await X25519KeyPair.generate(random);
    final (rk, cks) = kdfRoot(
      sharedSecret,
      await dhs.agree(remoteSignedPrekey),
    );
    return RatchetState(
      rootKey: rk,
      sendingRatchetKey: dhs,
      remoteRatchetKey: copyBytes(remoteSignedPrekey),
      sendingChainKey: cks,
      sendCount: 0,
      previousSendCount: 0,
      receivingChainKey: null,
      receiveCount: 0,
      skipped: const [],
      retiredRemoteRatchetKeys: const [],
    );
  }

  /// Bob: `DHs = SPK_B; DHr = none; RK = SK`. Bob can send only after the
  /// first message from Alice has been decrypted.
  factory RatchetState.responder({
    required List<int> sharedSecret,
    required X25519KeyPair signedPrekey,
  }) {
    requireLength(sharedSecret, 32, 'shared secret');
    return RatchetState(
      rootKey: copyBytes(sharedSecret),
      sendingRatchetKey: signedPrekey,
      remoteRatchetKey: null,
      sendingChainKey: null,
      sendCount: 0,
      previousSendCount: 0,
      receivingChainKey: null,
      receiveCount: 0,
      skipped: const [],
      retiredRemoteRatchetKeys: const [],
    );
  }

  final Uint8List rootKey;

  /// `DHs`.
  final X25519KeyPair sendingRatchetKey;

  /// `DHr`.
  final Uint8List? remoteRatchetKey;

  /// `CKs`, null until Bob has received.
  final Uint8List? sendingChainKey;

  /// `Ns`.
  final int sendCount;

  /// `PN`.
  final int previousSendCount;

  /// `CKr`.
  final Uint8List? receivingChainKey;

  /// `Nr`.
  final int receiveCount;

  /// Oldest first.
  final List<SkippedMessageKey> skipped;

  /// Oldest first.
  final List<Uint8List> retiredRemoteRatchetKeys;

  bool get canSend => sendingChainKey != null;

  JsonMap toJson() => {
    'v': 1,
    'rk': encodeBytes(rootKey),
    'dhs_priv': encodeBytes(sendingRatchetKey.privateKey),
    'dhs': encodeBytes(sendingRatchetKey.publicKey),
    'dhr': ?_opt(remoteRatchetKey),
    'cks': ?_opt(sendingChainKey),
    'ns': sendCount,
    'pn': previousSendCount,
    'ckr': ?_opt(receivingChainKey),
    'nr': receiveCount,
    'skipped': [for (final s in skipped) s.toJson()],
    'retired': [for (final k in retiredRemoteRatchetKeys) encodeBytes(k)],
  };

  factory RatchetState.fromJson(JsonReader json) =>
      readState('ratchet state', () {
        requireVersion(json, 1, 'ratchet state');
        return RatchetState(
          rootKey: json.bytes('rk'),
          sendingRatchetKey: X25519KeyPair.restore(
            json.bytes('dhs_priv'),
            json.bytes('dhs'),
          ),
          remoteRatchetKey: json.optBytes('dhr'),
          sendingChainKey: json.optBytes('cks'),
          sendCount: json.integer('ns'),
          previousSendCount: json.integer('pn'),
          receivingChainKey: json.optBytes('ckr'),
          receiveCount: json.integer('nr'),
          skipped: List.unmodifiable(
            json.objects('skipped', SkippedMessageKey.fromJson),
          ),
          retiredRemoteRatchetKeys: List.unmodifiable([
            for (final k in json.strings('retired')) decodeBytes(k),
          ]),
        );
      });

  static String? _opt(Uint8List? bytes) =>
      bytes == null ? null : encodeBytes(bytes);

  @override
  String toString() => 'RatchetState(<redacted>)';
}

/// The result of encrypting one message.
final class RatchetEncryption {
  const RatchetEncryption(this.header, this.ciphertext, this.state);

  final RatchetHeader header;
  final Uint8List ciphertext;

  /// Commit this before the ciphertext leaves the device; never encrypt
  /// twice from the same state (that would reuse a message key).
  final RatchetState state;
}

/// The result of decrypting one message.
final class RatchetDecryption {
  const RatchetDecryption(this.plaintext, this.state);

  final Uint8List plaintext;
  final RatchetState state;
}

/// `KDF_RK`.
(Uint8List, Uint8List) kdfRoot(List<int> rootKey, List<int> dhOutput) {
  final out = hkdf(
    ikm: dhOutput,
    salt: rootKey,
    info: label('helix.v2.ratchet.root'),
    length: 64,
  );
  return (
    Uint8List.fromList(out.sublist(0, 32)),
    Uint8List.fromList(out.sublist(32, 64)),
  );
}

/// `KDF_CK`: (message key, next chain key).
(Uint8List, Uint8List) kdfChain(List<int> chainKey) =>
    (hmacSha256(chainKey, const [0x01]), hmacSha256(chainKey, const [0x02]));

/// AES key and nonce for one ratchet message key.
AeadKey ratchetMessageKey(List<int> messageKey) =>
    AeadKey.derive(messageKey, 'helix.v2.message');

abstract final class DoubleRatchet {
  static Future<RatchetEncryption> encrypt(
    RatchetState state,
    List<int> plaintext, {
    required List<int> associatedData,
  }) async {
    final cks = state.sendingChainKey;
    if (cks == null) {
      throw StateError('this session cannot send until it has received');
    }
    if (!isU32(state.sendCount)) {
      throw StateError('sending chain exhausted; start a new session');
    }
    final header = RatchetHeader(
      ratchetKey: state.sendingRatchetKey.publicKey,
      previousCount: state.previousSendCount,
      count: state.sendCount,
    );
    final (mk, next) = kdfChain(cks);
    final ciphertext = await ratchetMessageKey(mk).seal(
      plaintext,
      aad: concatBytes([associatedData, header.toAuthenticatedBytes()]),
    );
    return RatchetEncryption(
      header,
      ciphertext,
      RatchetState(
        rootKey: state.rootKey,
        sendingRatchetKey: state.sendingRatchetKey,
        remoteRatchetKey: state.remoteRatchetKey,
        sendingChainKey: next,
        sendCount: state.sendCount + 1,
        previousSendCount: state.previousSendCount,
        receivingChainKey: state.receivingChainKey,
        receiveCount: state.receiveCount,
        skipped: state.skipped,
        retiredRemoteRatchetKeys: state.retiredRemoteRatchetKeys,
      ),
    );
  }

  /// Decrypts [ciphertext] sent with [header]. Throws a [CryptoV2Exception];
  /// on any failure [state] is still the state to keep.
  ///
  /// [random] is used only after authentication succeeds (for the next
  /// sending ratchet key), so trying a message against several sessions
  /// consumes no randomness.
  static Future<RatchetDecryption> decrypt(
    RatchetState state,
    RatchetHeader header,
    List<int> ciphertext, {
    required List<int> associatedData,
    required DateTime now,
    required CryptoRandom random,
  }) async {
    final dh = header.ratchetKey;
    if (dh.length != 32) {
      throw const MalformedCryptoInputException('ratchet key must be 32 bytes');
    }
    if (!isU32(header.count) || !isU32(header.previousCount)) {
      throw const MalformedCryptoInputException('header counters out of range');
    }
    final aad = concatBytes([associatedData, header.toAuthenticatedBytes()]);
    final cutoff = now.subtract(RatchetLimits.skippedKeyLifetime);
    final skipped = [
      for (final s in state.skipped)
        if (s.storedAt.isAfter(cutoff)) s,
    ];

    // 1. A key skipped earlier.
    final found = skipped.indexWhere(
      (s) => s.index == header.count && bytesEqual(s.ratchetKey, dh),
    );
    if (found >= 0) {
      final plaintext = await ratchetMessageKey(
        skipped[found].messageKey,
      ).open(ciphertext, aad: aad);
      skipped.removeAt(found);
      return RatchetDecryption(plaintext, _with(state, skipped: skipped));
    }

    var rootKey = state.rootKey;
    var remote = state.remoteRatchetKey;
    var ckr = state.receivingChainKey;
    var nr = state.receiveCount;
    var cks = state.sendingChainKey;
    var ns = state.sendCount;
    var pn = state.previousSendCount;
    final retired = [...state.retiredRemoteRatchetKeys];
    var stepped = false;

    // 2. A new remote ratchet key: finish the current receiving chain, then
    //    a receiving DH step.
    if (remote == null || !bytesEqual(remote, dh)) {
      if (retired.any((k) => bytesEqual(k, dh))) {
        throw const DuplicateOrExpiredMessageException(
          'message from a finished ratchet chain',
        );
      }
      if (ckr != null && remote != null) {
        ckr = _skip(ckr, nr, header.previousCount, remote, skipped, now);
        nr = header.previousCount > nr ? header.previousCount : nr;
      }
      if (remote != null) retired.add(remote);
      final (rk, ck) = kdfRoot(
        rootKey,
        await state.sendingRatchetKey.agree(dh),
      );
      rootKey = rk;
      ckr = ck;
      remote = copyBytes(dh);
      nr = 0;
      pn = ns;
      ns = 0;
      cks = null;
      stepped = true;
    }
    if (ckr == null) {
      throw const DecryptionFailedException('no receiving chain');
    }

    // 3. This chain: skip to the message, then its key.
    if (header.count < nr) {
      throw const DuplicateOrExpiredMessageException(
        'message key already used or evicted',
      );
    }
    ckr = _skip(ckr, nr, header.count, remote, skipped, now);
    final (mk, nextCkr) = kdfChain(ckr);
    final plaintext = await ratchetMessageKey(mk).open(ciphertext, aad: aad);

    // Authentic: complete the DH step with a fresh sending key.
    var dhs = state.sendingRatchetKey;
    if (stepped) {
      dhs = await X25519KeyPair.generate(random);
      final (rk, ck) = kdfRoot(rootKey, await dhs.agree(remote));
      rootKey = rk;
      cks = ck;
    }
    if (skipped.length > RatchetLimits.maxStoredSkippedKeys) {
      skipped.removeRange(
        0,
        skipped.length - RatchetLimits.maxStoredSkippedKeys,
      );
    }
    if (retired.length > RatchetLimits.rememberedRemoteRatchetKeys) {
      retired.removeRange(
        0,
        retired.length - RatchetLimits.rememberedRemoteRatchetKeys,
      );
    }
    return RatchetDecryption(
      plaintext,
      RatchetState(
        rootKey: rootKey,
        sendingRatchetKey: dhs,
        remoteRatchetKey: remote,
        sendingChainKey: cks,
        sendCount: ns,
        previousSendCount: pn,
        receivingChainKey: nextCkr,
        receiveCount: header.count + 1,
        skipped: List.unmodifiable(skipped),
        retiredRemoteRatchetKeys: List.unmodifiable(retired),
      ),
    );
  }

  /// Advances [chainKey] from index [from] to [until], storing the skipped
  /// message keys. Enforces `MAX_SKIP`.
  static Uint8List _skip(
    Uint8List chainKey,
    int from,
    int until,
    Uint8List ratchetKey,
    List<SkippedMessageKey> skipped,
    DateTime now,
  ) {
    if (until <= from) return chainKey;
    if (until - from > RatchetLimits.maxSkipPerChain) {
      throw TooManySkippedMessagesException(
        'would skip ${until - from} messages in one chain '
        '(max ${RatchetLimits.maxSkipPerChain})',
      );
    }
    var ck = chainKey;
    for (var i = from; i < until; i++) {
      final (mk, next) = kdfChain(ck);
      skipped.add(
        SkippedMessageKey(
          ratchetKey: ratchetKey,
          index: i,
          messageKey: mk,
          storedAt: now,
        ),
      );
      ck = next;
    }
    return ck;
  }

  static RatchetState _with(
    RatchetState s, {
    required List<SkippedMessageKey> skipped,
  }) => RatchetState(
    rootKey: s.rootKey,
    sendingRatchetKey: s.sendingRatchetKey,
    remoteRatchetKey: s.remoteRatchetKey,
    sendingChainKey: s.sendingChainKey,
    sendCount: s.sendCount,
    previousSendCount: s.previousSendCount,
    receivingChainKey: s.receivingChainKey,
    receiveCount: s.receiveCount,
    skipped: List.unmodifiable(skipped),
    retiredRemoteRatchetKeys: s.retiredRemoteRatchetKeys,
  );
}
