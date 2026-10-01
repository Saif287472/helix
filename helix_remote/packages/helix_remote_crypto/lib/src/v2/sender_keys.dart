import 'dart:typed_data';

import 'package:helix_remote_crypto/src/v2/codec.dart';
import 'package:helix_remote_crypto/src/v2/errors.dart';
import 'package:helix_remote_crypto/src/v2/identity.dart';
import 'package:helix_remote_crypto/src/v2/primitives.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Sender Keys for groups (CRYPTO_V2.md §7):
///
/// ```
/// step        : mk = HMAC(ck, 0x01); ck' = HMAC(ck, 0x02); iteration += 1
/// message key : HKDF(mk, salt = 0x00*32, info = "helix.v2.sender-key", 44)
/// ciphertext  : AES-256-GCM(key, nonce, padded,
///               aad = "helix.v2.sk" ‖ group_id ‖ dist_id ‖ u32(iteration))
/// signature   : Ed25519(signing, "helix.v2.sk-sig" ‖ group_id ‖ dist_id
///               ‖ u32(iteration) ‖ ciphertext)
/// ```
///
/// A message's `it` is the iteration of the chain key that produced it, so
/// the first message under a new sender key has `it = 0`.
abstract final class SenderKeyLimits {
  /// Iterations a receiver derives forward for one message.
  static const maxForwardSkip = 2000;

  /// Old message keys cached per sender key; the oldest are evicted.
  static const maxStoredSkippedKeys = 2000;
  static const skippedKeyLifetime = Duration(days: 30);

  /// Rotate at the latest after this long ...
  static const maxAge = Duration(days: 7);

  /// ... or this many messages.
  static const maxMessages = 10000;
}

/// The group as the sender sees it when sending: every member account, and
/// every member device the server fans out to (all except this device).
final class GroupRoster {
  GroupRoster({
    required this.groupId,
    required Iterable<String> members,
    required Iterable<DeviceAddress> devices,
  }) : members = Set.unmodifiable(members),
       devices = Set.unmodifiable(devices) {
    uuidBytes(groupId);
  }

  final String groupId;
  final Set<String> members;
  final Set<DeviceAddress> devices;
}

/// Why a sender key must be replaced before the next message.
enum SenderKeyRotationReason {
  /// No sender key yet for this group.
  noKey,

  /// A member was removed or left.
  memberRemoved,

  /// A member's device disappeared (revoked).
  deviceRemoved,

  /// The sender's own device list changed.
  ownDevicesChanged,

  /// Older than [SenderKeyLimits.maxAge].
  expired,

  /// [SenderKeyLimits.maxMessages] messages sent.
  messageLimit,
}

/// This device's sender key for one group.
final class SenderKeyState {
  const SenderKeyState({
    required this.groupId,
    required this.distributionId,
    required this.iteration,
    required this.chainKey,
    required this.signingKey,
    required this.createdAt,
    required this.members,
    required this.devices,
    required this.distributedTo,
  });

  /// A fresh key: new `dist_id`, chain key and signing key.
  static Future<SenderKeyState> create({
    required GroupRoster roster,
    required CryptoRandom random,
    required DateTime now,
  }) async {
    final id = random.nextBytes(16);
    id[6] = 0x40 | (id[6] & 0x0f); // UUIDv4
    id[8] = 0x80 | (id[8] & 0x3f);
    return SenderKeyState(
      groupId: roster.groupId,
      distributionId: Uuid.format(id),
      iteration: 0,
      chainKey: random.nextBytes(32),
      signingKey: await Ed25519KeyPair.generate(random),
      createdAt: now.toUtc(),
      members: roster.members,
      devices: roster.devices,
      distributedTo: const {},
    );
  }

  final String groupId;
  final String distributionId;

  /// Iteration of the next message.
  final int iteration;

  /// Chain key at [iteration].
  final Uint8List chainKey;
  final Ed25519KeyPair signingKey;
  final DateTime createdAt;

  /// Members and member devices when last sent to; a removal from these
  /// triggers rotation.
  final Set<String> members;
  final Set<DeviceAddress> devices;

  /// Devices known to hold this key.
  final Set<DeviceAddress> distributedTo;

