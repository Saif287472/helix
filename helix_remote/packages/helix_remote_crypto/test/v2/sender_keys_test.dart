import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_crypto/src/v2/primitives.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

final class MemorySenderKeyStore implements SenderKeyStore {
  SenderKeyState? own;
  final Map<String, ReceivedSenderKey> received = {};

  static String _k(DeviceAddress s, String g, String d) => '$s|$g|$d';

  @override
  Future<SenderKeyState?> ownKey(String groupId) async =>
      own?.groupId == groupId ? own : null;

  @override
  Future<ReceivedSenderKey?> receivedKey(
    DeviceAddress sender,
    String groupId,
    String distributionId,
  ) async => received[_k(sender, groupId, distributionId)];

  void apply(List<GroupCryptoWrite> writes) {
    for (final w in writes) {
      switch (w) {
        case OwnSenderKeyWrite(:final state):
          own = SenderKeyState.decode(state.encode());
        case ReceivedSenderKeyWrite(:final key):
          received[_k(key.sender, key.groupId, key.distributionId)] =
              ReceivedSenderKey.decode(key.encode());
      }
    }
  }
}

/// One device in a group test.
final class Member {
  Member(this.address, TestClock clock, String seed)
    : protocol = SenderKeyGroupProtocol(
        self: address,
        store: MemorySenderKeyStore(),
        random: SeededRandom(seed),
        clock: clock.call,
      );

  final DeviceAddress address;
  final SenderKeyGroupProtocol protocol;

  MemorySenderKeyStore get store => protocol.store as MemorySenderKeyStore;
}

