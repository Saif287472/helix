import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/crypto.dart';
import 'package:helix_remote_server/src/kernel/jwt.dart';
import 'package:test/test.dart';

/// MED-3 (regression matrix): signatures and secrets are compared in constant
/// time, and token verification fails closed. No database needed.
void main() {
  group('constantTimeEquals', () {
    test('agrees with == on every case == would handle', () {
      final cases = <(List<int>, List<int>, bool)>[
        ([], [], true),
        ([1], [1], true),
        ([1, 2, 3], [1, 2, 3], true),
        ([1, 2, 3], [1, 2, 4], false),
        ([0, 2, 3], [1, 2, 3], false),
        ([1, 2, 3], [1, 2], false),
        ([1, 2], [1, 2, 3], false),
        ([], [0], false),
        ([255, 255], [255, 254], false),
      ];
      for (final (a, b, equal) in cases) {
        expect(constantTimeEquals(a, b), equal, reason: '$a vs $b');
        expect(constantTimeEquals(b, a), equal, reason: '$b vs $a');
      }
    });
  });

  group('HmacJwt', () {
    final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
    final other = Uint8List.fromList(List.generate(32, (i) => 200 - i));
    final now = DateTime.utc(2026, 10, 5, 12);
    final jwt = HmacJwt(keys: {'k1': key}, activeKid: 'k1');

    String token({
      HmacJwt? signer,
      String audience = 'helix.device',
      String type = 'access',
      Duration lifetime = const Duration(minutes: 15),
    }) => (signer ?? jwt).sign(
      audience: audience,
      type: type,
      issuedAt: now,
      expiresAt: now.add(lifetime),
      claims: {'sub': 'abc'},
    );

    Map<String, Object?>? verify(
      String t, {
      HmacJwt? verifier,
      String audience = 'helix.device',
      String type = 'access',
      DateTime? at,
    }) => (verifier ?? jwt).verify(
      t,
      audience: audience,
      type: type,
      now: at ?? now,
    );

    test('a fresh token verifies', () {
      expect(verify(token())?['sub'], 'abc');
    });

    test('a changed signature, payload or key is refused', () {
      final parts = token().split('.');
      final badSignature = [
        ...parts.take(2),
        encodeBytes(Uint8List(32)),
      ].join('.');
      expect(verify(badSignature), isNull);

      final forgedPayload = encodeBytes(
        utf8.encode(
          jsonEncode({
            'iss': HmacJwt.issuer,
            'aud': 'helix.device',
            'typ': 'access',
            'exp': now.millisecondsSinceEpoch ~/ 1000 + 3600,
            'ims': now.millisecondsSinceEpoch,
            'sub': 'someone-else',
          }),
        ),
      );
      expect(verify([parts[0], forgedPayload, parts[2]].join('.')), isNull);

      final stranger = HmacJwt(keys: {'k1': other}, activeKid: 'k1');
      expect(verify(token(signer: stranger)), isNull);
    });

    test('the wrong audience, the wrong type and an expired token fail', () {
      expect(verify(token(audience: 'helix.admin')), isNull);
      expect(verify(token(type: 'refresh')), isNull);
      expect(verify(token(), at: now.add(const Duration(minutes: 16))), isNull);
      expect(verify('not.a.token'), isNull);
      expect(verify(''), isNull);
    });

    test('a ring verifies old keys and signs with the active one', () {
      final old = HmacJwt(keys: {'k1': key}, activeKid: 'k1');
      final rotated = HmacJwt(keys: {'k1': key, 'k2': other}, activeKid: 'k2');
      expect(verify(token(signer: old), verifier: rotated), isNotNull);
      expect(verify(token(signer: rotated), verifier: rotated), isNotNull);
      expect(verify(token(signer: rotated), verifier: old), isNull);
    });
  });
}