  /// Whether this key must be replaced before sending to [roster]. Adding a
  /// member or a member's device does not rotate (the newcomer gets the key
  /// at the current iteration and cannot read earlier messages).
  SenderKeyRotationReason? rotationReason(
    GroupRoster roster, {
    required String selfAccount,
    required DateTime now,
  }) {
    if (roster.groupId != groupId) throw ArgumentError('another group');
    if (members.difference(roster.members).isNotEmpty) {
      return SenderKeyRotationReason.memberRemoved;
    }
    final removed = devices.difference(roster.devices);
    final added = roster.devices.difference(devices);
    if ([...removed, ...added].any((d) => d.account == selfAccount)) {
      return SenderKeyRotationReason.ownDevicesChanged;
    }
    if (removed.isNotEmpty) return SenderKeyRotationReason.deviceRemoved;
    if (!now.isBefore(createdAt.add(SenderKeyLimits.maxAge))) {
      return SenderKeyRotationReason.expired;
    }
    if (iteration >= SenderKeyLimits.maxMessages) {
      return SenderKeyRotationReason.messageLimit;
    }
    return null;
  }

  /// Member devices that still need a distribution of this key.
  List<DeviceAddress> devicesNeedingKey(GroupRoster roster) =>
      (roster.devices.difference(distributedTo).toList()..sort());

  /// The `sender_key_distribution` content for the current iteration.
  SenderKeyDistributionBody distribution() => SenderKeyDistributionBody(
    groupId: groupId,
    distributionId: distributionId,
    iteration: iteration,
    chainKey: chainKey,
    signingKey: signingKey.publicKey,
  );

  SenderKeyState copyWith({
    int? iteration,
    Uint8List? chainKey,
    Set<String>? members,
    Set<DeviceAddress>? devices,
    Set<DeviceAddress>? distributedTo,
  }) => SenderKeyState(
    groupId: groupId,
    distributionId: distributionId,
    iteration: iteration ?? this.iteration,
    chainKey: chainKey ?? this.chainKey,
    signingKey: signingKey,
    createdAt: createdAt,
    members: members ?? this.members,
    devices: devices ?? this.devices,
    distributedTo: distributedTo ?? this.distributedTo,
  );

  JsonMap toJson() => {
    'v': 1,
    'group_id': groupId,
    'dist_id': distributionId,
    'it': iteration,
    'ck': encodeBytes(chainKey),
    'sig_seed': encodeBytes(signingKey.seed),
    'sig_pub': encodeBytes(signingKey.publicKey),
    'created_at': toWireTime(createdAt),
    'members': members.toList()..sort(),
    'devices': [for (final d in devices.toList()..sort()) d.toJson()],
    'distributed': [for (final d in distributedTo.toList()..sort()) d.toJson()],
  };

  factory SenderKeyState.fromJson(JsonReader json) =>
      readState('sender key', () {
        requireVersion(json, 1, 'sender key');
        return SenderKeyState(
          groupId: json.nonEmpty('group_id'),
          distributionId: json.nonEmpty('dist_id'),
          iteration: json.integer('it'),
          chainKey: json.bytes('ck'),
          signingKey: Ed25519KeyPair.restore(
            json.bytes('sig_seed'),
            json.bytes('sig_pub'),
          ),
          createdAt: json.time('created_at'),
          members: Set.unmodifiable(json.strings('members')),
          devices: Set.unmodifiable(
            json.objects('devices', DeviceAddress.fromJson),
          ),
          distributedTo: Set.unmodifiable(
            json.objects('distributed', DeviceAddress.fromJson),
          ),
        );
      });

  Uint8List encode() => encodeStateJson(toJson());

  static SenderKeyState decode(List<int> bytes) =>
      SenderKeyState.fromJson(decodeStateJson(bytes, what: 'sender key'));

  @override
  String toString() => 'SenderKeyState($groupId, $distributionId, <redacted>)';
}

/// A cached message key for a group message not yet received.
final class SkippedSenderKey {
  const SkippedSenderKey({
    required this.iteration,
    required this.messageKey,
    required this.storedAt,
  });

  final int iteration;
  final Uint8List messageKey;
  final DateTime storedAt;

  JsonMap toJson() => {
    'it': iteration,
    'mk': encodeBytes(messageKey),
    'at': toWireTime(storedAt),
  };

