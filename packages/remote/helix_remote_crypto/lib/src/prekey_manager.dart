import 'dart:convert';

import 'package:cryptography/cryptography.dart';

class RemotePrekeyPublication {
  const RemotePrekeyPublication({
    required this.signedPrekeyId,
    required this.signedPrekeyPublic,
    required this.signedPrekeyPrivate,
    required this.signedPrekeySignature,
    required this.oneTimePrekeys,
    required this.createdAt,
    required this.expiresAt,
  });

  final int signedPrekeyId;
  final String signedPrekeyPublic;
  final String signedPrekeyPrivate;
  final String signedPrekeySignature;
  final List<RemoteOneTimePrekey> oneTimePrekeys;
  final DateTime createdAt;
  final DateTime expiresAt;

  List<Map<String, dynamic>> oneTimePrekeyPublicPayloads() => oneTimePrekeys
      .map((key) => {'key_id': key.keyId, 'public_key': key.publicKey})
      .toList();
}

class RemoteOneTimePrekey {
  const RemoteOneTimePrekey({
    required this.keyId,
    required this.publicKey,
    required this.privateKey,
  });

  final int keyId;
  final String publicKey;
  final String privateKey;
}

class RemotePrekeyManager {
  RemotePrekeyManager({X25519? x25519, Ed25519? ed25519})
    : _x25519 = x25519 ?? X25519(),
      _ed25519 = ed25519 ?? Ed25519();

  final X25519 _x25519;
  final Ed25519 _ed25519;

  Future<RemotePrekeyPublication> createPublication({
    required SimpleKeyPair accountIdentitySigningKey,
    required int signedPrekeyId,
    required int firstOneTimePrekeyId,
    int oneTimePrekeyCount = 10,
    DateTime? now,
    Duration signedPrekeyTtl = const Duration(days: 30),
  }) async {
    if (oneTimePrekeyCount <= 0) {
      throw ArgumentError.value(
        oneTimePrekeyCount,
        'oneTimePrekeyCount',
        'must be positive',
      );
    }

    final createdAt = now ?? DateTime.now().toUtc();
    final signedPrekey = await _x25519.newKeyPair();
    final signedPrekeyPublic = await signedPrekey.extractPublicKey();
    final signedPrekeyPrivate = await signedPrekey.extractPrivateKeyBytes();
    final signature = await _ed25519.sign(
      signedPrekeyPublic.bytes,
      keyPair: accountIdentitySigningKey,
    );

    final oneTimePrekeys = <RemoteOneTimePrekey>[];
    for (var i = 0; i < oneTimePrekeyCount; i++) {
      final keyPair = await _x25519.newKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      final privateKey = await keyPair.extractPrivateKeyBytes();
      oneTimePrekeys.add(
        RemoteOneTimePrekey(
          keyId: firstOneTimePrekeyId + i,
          publicKey: base64Url.encode(publicKey.bytes),
          privateKey: base64Url.encode(privateKey),
        ),
      );
    }

    return RemotePrekeyPublication(
      signedPrekeyId: signedPrekeyId,
      signedPrekeyPublic: base64Url.encode(signedPrekeyPublic.bytes),
      signedPrekeyPrivate: base64Url.encode(signedPrekeyPrivate),
      signedPrekeySignature: base64Url.encode(signature.bytes),
      oneTimePrekeys: oneTimePrekeys,
      createdAt: createdAt,
      expiresAt: createdAt.add(signedPrekeyTtl),
    );
  }

  bool shouldReplenish({
    required int availableOneTimePrekeyCount,
    int threshold = 5,
  }) {
    return availableOneTimePrekeyCount < threshold;
  }

  bool isExpired(RemotePrekeyPublication publication, DateTime now) {
    return !now.toUtc().isBefore(publication.expiresAt);
  }
}
