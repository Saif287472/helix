import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('envelopes', () {
    test('server-generated kinds carry data, not payloads', () {
      final roster = const RosterChangeEvent(
        groupId: groupG,
        change: RosterChangeKind.removed,
        epoch: 3,
        actor: accountA,
        members: [accountB],
      );
      final envelope = expectRoundTrip(
        Envelope(
          id: messageM,
          kind: EnvelopeKind.rosterChange,
          sentAt: t0,
          seq: 7,
          groupId: groupG,
          data: roster.toJson(),
        ),
        (v) => v.toJson(),
        Envelope.fromJson,
      );
      expect(envelope.kind.isServerGenerated, isTrue);
      expect(envelope.from, isNull);
      expect(RosterChangeEvent.fromJson(JsonReader(envelope.data!)).members, [
        accountB,
      ]);
    });

    test('ephemeral envelopes have no seq', () {
      final envelope = Envelope.fromJson(
        JsonReader({
          'id': messageM,
          'kind': 'call_signal',
          'sent_at': 0,
          'call_id': 'c1',
          'payload': encodeBytes(bytes(10)),
        }),
      );
      expect(envelope.isEphemeral, isTrue);
      expect(envelope.callId, 'c1');
      expect(envelope.urgent, isFalse);
    });

    test('unknown kinds decode as unknown (acked and ignored)', () {
      final envelope = Envelope.fromJson(
        JsonReader({
          'id': messageM,
          'kind': 'teleport',
          'sent_at': 0,
          'seq': 1,
        }),
      );
      expect(envelope.kind, EnvelopeKind.unknown);
    });

    test('event payloads round-trip', () {
      expectRoundTrip(
        KeyChangeEvent(account: accountB, identityKey: bytes(32)),
        (v) => v.toJson(),
        KeyChangeEvent.fromJson,
      );
      expectRoundTrip(
        AccountSignalEvent(
          signal: AccountSignalKind.newSignIn,
          at: t0,
          device: deviceA1,
          deviceName: 'Laptop',
        ),
        (v) => v.toJson(),
        AccountSignalEvent.fromJson,
      );
      expectRoundTrip(
        const PrekeysLowEvent(remaining: 4),
        (v) => v.toJson(),
        PrekeysLowEvent.fromJson,
      );
      expectRoundTrip(
        const DeviceListChangeEvent(account: accountB),
        (v) => v.toJson(),
        DeviceListChangeEvent.fromJson,
      );
    });
  });

  group('sealed payloads', () {
    final header = RatchetHeader(
      ratchetKey: bytes(32),
      previousCount: 2,
      count: 9,
    );

    test('all three forms round-trip through bytes', () {
      final payloads = <SealedPayload>[
        PrekeyMessage(
          senderIdentityKey: bytes(32, 1),
          ephemeralKey: bytes(32, 2),
          signedPrekeyId: 12,
          oneTimePrekeyId: 345,
          header: header,
          ciphertext: bytes(160),
        ),
        RatchetMessage(header: header, ciphertext: bytes(320)),
        SenderKeyMessage(
          distributionId: 'd1',
          iteration: 42,
          ciphertext: bytes(160),
          signature: bytes(64),
        ),
      ];
      for (final payload in payloads) {
        final decoded = SealedPayload.decode(payload.encode());
        expect(decoded.runtimeType, payload.runtimeType);
        expect(decoded.toJson(), payload.toJson());
      }
    });

    test('version and type are checked', () {
      expect(
        () => SealedPayload.decode('{"v":1,"t":"ratchet"}'.codeUnits),
        throwsA(isA<ProtocolFormatException>()),
      );
      expect(
        () => SealedPayload.decode('{"v":2,"t":"quantum"}'.codeUnits),
        throwsA(isA<ProtocolFormatException>()),
      );
      expect(
        () => SealedPayload.decode([0xff]),
        throwsA(isA<ProtocolFormatException>()),
      );
    });

    test('authenticated header bytes are fixed-layout', () {
      final bytes = header.toAuthenticatedBytes();
      expect(bytes.length, 12 + 32 + 4 + 4);
      expect(String.fromCharCodes(bytes.sublist(0, 12)), 'helix.v2.hdr');
    });
  });

  group('realtime frames', () {
    test('server frames round-trip', () {
      final frames = <ServerFrame>[
        HelloFrame(
          serverTime: t0,
          heartbeatSeconds: 25,
          window: 100,
          lastSeq: 9,
        ),
        EnvelopeFrame(
          Envelope(
            id: messageM,
            kind: EnvelopeKind.prekeysLow,
            sentAt: t0,
            seq: 3,
            data: const {'remaining': 1},
          ),
        ),
        const WakeFrame(),
        const PongFrame(nonce: 'n'),
        const ErrorFrame(code: 'protocol_error', message: 'bad frame'),
      ];
      for (final frame in frames) {
        final decoded = ServerFrame.decode(frame.encode());
        expect(decoded.runtimeType, frame.runtimeType);
        expect(decoded.toJson(), frame.toJson());
      }
    });

    test('client frames round-trip; unknown frames are tolerated', () {
      for (final frame in const <ClientFrame>[
        AckFrame(seq: 5),
        PingFrame(nonce: 'x'),
      ]) {
        expect(ClientFrame.decode(frame.encode()).toJson(), frame.toJson());
      }
      expect(ClientFrame.decode('{"t":"dance"}'), isA<UnknownClientFrame>());
      final unknown = ServerFrame.decode('{"t":"future","seq":4}');
      expect(unknown, isA<UnknownServerFrame>());
      expect((unknown as UnknownServerFrame).seq, 4);
    });
  });
}
