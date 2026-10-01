import 'dart:typed_data';

import 'package:helix_remote_crypto/src/v2/errors.dart';
import 'package:helix_remote_crypto/src/v2/identity.dart';
import 'package:helix_remote_crypto/src/v2/primitives.dart';
import 'package:helix_remote_crypto/src/v2/sender_keys.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The engine's interface to group encryption (CRYPTO_V2.md §7), so another
/// protocol (MLS) can be added later without touching callers.
///
/// Like the pairwise manager, implementations read state through a store
/// and return [GroupCryptoWrite]s for the caller to commit; they never write.
abstract interface class GroupCryptoProtocol {
  /// Stable id of the protocol (stored with group state).
  String get protocolId;

  /// Encrypts [content] once for the whole group. Commit
  /// [GroupEncryption.writes] before sending; deliver
  /// [GroupEncryption.controlMessages] pairwise in the same request.
  Future<GroupEncryption> encrypt({
    required GroupRoster roster,
    required List<int> content,
  });

  /// Records that the send carrying [GroupEncryption.controlMessages]
  /// succeeded for [devices].
  Future<List<GroupCryptoWrite>> markDelivered({
    required String groupId,
    required String keyId,
    required Iterable<DeviceAddress> devices,
  });

  /// Decrypts a group payload from [sender] (the server-attested
  /// `Envelope.from`).
  Future<GroupDecryption> decrypt({
    required String groupId,
    required DeviceAddress sender,
    required SealedPayload payload,
  });

  /// Handles a group control message (a sender-key distribution) that
  /// arrived over the pairwise session with [sender].
  Future<List<GroupCryptoWrite>> receiveControl({
    required DeviceAddress sender,
    required ContentBody body,
  });
}

/// A state change to commit; each protocol defines its own kinds.
abstract interface class GroupCryptoWrite {}

final class OwnSenderKeyWrite implements GroupCryptoWrite {
  const OwnSenderKeyWrite(this.state);

  final SenderKeyState state;
}

final class ReceivedSenderKeyWrite implements GroupCryptoWrite {
  const ReceivedSenderKeyWrite(this.key);

  final ReceivedSenderKey key;
}

final class GroupEncryption {
  const GroupEncryption({
    required this.payload,
    required this.keyId,
    required this.controlMessages,
    required this.writes,
    this.rotated,
  });

  /// One ciphertext for every member device (`group_message` payload).
  final SealedPayload payload;

  /// The key the message used (the sender key's `dist_id`).
  final String keyId;

  /// Content to send pairwise to devices that lack the key.
  final Map<DeviceAddress, ContentBody> controlMessages;
  final List<GroupCryptoWrite> writes;

  /// Set when a new key was created for this message, and why.
  final SenderKeyRotationReason? rotated;
}

final class GroupDecryption {
  const GroupDecryption({required this.content, required this.writes});

  /// Unpadded content bytes.
  final Uint8List content;
  final List<GroupCryptoWrite> writes;
}

/// Read access to sender keys. `helix_remote_db` implements it.
abstract interface class SenderKeyStore {
  Future<SenderKeyState?> ownKey(String groupId);

  Future<ReceivedSenderKey?> receivedKey(
    DeviceAddress sender,
    String groupId,
    String distributionId,
  );
}

/// Sender Keys as a [GroupCryptoProtocol].
final class SenderKeyGroupProtocol implements GroupCryptoProtocol {
  SenderKeyGroupProtocol({
    required this.self,
    required this.store,
    required this.random,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// This device.
  final DeviceAddress self;
  final SenderKeyStore store;
  final CryptoRandom random;
  final DateTime Function() _clock;

  @override
  String get protocolId => 'helix.v2.sender-keys';

  @override
  Future<GroupEncryption> encrypt({
    required GroupRoster roster,
    required List<int> content,
  }) async {
    if (roster.devices.contains(self)) {
      throw ArgumentError('the roster must not contain the sending device');
    }
    final now = _clock();
    var key = await store.ownKey(roster.groupId);
    SenderKeyRotationReason? rotated;
    if (key == null) {
      rotated = SenderKeyRotationReason.noKey;
    } else {
      rotated = key.rotationReason(roster, selfAccount: self.account, now: now);
    }
    if (key == null || rotated != null) {
      key = await SenderKeyState.create(
        roster: roster,
        random: random,
        now: now,
      );
    } else {
      key = key.copyWith(members: roster.members, devices: roster.devices);
    }
    final distribution = key.distribution();
    final controls = <DeviceAddress, ContentBody>{
      for (final device in key.devicesNeedingKey(roster)) device: distribution,
    };
    final (message, next) = await GroupSenderChain.encrypt(key, content);
    return GroupEncryption(
      payload: message,
      keyId: key.distributionId,
      controlMessages: controls,
      writes: [OwnSenderKeyWrite(next)],
      rotated: rotated,
    );
  }

  @override
  Future<List<GroupCryptoWrite>> markDelivered({
    required String groupId,
    required String keyId,
    required Iterable<DeviceAddress> devices,
  }) async {
    final key = await store.ownKey(groupId);
    if (key == null || key.distributionId != keyId) return const [];
    return [
      OwnSenderKeyWrite(
        key.copyWith(
          distributedTo: Set.unmodifiable({...key.distributedTo, ...devices}),
        ),
      ),
    ];
  }

  @override
  Future<GroupDecryption> decrypt({
    required String groupId,
    required DeviceAddress sender,
    required SealedPayload payload,
  }) async {
    if (payload is! SenderKeyMessage) {
      throw const MalformedCryptoInputException('not a sender-key message');
    }
    final key = await store.receivedKey(
      sender,
      groupId,
      payload.distributionId,
    );
    if (key == null) {
      throw NoSenderKeyException('no sender key from $sender for this group');
    }
    final (content, next) = await GroupSenderChain.decrypt(
      key,
      payload,
      now: _clock(),
    );
    return GroupDecryption(
      content: content,
      writes: [ReceivedSenderKeyWrite(next)],
    );
  }

  @override
  Future<List<GroupCryptoWrite>> receiveControl({
    required DeviceAddress sender,
    required ContentBody body,
  }) async {
    if (body is! SenderKeyDistributionBody) return const [];
    final existing = await store.receivedKey(
      sender,
      body.groupId,
      body.distributionId,
    );
    if (existing != null) {
      // A repeated distribution never rewinds or replaces a key we hold; a
      // different signing key under the same dist_id is an attack.
      if (!bytesEqual(existing.signingKey, body.signingKey)) {
        throw const UntrustedIdentityException(
          'sender key redistributed with a different signing key',
        );
      }
      return const [];
    }
    return [
      ReceivedSenderKeyWrite(
        ReceivedSenderKey.fromDistribution(sender, body, _clock()),
      ),
    ];
  }
}
