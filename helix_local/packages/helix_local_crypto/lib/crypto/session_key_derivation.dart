import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;

const sessionKeyLengthBytes = 32;

const _hkdfSalt = <int>[
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
];

class DirectionalChainKeys {
  const DirectionalChainKeys({
    required this.sendChainKey,
    required this.receiveChainKey,
  });

  final crypto.SecretKey sendChainKey;
  final crypto.SecretKey receiveChainKey;
}

Future<DirectionalChainKeys> deriveDirectionalChainKeys({
  required String localSessionId,
  required String peerSessionId,
  required Uint8List localPublicKeyDer,
  required Uint8List peerPublicKeyDer,
}) async {
  final weAreSmaller = localSessionId.compareTo(peerSessionId) < 0;
  final firstSession = weAreSmaller ? localSessionId : peerSessionId;
  final secondSession = weAreSmaller ? peerSessionId : localSessionId;
  final firstDer = weAreSmaller ? localPublicKeyDer : peerPublicKeyDer;
  final secondDer = weAreSmaller ? peerPublicKeyDer : localPublicKeyDer;
  final ikm = buildChainSeed(
    firstSessionId: firstSession,
    firstPublicKeyDer: firstDer,
    secondSessionId: secondSession,
    secondPublicKeyDer: secondDer,
  );
  try {
    final keyA = await _deriveHkdf(ikm, 'helix-chain-a');
    final keyB = await _deriveHkdf(ikm, 'helix-chain-b');
    return DirectionalChainKeys(
      sendChainKey: weAreSmaller ? keyA : keyB,
      receiveChainKey: weAreSmaller ? keyB : keyA,
    );
  } finally {
    zeroMutableBytes(ikm);
  }
}

Future<crypto.SecretKey> ratchetChainKey(crypto.SecretKey current) {
  return _deriveHkdfFromSecret(current, 'helix-ratchet');
}

Uint8List buildIdentityProofPayload(String sessionId) {
  final prefix = utf8.encode('Helix-identity-v1');
  final sid = ascii.encode(sessionId);
  final out = Uint8List(prefix.length + sid.length);
  out.setAll(0, prefix);
  out.setAll(prefix.length, sid);
  return out;
}

Uint8List buildChainSeed({
  required String firstSessionId,
  required Uint8List firstPublicKeyDer,
  required String secondSessionId,
  required Uint8List secondPublicKeyDer,
}) {
  final out = BytesBuilder(copy: false);
  out.add(utf8.encode('Helix-chain-seed-v1'));
  _addLengthPrefixed(out, utf8.encode(firstSessionId));
  _addLengthPrefixed(out, firstPublicKeyDer);
  _addLengthPrefixed(out, utf8.encode(secondSessionId));
  _addLengthPrefixed(out, secondPublicKeyDer);
  return out.toBytes();
}

void zeroMutableBytes(Uint8List bytes) {
  bytes.fillRange(0, bytes.length, 0);
}

Future<crypto.SecretKey> _deriveHkdf(Uint8List ikm, String info) {
  return _deriveHkdfFromSecret(crypto.SecretKey(ikm), info);
}

Future<crypto.SecretKey> _deriveHkdfFromSecret(
  crypto.SecretKey secret,
  String info,
) {
  final hkdf = crypto.Hkdf(
    hmac: crypto.Hmac(crypto.Sha256()),
    outputLength: sessionKeyLengthBytes,
  );
  return hkdf.deriveKey(
    secretKey: secret,
    nonce: _hkdfSalt,
    info: utf8.encode(info),
  );
}

void _addLengthPrefixed(BytesBuilder out, List<int> bytes) {
  final length = ByteData(4)..setUint32(0, bytes.length, Endian.big);
  out.add(length.buffer.asUint8List());
  out.add(bytes);
}
