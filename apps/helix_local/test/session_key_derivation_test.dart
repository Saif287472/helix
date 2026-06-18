import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_local_crypto/crypto/session_key_derivation.dart';

void main() {
  test('identity proof payload preserves legacy format', () {
    final payload = buildIdentityProofPayload('abcd');

    expect(String.fromCharCodes(payload), 'Helix-identity-v1abcd');
  });

  test('directional chain keys are complementary for both peers', () async {
    final aliceDer = Uint8List.fromList([1, 2, 3, 4]);
    final bobDer = Uint8List.fromList([5, 6, 7, 8]);

    final alice = await deriveDirectionalChainKeys(
      localSessionId: 'alice',
      peerSessionId: 'bob',
      localPublicKeyDer: aliceDer,
      peerPublicKeyDer: bobDer,
    );
    final bob = await deriveDirectionalChainKeys(
      localSessionId: 'bob',
      peerSessionId: 'alice',
      localPublicKeyDer: bobDer,
      peerPublicKeyDer: aliceDer,
    );

    expect(
      await alice.sendChainKey.extractBytes(),
      await bob.receiveChainKey.extractBytes(),
    );
    expect(
      await alice.receiveChainKey.extractBytes(),
      await bob.sendChainKey.extractBytes(),
    );
  });

  test('ratchetChainKey advances key material deterministically', () async {
    final keys = await deriveDirectionalChainKeys(
      localSessionId: 'alice',
      peerSessionId: 'bob',
      localPublicKeyDer: Uint8List.fromList([1, 2, 3, 4]),
      peerPublicKeyDer: Uint8List.fromList([5, 6, 7, 8]),
    );

    final nextA = await ratchetChainKey(keys.sendChainKey);
    final nextB = await ratchetChainKey(keys.sendChainKey);

    expect(await nextA.extractBytes(), await nextB.extractBytes());
    expect(
      await nextA.extractBytes(),
      isNot(await keys.sendChainKey.extractBytes()),
    );
  });

  test('zeroMutableBytes clears owned buffers', () {
    final bytes = Uint8List.fromList([1, 2, 3]);

    zeroMutableBytes(bytes);

    expect(bytes, [0, 0, 0]);
  });
}