  factory SkippedSenderKey.fromJson(JsonReader json) => SkippedSenderKey(
    iteration: json.integer('it'),
    messageKey: json.bytes('mk'),
    storedAt: json.time('at'),
  );
}

/// Another device's sender key, kept per `(account, device, dist_id)`.
final class ReceivedSenderKey {
  const ReceivedSenderKey({
    required this.sender,
    required this.groupId,
    required this.distributionId,
    required this.iteration,
    required this.chainKey,
    required this.signingKey,
    required this.skipped,
    required this.receivedAt,
  });

  /// From a `sender_key_distribution` that arrived over the pairwise session
  /// with [sender]; the caller guarantees that origin.
  factory ReceivedSenderKey.fromDistribution(
    DeviceAddress sender,
    SenderKeyDistributionBody body,
    DateTime now,
  ) {
    if (!Uuid.isValid(body.groupId) || !Uuid.isValid(body.distributionId)) {
      throw const MalformedCryptoInputException('distribution ids');
    }
    if (body.chainKey.length != 32 || body.signingKey.length != 32) {
      throw const MalformedCryptoInputException('distribution key lengths');
    }
    if (!isU32(body.iteration)) {
      throw const MalformedCryptoInputException('distribution iteration');
    }
    return ReceivedSenderKey(
      sender: sender,
      groupId: body.groupId,
      distributionId: body.distributionId,
      iteration: body.iteration,
      chainKey: body.chainKey,
      signingKey: body.signingKey,
      skipped: const [],
      receivedAt: now.toUtc(),
    );
  }

  final DeviceAddress sender;
  final String groupId;
  final String distributionId;

  /// Iteration of the next expected message; [chainKey] is the key there.
  final int iteration;
  final Uint8List chainKey;
  final Uint8List signingKey;

  /// Oldest first.
  final List<SkippedSenderKey> skipped;
  final DateTime receivedAt;

  JsonMap toJson() => {
    'v': 1,
    'sender': sender.toJson(),
    'group_id': groupId,
    'dist_id': distributionId,
    'it': iteration,
    'ck': encodeBytes(chainKey),
    'sig_pub': encodeBytes(signingKey),
    'skipped': [for (final s in skipped) s.toJson()],
    'received_at': toWireTime(receivedAt),
  };

  factory ReceivedSenderKey.fromJson(JsonReader json) =>
      readState('received sender key', () {
        requireVersion(json, 1, 'received sender key');
        return ReceivedSenderKey(
          sender: DeviceAddress.fromJson(json.object('sender')),
          groupId: json.nonEmpty('group_id'),
          distributionId: json.nonEmpty('dist_id'),
          iteration: json.integer('it'),
          chainKey: json.bytes('ck'),
          signingKey: json.bytes('sig_pub'),
          skipped: List.unmodifiable(
            json.objects('skipped', SkippedSenderKey.fromJson),
          ),
          receivedAt: json.time('received_at'),
        );
      });

  Uint8List encode() => encodeStateJson(toJson());

  static ReceivedSenderKey decode(List<int> bytes) =>
      ReceivedSenderKey.fromJson(
        decodeStateJson(bytes, what: 'received sender key'),
      );

  @override
  String toString() =>
      'ReceivedSenderKey($sender, $groupId, $distributionId, <redacted>)';
}

/// Sender-key message encryption and decryption (pure: states in, states
/// out).
abstract final class GroupSenderChain {
  static Uint8List associatedData(
    String groupId,
    String distributionId,
    int iteration,
  ) => concatBytes([
    label('helix.v2.sk'),
    uuidBytes(groupId),
    uuidBytes(distributionId),
    u32(iteration),
  ]);

  static Uint8List signatureInput(
    String groupId,
    String distributionId,
    int iteration,
    List<int> ciphertext,
  ) => concatBytes([
    label('helix.v2.sk-sig'),
    uuidBytes(groupId),
    uuidBytes(distributionId),
    u32(iteration),
    ciphertext,
  ]);

  static AeadKey messageKey(List<int> mk) =>
      AeadKey.derive(mk, 'helix.v2.sender-key');