void main() {
  late TestClock clock;
  late Member a1;
  late Member a2;
  late Member b1;
  late Member c1;

  setUp(() {
    clock = TestClock();
    a1 = Member(DeviceAddress(accountA, deviceA1), clock, 'a1');
    a2 = Member(DeviceAddress(accountA, deviceA2), clock, 'a2');
    b1 = Member(DeviceAddress(accountB, deviceB1), clock, 'b1');
    c1 = Member(DeviceAddress(accountC, deviceC1), clock, 'c1');
  });

  GroupRoster roster(Member sender, List<Member> others) => GroupRoster(
    groupId: groupG,
    members: {
      sender.address.account,
      for (final m in others) m.address.account,
    },
    devices: {for (final m in others) m.address},
  );

  /// Sends [text] from [from]: delivers distributions to their devices,
  /// marks them delivered, and returns the group payload.
  Future<(GroupEncryption, Uint8List)> send(
    Member from,
    List<Member> others,
    String text,
  ) async {
    final out = await from.protocol.encrypt(
      roster: roster(from, others),
      content: utf8.encode(text),
    );
    from.store.apply(out.writes);
    for (final MapEntry(key: device, value: body)
        in out.controlMessages.entries) {
      final to = others.firstWhere((m) => m.address == device);
      to.store.apply(
        await to.protocol.receiveControl(sender: from.address, body: body),
      );
    }
    from.store.apply(
      await from.protocol.markDelivered(
        groupId: groupG,
        keyId: out.keyId,
        devices: out.controlMessages.keys,
      ),
    );
    return (out, out.payload.encode());
  }

  Future<String> receive(Member to, Member from, List<int> wire) async {
    final out = await to.protocol.decrypt(
      groupId: groupG,
      sender: from.address,
      payload: SealedPayload.decode(wire),
    );
    to.store.apply(out.writes);
    return utf8.decode(out.content);
  }

  Future<void> expectThrows<T>(Future<Object?> f) =>
      expectLater(f, throwsA(isA<T>()));

  test(
    'one ciphertext for every member; distributions only when needed',
    () async {
      final (first, w1) = await send(a1, [a2, b1, c1], 'hello group');
      expect(first.rotated, SenderKeyRotationReason.noKey);
      expect(first.controlMessages.keys.toSet(), {
        a2.address,
        b1.address,
        c1.address,
      });
      expect(first.payload, isA<SenderKeyMessage>());
      for (final m in [a2, b1, c1]) {
        expect(await receive(m, a1, w1), 'hello group');
      }
      final (second, w2) = await send(a1, [a2, b1, c1], 'no redistribution');
      expect(second.controlMessages, isEmpty);
      expect(second.rotated, isNull);
      expect(second.keyId, first.keyId);
      expect(await receive(b1, a1, w2), 'no redistribution');
    },
  );

  test('out of order, replay and the forward-skip cap', () async {
    await send(a1, [b1], 'setup');
    final wires = [
      for (var i = 0; i < 6; i++) (await send(a1, [b1], 'm$i')).$2,
    ];
    for (final i in [5, 1, 3, 0, 4, 2]) {
      expect(await receive(b1, a1, wires[i]), 'm$i');
    }
    await expectThrows<DuplicateOrExpiredMessageException>(
      receive(b1, a1, wires[3]),
    );

    // A message 2,001 iterations ahead: refused; 2,000 ahead: accepted.
    var state = a1.store.own!;
    var ck = state.chainKey;
    for (var i = 0; i < 2001; i++) {
      ck = hmacSha256(ck, const [0x02]);
    }
    final far = state.copyWith(iteration: state.iteration + 2001, chainKey: ck);
    final (tooFar, _) = await GroupSenderChain.encrypt(far, utf8.encode('far'));
    await expectThrows<TooManySkippedMessagesException>(
      receive(b1, a1, tooFar.encode()),
    );
    ck = state.chainKey;
    for (var i = 0; i < 2000; i++) {
      ck = hmacSha256(ck, const [0x02]);
    }
    final ok = state.copyWith(iteration: state.iteration + 2000, chainKey: ck);
    final (near, _) = await GroupSenderChain.encrypt(ok, utf8.encode('near'));
    expect(await receive(b1, a1, near.encode()), 'near');
    expect(b1.store.received.values.single.skipped, hasLength(2000));
  });

  test(
    'tampering and forged signatures are refused before decryption',
    () async {
      final (_, wire) = await send(a1, [b1], 'signed');
      final m = SealedPayload.decode(wire) as SenderKeyMessage;
      final before = b1.store.received.values.single.encode();
      final forgedKey = await Ed25519KeyPair.generate(SeededRandom('forger'));
      final variants = [
        SenderKeyMessage(
          distributionId: m.distributionId,
          iteration: m.iteration,
          ciphertext: Uint8List.fromList(m.ciphertext)..[0] ^= 1,
          signature: m.signature,
        ),
        SenderKeyMessage(
          distributionId: m.distributionId,
          iteration: m.iteration,
          ciphertext: m.ciphertext,
          signature: Uint8List.fromList(m.signature)..[0] ^= 1,
        ),
        SenderKeyMessage(
          distributionId: m.distributionId,
          iteration: m.iteration + 1,
          ciphertext: m.ciphertext,
          signature: m.signature,
        ),
        SenderKeyMessage(
          distributionId: m.distributionId,
          iteration: m.iteration,
          ciphertext: m.ciphertext,
          signature: await forgedKey.sign(
            GroupSenderChain.signatureInput(
              groupG,
              m.distributionId,
              m.iteration,
              m.ciphertext,
            ),
          ),
        ),
      ];
      for (final v in variants) {
        await expectThrows<InvalidSignatureException>(
          receive(b1, a1, v.encode()),
        );
        expect(b1.store.received.values.single.encode(), before);
      }
      expect(await receive(b1, a1, wire), 'signed');
      // From another device, or for another group: no key.
      await expectThrows<NoSenderKeyException>(receive(b1, c1, wire));
    },
  );

  test('member removal rotates; the removed member cannot read on', () async {
    final (_, w0) = await send(a1, [b1, c1], 'before');
    expect(await receive(c1, a1, w0), 'before');
    final (after, w1) = await send(a1, [b1], 'after removal');
    expect(after.rotated, SenderKeyRotationReason.memberRemoved);
    expect(after.controlMessages.keys, [b1.address]);
    expect(await receive(b1, a1, w1), 'after removal');
    await expectThrows<NoSenderKeyException>(receive(c1, a1, w1));
  });

  test('device revocation and own device changes rotate', () async {
    final b2 = Member(DeviceAddress(accountB, deviceC1), clock, 'b2');
    await send(a1, [b1, b2], 'x');
    final (r1, _) = await send(a1, [b1], 'b2 revoked');
    expect(r1.rotated, SenderKeyRotationReason.deviceRemoved);
    final (r2, _) = await send(a1, [b1, a2], 'own device added');
    expect(r2.rotated, SenderKeyRotationReason.ownDevicesChanged);
    final (r3, _) = await send(a1, [b1], 'own device removed');
    expect(r3.rotated, SenderKeyRotationReason.ownDevicesChanged);
  });

  test('adding a member does not rotate and hides earlier messages', () async {
    final (_, early) = await send(a1, [b1], 'early');
    final (added, late) = await send(a1, [b1, c1], 'late');
    expect(added.rotated, isNull);
    expect(added.controlMessages.keys, [c1.address]);
    expect(await receive(c1, a1, late), 'late');
    await expectThrows<DuplicateOrExpiredMessageException>(
      receive(c1, a1, early),
    );
  });

  test('time and message-count limits rotate', () async {
    await send(a1, [b1], 'x');
    clock.advance(const Duration(days: 7));
    expect(
      (await send(a1, [b1], 'old')).$1.rotated,
      SenderKeyRotationReason.expired,
    );
    a1.store.own = a1.store.own!.copyWith(iteration: 10000);
    expect(
      (await send(a1, [b1], 'many')).$1.rotated,
      SenderKeyRotationReason.messageLimit,
    );
  });

  test('a redistribution never rewinds or swaps the signing key', () async {
    final (first, _) = await send(a1, [b1], 'x');
    final body =
        first.controlMessages[b1.address]! as SenderKeyDistributionBody;
    expect(
      await b1.protocol.receiveControl(sender: a1.address, body: body),
      isEmpty,
    );
    await expectThrows<UntrustedIdentityException>(
      b1.protocol.receiveControl(
        sender: a1.address,
        body: SenderKeyDistributionBody(
          groupId: body.groupId,
          distributionId: body.distributionId,
          iteration: 0,
          chainKey: body.chainKey,
          signingKey: SeededRandom('other').nextBytes(32),
        ),
      ),
    );
  });

  test('the sending device must not be in its own roster', () async {
    await expectLater(
      a1.protocol.encrypt(roster: roster(a1, [a1, b1]), content: [1]),
      throwsArgumentError,
    );
  });
}
