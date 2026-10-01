import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Device-pair sessions: X3DH, the Double Ratchet with DH steps, caps,
/// replay and tamper rejection, identity checks, resets and simultaneous
/// initiation (CRYPTO_V2.md §3-5, §13a).
void main() {
  late TestClock clock;
  late TestAccount alice;
  late TestAccount bob;
  late TestDevice a;
  late TestDevice b;

  setUp(() async {
    clock = TestClock();
    final random = SeededRandom('session');
    alice = await TestAccount.create(accountA, random);
    bob = await TestAccount.create(accountB, random);
    a = await TestDevice.create(alice, deviceA1, random, clock);
    b = await TestDevice.create(bob, deviceB1, random, clock);
    a.trust(b);
    b.trust(a);
  });

  Future<void> expectThrows<T>(Future<Object?> future) =>
      expectLater(future, throwsA(isA<T>()));

  group('session setup', () {
    test(
      'prekey messages until the first reply, then ratchet messages',
      () async {
        await a.startSessionWith(b);
        final m1 = await a.send(b, 'hello');
        final m2 = await a.send(b, 'again');
        expect(SealedPayload.decode(m1), isA<PrekeyMessage>());
        expect(SealedPayload.decode(m2), isA<PrekeyMessage>());
        expect((SealedPayload.decode(m1) as PrekeyMessage).oneTimePrekeyId, 1);

        expect(await b.receive(a, m1), 'hello');
        expect(b.prekeys.oneTime.containsKey(1), isFalse, reason: 'OPK used');
        expect(await b.receive(a, m2), 'again');

        final r1 = await b.send(a, 'hi alice');
        expect(SealedPayload.decode(r1), isA<RatchetMessage>());
        expect(await a.receive(b, r1), 'hi alice');

        final m3 = await a.send(b, 'now ratchet');
        expect(SealedPayload.decode(m3), isA<RatchetMessage>());
        expect(await b.receive(a, m3), 'now ratchet');
      },
    );

    test('works without a one-time prekey (X3DH without DH4)', () async {
      await a.startSessionWith(b, withOneTime: false);
      final m1 = await a.send(b, 'no opk');
      expect(
        (SealedPayload.decode(m1) as PrekeyMessage).oneTimePrekeyId,
        isNull,
      );
      expect(await b.receive(a, m1), 'no opk');
      expect(b.prekeys.oneTime, hasLength(5));
    });

    test('each turn of the conversation uses a new ratchet key', () async {
      await a.startSessionWith(b);
      final keys = <String>{};
      for (var turn = 0; turn < 6; turn++) {
        final (from, to) = turn.isEven ? (a, b) : (b, a);
        final wire = await from.send(to, 'turn $turn');
        final payload = SealedPayload.decode(wire);
        final header = switch (payload) {
          PrekeyMessage(:final header) => header,
          RatchetMessage(:final header) => header,
          _ => throw StateError('unexpected'),
        };
        keys.add(hex(header.ratchetKey));
        expect(await to.receive(from, wire), 'turn $turn');
      }
      expect(keys, hasLength(6), reason: 'a DH ratchet step every turn');
    });

    test('a device with no session cannot encrypt', () async {
      await expectThrows<NoSessionException>(
        a.manager.encrypt(b.address, utf8.encode('x')),
      );
    });

    test('session state survives a byte round trip unchanged', () async {
      await a.startSessionWith(b);
      final m = await a.send(b, 'x');
      await b.receive(a, m);
      final stored = b.sessions.rows[a.address]!;
      expect(DeviceSessions.decode(stored).encode(), stored);
      expect(
        () => DeviceSessions.decode(utf8.encode('{"v":9}')),
        throwsA(isA<MalformedCryptoInputException>()),
      );
    });
  });

  group('out of order and dropped messages', () {
    for (final seed in [1, 2, 3, 4, 5]) {
      test('random interleaving and drops, seed $seed', () async {
        final rng = Random(seed);
        await a.startSessionWith(b);
        // Establish so both can send.
        await b.receive(a, await a.send(b, 'open'));
        await a.receive(b, await b.send(a, 'ack'));

        final inFlight = <(TestDevice, TestDevice, Uint8List, String)>[];
        for (var round = 0; round < 6; round++) {
          final (from, to) = rng.nextBool() ? (a, b) : (b, a);
          final count = 1 + rng.nextInt(12);
          for (var i = 0; i < count; i++) {
            final text = 'r$round-$i-${from.address.device}';
            inFlight.add((from, to, await from.send(to, text), text));
          }
          // Deliver a random part of what is in flight, in random order.
          inFlight.shuffle(rng);
          final deliver = rng.nextInt(inFlight.length + 1);
          for (final (from, to, wire, text) in inFlight.take(deliver)) {
            expect(await to.receive(from, wire), text);
          }
          inFlight.removeRange(0, deliver);
        }
        // Drop a few, deliver the rest late and shuffled.
        inFlight.shuffle(rng);
        final dropped = inFlight.length ~/ 3;
        for (final (from, to, wire, text) in inFlight.skip(dropped)) {
          expect(await to.receive(from, wire), text);
        }
        // The conversation still works both ways after drops.
        expect(await b.receive(a, await a.send(b, 'after')), 'after');
        expect(await a.receive(b, await b.send(a, 'reply')), 'reply');
      });
    }

    test('messages from the previous chain arrive after a DH step', () async {
      await a.startSessionWith(b);
      await b.receive(a, await a.send(b, 'open'));
      final old1 = await b.send(a, 'old 1');
      final old2 = await b.send(a, 'old 2');
      expect(await a.receive(b, old2), 'old 2');
      // Alice turns; Bob turns again (a new chain); then the late one.
      await b.receive(a, await a.send(b, 'turn'));
      expect(await a.receive(b, await b.send(a, 'new chain')), 'new chain');
      expect(await a.receive(b, old1), 'old 1');
    });
  });

  group('skipped-key caps', () {
    Future<void> establish() async {
      await a.startSessionWith(b);
      await b.receive(a, await a.send(b, 'open'));
      await a.receive(b, await b.send(a, 'ack'));
    }

    test('at most 1,000 skipped keys per chain for one message', () async {
      await establish();
      final wires = [for (var i = 0; i < 1002; i++) await a.send(b, 'm$i')];
      // Index 1001 needs 1,001 skips: refused, state untouched.
      await expectThrows<TooManySkippedMessagesException>(
        b.receive(a, wires[1001]),
      );
      // Index 1000 needs exactly 1,000: accepted.
      expect(await b.receive(a, wires[1000]), 'm1000');
      expect(await b.receive(a, wires[1001]), 'm1001');
      expect(await b.receive(a, wires[0]), 'm0');
      expect(await b.receive(a, wires[999]), 'm999');
    });

    test('at most 2,000 stored per session; the oldest are evicted', () async {
      await establish();
      final chain1 = [for (var i = 0; i < 1001; i++) await a.send(b, 'c1-$i')];
      expect(await b.receive(a, chain1[1000]), 'c1-1000'); // 1,000 stored
      await a.receive(b, await b.send(a, 'turn 1'));
      final chain2 = [for (var i = 0; i < 1001; i++) await a.send(b, 'c2-$i')];
      expect(await b.receive(a, chain2[1000]), 'c2-1000'); // 2,000 stored
      await a.receive(b, await b.send(a, 'turn 2'));
      final chain3 = [for (var i = 0; i < 3; i++) await a.send(b, 'c3-$i')];
      expect(await b.receive(a, chain3[2]), 'c3-2'); // 2,002: evict 2

      final stored = DeviceSessions.decode(b.sessions.rows[a.address]!);
      expect(stored.active!.ratchet.skipped, hasLength(2000));
      await expectThrows<DuplicateOrExpiredMessageException>(
        b.receive(a, chain1[0]),
      );
      await expectThrows<DuplicateOrExpiredMessageException>(
        b.receive(a, chain1[1]),
      );
      expect(await b.receive(a, chain1[2]), 'c1-2');
      expect(await b.receive(a, chain2[0]), 'c2-0');
      expect(await b.receive(a, chain3[0]), 'c3-0');
    });

    test('skipped keys expire after 30 days', () async {
      await establish();
      final late = await a.send(b, 'late');
      expect(await b.receive(a, await a.send(b, 'first')), 'first');
      clock.advance(const Duration(days: 30, seconds: 1));
      await expectThrows<DuplicateOrExpiredMessageException>(
        b.receive(a, late),
      );
    });
  });

  group('replay and tampering', () {
    test(
      'a replayed message is rejected and the session keeps working',
      () async {
        await a.startSessionWith(b);
        final m1 = await a.send(b, 'once');
        expect(await b.receive(a, m1), 'once');
        await expectThrows<DuplicateOrExpiredMessageException>(
          b.receive(a, m1),
        );
        final r = await b.send(a, 'reply');
        expect(await a.receive(b, r), 'reply');
        await expectThrows<DuplicateOrExpiredMessageException>(a.receive(b, r));
        // A replayed message from a finished chain.
        final m2 = await a.send(b, 'next');
        expect(await b.receive(a, m2), 'next');
        expect(await a.receive(b, await b.send(a, 'turn')), 'turn');
        await expectThrows<DuplicateOrExpiredMessageException>(
          b.receive(a, m1),
        );
      },
    );

    test('a replayed prekey message never creates a second session', () async {
      await a.startSessionWith(b, withOneTime: false);
      final m1 = await a.send(b, 'first');
      expect(await b.receive(a, m1), 'first');
      await expectThrows<DuplicateOrExpiredMessageException>(b.receive(a, m1));
      // Even after Bob drops every session (no OPK protects this one).
      b.sessions.save(
        DeviceSessions.decode(b.sessions.rows[a.address]!).cleared(),
      );
      await expectThrows<DuplicateOrExpiredMessageException>(b.receive(a, m1));
    });

    test('tampered ciphertext, header or AD fail and change nothing', () async {
      await a.startSessionWith(b);
      await b.receive(a, await a.send(b, 'open'));
      await a.receive(b, await b.send(a, 'ack'));
      final wire = await a.send(b, 'target');
      final message = SealedPayload.decode(wire) as RatchetMessage;
      final before = b.sessions.rows[a.address];

      Uint8List rebuild({RatchetHeader? header, Uint8List? ciphertext}) =>
          RatchetMessage(
            header: header ?? message.header,
            ciphertext: ciphertext ?? message.ciphertext,
          ).encode();

      final h = message.header;
      final tampered = [
        rebuild(ciphertext: Uint8List.fromList(message.ciphertext)..[0] ^= 1),
        rebuild(
          ciphertext: Uint8List.fromList(message.ciphertext)
            ..[message.ciphertext.length - 1] ^= 1,
        ),
        rebuild(
          header: RatchetHeader(
            ratchetKey: h.ratchetKey,
            previousCount: h.previousCount + 1,
            count: h.count,
          ),
        ),
        rebuild(
          header: RatchetHeader(
            ratchetKey: h.ratchetKey,
            previousCount: h.previousCount,
            count: h.count + 1,
          ),
        ),
        rebuild(
          header: RatchetHeader(
            ratchetKey: Uint8List.fromList(h.ratchetKey)..[3] ^= 0x10,
            previousCount: h.previousCount,
            count: h.count,
          ),
        ),
      ];
      for (final bad in tampered) {
        await expectThrows<CryptoV2Exception>(b.receive(a, bad));
        expect(b.sessions.rows[a.address], before, reason: 'no commit');
      }
      expect(await b.receive(a, wire), 'target');

      // Same message under a different AD (another device pair) fails.
      final session = DeviceSessions.decode(b.sessions.rows[a.address]!);
      final next =
          SealedPayload.decode(await a.send(b, 'ad')) as RatchetMessage;
      await expectThrows<DecryptionFailedException>(
        DoubleRatchet.decrypt(
          session.active!.ratchet,
          next.header,
          next.ciphertext,
          associatedData: Uint8List.fromList(session.active!.associatedData)
            ..[20] ^= 1,
          now: clock.now,
          random: SeededRandom('ad'),
        ),
      );
    });

    test('a group payload is not accepted as a pairwise one', () async {
      await expectThrows<MalformedCryptoInputException>(
        b.manager.decrypt(
          sender: a.address,
          payload: SenderKeyMessage(
            distributionId: groupG,
            iteration: 0,
            ciphertext: Uint8List(16),
            signature: Uint8List(64),
          ),
        ),
      );
    });
  });

  group('identity verification', () {
    test('a bundle certified by another account key is refused', () async {
      final mallory = await TestAccount.create(accountC, SeededRandom('m'));
      await expectThrows<UntrustedIdentityException>(
        VerifiedPrekeyBundle.verify(
          account: bob.id,
          accountIdentityKey: mallory.aik.publicKey,
          bundle: b.bundle(),
        ),
      );
    });

    test('a bundle whose SPK signature fails is refused', () async {
      final good = b.bundle();
      final forged = DeviceBundle(
        deviceId: good.deviceId,
        identityKey: good.identityKey,
        signingKey: good.signingKey,
        certificate: good.certificate,
        signedPrekey: SignedPrekey(
          id: good.signedPrekey.id,
          publicKey: SeededRandom('evil spk').nextBytes(32),
          signature: good.signedPrekey.signature,
        ),
        oneTimePrekey: good.oneTimePrekey,
      );
      await expectThrows<InvalidSignatureException>(
        VerifiedPrekeyBundle.verify(
          account: bob.id,
          accountIdentityKey: bob.aik.publicKey,
          bundle: forged,
        ),
      );
    });

    test(
      'a bundle whose keys differ from the certificate is refused',
      () async {
        final good = b.bundle();
        final swapped = DeviceBundle(
          deviceId: good.deviceId,
          identityKey: SeededRandom('evil dik').nextBytes(32),
          signingKey: good.signingKey,
          certificate: good.certificate,
          signedPrekey: good.signedPrekey,
        );
        await expectThrows<UntrustedIdentityException>(
          VerifiedPrekeyBundle.verify(
            account: bob.id,
            accountIdentityKey: bob.aik.publicKey,
            bundle: swapped,
          ),
        );
      },
    );

    test(
      'account keys report AIK pinning and refuse another account',
      () async {
        final keys = AccountKeys(
          account: bob.id,
          identityKey: bob.aik.publicKey,
          devices: [b.bundle()],
        );
        final first = await VerifiedAccountKeys.verify(
          account: bob.id,
          keys: keys,
        );
        expect(first.pin, AikPinResult.firstUse);
        final same = await VerifiedAccountKeys.verify(
          account: bob.id,
          keys: keys,
          pinnedAccountIdentityKey: bob.aik.publicKey,
        );
        expect(same.pin, AikPinResult.matches);
        final changed = await VerifiedAccountKeys.verify(
          account: bob.id,
          keys: keys,
          pinnedAccountIdentityKey: alice.aik.publicKey,
        );
        expect(changed.pin, AikPinResult.changed);
        await expectThrows<UntrustedIdentityException>(
          VerifiedAccountKeys.verify(account: alice.id, keys: keys),
        );
      },
    );

    test(
      'a prekey message whose DIK is not the sender device key is refused',
      () async {
        final mallory = await TestAccount.create(accountC, SeededRandom('m'));
        final m = await TestDevice.create(
          mallory,
          deviceC1,
          SeededRandom('m1'),
          clock,
        );
        await m.startSessionWith(b);
        final forged = await m.send(b, 'I am Alice');
        // The server says it came from Alice's device; Bob knows Alice's DIK.
        await expectThrows<UntrustedIdentityException>(b.receive(a, forged));
        expect(b.sessions.rows, isEmpty);
      },
    );

    test('a prekey message from an unknown device is refused', () async {
      b.identities.known.clear();
      await a.startSessionWith(b);
      await expectThrows<UntrustedIdentityException>(
        b.receive(a, await a.send(b, 'hi')),
      );
    });

    test('unknown or used prekeys are refused without fallback', () async {
      final stale = await b.verifiedBundle();
      await a.startSessionWith(b);
      expect(await b.receive(a, await a.send(b, 'uses opk 1')), 'uses opk 1');

      // A second device of Alice with the same (now used) OPK.
      final a2 = await TestDevice.create(
        alice,
        deviceA2,
        SeededRandom('a2'),
        clock,
      );
      b.trust(a2);
      a2.sessions.save(await a2.manager.startSession(stale));
      final reuse = await a2.send(b, 'reuses opk 1');
      await expectLater(
        b.receive(a2, reuse),
        throwsA(
          isA<UnknownPrekeyException>().having(
            (e) => e.requestsSessionReset,
            'requestsSessionReset',
            isTrue,
          ),
        ),
      );

      // An SPK this device no longer has.
      b.prekeys.signed.clear();
      final a3 = await TestDevice.create(
        alice,
        deviceA2,
        SeededRandom('a3'),
        clock,
      );
      b.trust(a3);
      a3.sessions.save(await a3.manager.startSession(stale));
      await expectThrows<UnknownPrekeyException>(
        b.receive(a3, await a3.send(b, 'old spk')),
      );
    });
  });

  group('session reset (§13a)', () {
    test('lost state: NoSession, then a fresh session and a re-send', () async {
      await a.startSessionWith(b);
      await b.receive(a, await a.send(b, 'open'));
      await a.receive(b, await b.send(a, 'ack'));

      // Bob restores from a backup: no session state.
      b.sessions.rows.clear();
      final lost = await a.send(b, 'lost');
      await expectLater(
        b.receive(a, lost),
        throwsA(
          isA<NoSessionException>().having(
            (e) => e.requestsSessionReset,
            'requestsSessionReset',
            isTrue,
          ),
        ),
      );

      // Bob answers over a new session; Alice adopts it and re-sends.
      await b.startSessionWith(a);
      final error = await b.send(a, 'decryption_error');
      expect(SealedPayload.decode(error), isA<PrekeyMessage>());
      expect(await a.receive(b, error), 'decryption_error');
      final aSessions = DeviceSessions.decode(a.sessions.rows[b.address]!);
      expect(aSessions.previous, hasLength(1));

      final resent = await a.send(b, 'lost');
      expect(await b.receive(a, resent), 'lost');
      expect(await a.receive(b, await b.send(a, 'thanks')), 'thanks');
    });

    test('previous sessions are capped at five', () async {
      for (var i = 0; i < 7; i++) {
        await a.startSessionWith(b, withOneTime: false);
      }
      final record = DeviceSessions.decode(a.sessions.rows[b.address]!);
      expect(record.previous, hasLength(DeviceSessions.maxPrevious));
      expect(record.retiredBaseKeys, hasLength(1));
    });
  });

  group('simultaneous initiation', () {
    test('both sides start at once and converge on one session', () async {
      await a.startSessionWith(b);
      await b.startSessionWith(a);
      final fromA = await a.send(b, 'A first');
      final fromB = await b.send(a, 'B first');
      expect(await b.receive(a, fromA), 'A first');
      expect(await a.receive(b, fromB), 'B first');

      for (var i = 0; i < 4; i++) {
        expect(await b.receive(a, await a.send(b, 'a$i')), 'a$i');
        expect(await a.receive(b, await b.send(a, 'b$i')), 'b$i');
      }
      final sa = DeviceSessions.decode(a.sessions.rows[b.address]!).active!;
      final sb = DeviceSessions.decode(b.sessions.rows[a.address]!).active!;
      expect(hex(sa.baseKey), hex(sb.baseKey));
      expect(sa.pendingPrekey, isNull);
      expect(sb.pendingPrekey, isNull);
    });
  });
}