  /// Pads, encrypts and signs [content]. Commit the returned state before
  /// the message leaves the device.
  static Future<(SenderKeyMessage, SenderKeyState)> encrypt(
    SenderKeyState state,
    List<int> content,
  ) async {
    if (!isU32(state.iteration)) {
      throw StateError('sender key exhausted; rotate');
    }
    final it = state.iteration;
    final mk = hmacSha256(state.chainKey, const [0x01]);
    final next = hmacSha256(state.chainKey, const [0x02]);
    final ciphertext = await messageKey(mk).seal(
      padPlaintext(content),
      aad: associatedData(state.groupId, state.distributionId, it),
    );
    final signature = await state.signingKey.sign(
      signatureInput(state.groupId, state.distributionId, it, ciphertext),
    );
    return (
      SenderKeyMessage(
        distributionId: state.distributionId,
        iteration: it,
        ciphertext: ciphertext,
        signature: signature,
      ),
      state.copyWith(iteration: it + 1, chainKey: next),
    );
  }

  /// Verifies the signature first, then decrypts. Returns the unpadded
  /// content and the key state to commit.
  static Future<(Uint8List, ReceivedSenderKey)> decrypt(
    ReceivedSenderKey key,
    SenderKeyMessage message, {
    required DateTime now,
  }) async {
    if (message.distributionId != key.distributionId) {
      throw const NoSenderKeyException('message is for another sender key');
    }
    final it = message.iteration;
    if (!isU32(it)) {
      throw const MalformedCryptoInputException('iteration out of range');
    }
    await requireSignature(
      publicKey: key.signingKey,
      message: signatureInput(
        key.groupId,
        key.distributionId,
        it,
        message.ciphertext,
      ),
      signature: message.signature,
      what: 'sender-key message',
    );
    final aad = associatedData(key.groupId, key.distributionId, it);
    final cutoff = now.subtract(SenderKeyLimits.skippedKeyLifetime);
    final skipped = [
      for (final s in key.skipped)
        if (s.storedAt.isAfter(cutoff)) s,
    ];

    if (it < key.iteration) {
      final found = skipped.indexWhere((s) => s.iteration == it);
      if (found < 0) {
        throw const DuplicateOrExpiredMessageException(
          'sender-key message key already used or evicted',
        );
      }
      final padded = await messageKey(
        skipped[found].messageKey,
      ).open(message.ciphertext, aad: aad);
      skipped.removeAt(found);
      return (_unpad(padded), _with(key, skipped: skipped));
    }

    if (it - key.iteration > SenderKeyLimits.maxForwardSkip) {
      throw TooManySkippedMessagesException(
        'would skip ${it - key.iteration} sender-key iterations '
        '(max ${SenderKeyLimits.maxForwardSkip})',
      );
    }
    var ck = key.chainKey;
    for (var i = key.iteration; i < it; i++) {
      skipped.add(
        SkippedSenderKey(
          iteration: i,
          messageKey: hmacSha256(ck, const [0x01]),
          storedAt: now,
        ),
      );
      ck = hmacSha256(ck, const [0x02]);
    }
    final mk = hmacSha256(ck, const [0x01]);
    final padded = await messageKey(mk).open(message.ciphertext, aad: aad);
    if (skipped.length > SenderKeyLimits.maxStoredSkippedKeys) {
      skipped.removeRange(
        0,
        skipped.length - SenderKeyLimits.maxStoredSkippedKeys,
      );
    }
    return (
      _unpad(padded),
      ReceivedSenderKey(
        sender: key.sender,
        groupId: key.groupId,
        distributionId: key.distributionId,
        iteration: it + 1,
        chainKey: hmacSha256(ck, const [0x02]),
        signingKey: key.signingKey,
        skipped: List.unmodifiable(skipped),
        receivedAt: key.receivedAt,
      ),
    );
  }

  static ReceivedSenderKey _with(
    ReceivedSenderKey k, {
    required List<SkippedSenderKey> skipped,
  }) => ReceivedSenderKey(
    sender: k.sender,
    groupId: k.groupId,
    distributionId: k.distributionId,
    iteration: k.iteration,
    chainKey: k.chainKey,
    signingKey: k.signingKey,
    skipped: List.unmodifiable(skipped),
    receivedAt: k.receivedAt,
  );

  static Uint8List _unpad(Uint8List padded) {
    try {
      return unpadPlaintext(padded);
    } on FormatException {
      throw const MalformedCryptoInputException('bad plaintext padding');
    }
  }
}
