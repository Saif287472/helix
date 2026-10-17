import 'dart:typed_data';

import 'package:helix_remote_server/src/modules/identity/domain/phone_seal.dart';
import 'package:test/test.dart';

/// Reported phone numbers at rest (ADR-030): AES-256-GCM under
/// `HELIX_PHONE_KEY`, bound to the account.
void main() {
  final key = List<int>.generate(32, (i) => i);
  const alice = '01a13afb-fab4-79c5-9499-03cdfb21dc12';
  const bob = '01a13afb-fab4-79c5-9499-03cdfb21dc13';
  const number = '+8801711000001';

  test('a sealed number opens for its own account', () async {
    final seal = PhoneSeal(key);
    final sealed = await seal.seal(alice, number);
    expect(sealed.length, 12 + number.length + 16);
    expect(String.fromCharCodes(sealed), isNot(contains('1711000001')));
    expect(await seal.open(alice, sealed), number);
  });

  test('two seals of one number differ (a fresh nonce each time)', () async {
    final seal = PhoneSeal(key);
    expect(
      await seal.seal(alice, number),
      isNot(equals(await seal.seal(alice, number))),
    );
  });

  test(
    'it does not open for another account, tampered, or another key',
    () async {
      final seal = PhoneSeal(key);
      final sealed = await seal.seal(alice, number);
      expect(await seal.open(bob, sealed), isNull);
      final tampered = Uint8List.fromList(sealed)..[20] ^= 1;
      expect(await seal.open(alice, tampered), isNull);
      final other = PhoneSeal(List<int>.generate(32, (i) => 255 - i));
      expect(await other.open(alice, sealed), isNull);
      expect(await seal.open(alice, sealed.sublist(0, 10)), isNull);
    },
  );
}
