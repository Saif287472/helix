import 'dart:typed_data';

import 'package:helix_remote_crypto/src/v2/identity.dart';
import 'package:helix_remote_crypto/src/v2/primitives.dart';

/// X3DH session setup per device pair (CRYPTO_V2.md §4).
///
/// ```
/// DH1 = X25519(DIK_A, SPK_B)   DH2 = X25519(EK, DIK_B)
/// DH3 = X25519(EK, SPK_B)      DH4 = X25519(EK, OPK_B)   (if an OPK)
/// SK  = HKDF(0xFF*32 ‖ DH1 ‖ DH2 ‖ DH3 [‖ DH4], salt = 0x00*32,
///            info = "helix.v2.x3dh", len = 32)
/// AD  = "helix.v2.ad" ‖ account_A ‖ device_A ‖ DIK_A ‖ account_B ‖ device_B ‖ DIK_B
/// ```
abstract final class X3dh {
  static const info = 'helix.v2.x3dh';
  static const adLabel = 'helix.v2.ad';

  /// The session's associated data; A is always the initiator.
  static Uint8List associatedData({
    required DeviceAddress initiator,
    required List<int> initiatorIdentityKey,
    required DeviceAddress responder,
    required List<int> responderIdentityKey,
  }) {
    requireLength(initiatorIdentityKey, 32, 'DIK');
    requireLength(responderIdentityKey, 32, 'DIK');
    return concatBytes([
      label(adLabel),
      initiator.accountBytes,
      initiator.deviceBytes,
      initiatorIdentityKey,
      responder.accountBytes,
      responder.deviceBytes,
      responderIdentityKey,
    ]);
  }

  /// Initiator side. [bundle] is already verified (certificate and SPK
  /// signature), which [VerifiedPrekeyBundle] guarantees by construction.
  static Future<X3dhInitiation> initiate({
    required LocalDeviceKeys local,
    required VerifiedPrekeyBundle bundle,
    required CryptoRandom random,
  }) async {
    final ephemeral = await X25519KeyPair.generate(random);
    final remote = bundle.identity;
    final dh1 = await local.identityKey.agree(bundle.signedPrekey);
    final dh2 = await ephemeral.agree(remote.identityKey);
    final dh3 = await ephemeral.agree(bundle.signedPrekey);
    final dh4 = bundle.oneTimePrekey == null
        ? null
        : await ephemeral.agree(bundle.oneTimePrekey!);
    return X3dhInitiation._(
      sharedSecret: _sharedSecret(dh1, dh2, dh3, dh4),
      associatedData: associatedData(
        initiator: local.address,
        initiatorIdentityKey: local.identityKey.publicKey,
        responder: remote.address,
        responderIdentityKey: remote.identityKey,
      ),
      ephemeralKey: ephemeral.publicKey,
      signedPrekeyId: bundle.signedPrekeyId,
      signedPrekey: bundle.signedPrekey,
      oneTimePrekeyId: bundle.oneTimePrekeyId,
    );
  }

  /// Responder side: the shared secret for a prekey message from
  /// [initiator] whose DIK was already checked against its certificate.
  static Future<Uint8List> respond({
    required LocalDeviceKeys local,
    required X25519KeyPair signedPrekey,
    required X25519KeyPair? oneTimePrekey,
    required List<int> initiatorIdentityKey,
    required List<int> ephemeralKey,
  }) async {
    final dh1 = await signedPrekey.agree(initiatorIdentityKey);
    final dh2 = await local.identityKey.agree(ephemeralKey);
    final dh3 = await signedPrekey.agree(ephemeralKey);
    final dh4 = oneTimePrekey == null
        ? null
        : await oneTimePrekey.agree(ephemeralKey);
    return _sharedSecret(dh1, dh2, dh3, dh4);
  }

  static Uint8List _sharedSecret(
    Uint8List dh1,
    Uint8List dh2,
    Uint8List dh3,
    Uint8List? dh4,
  ) => hkdf(
    ikm: concatBytes([
      Uint8List(32)..fillRange(0, 32, 0xff),
      dh1,
      dh2,
      dh3,
      ?dh4,
    ]),
    salt: zeroSalt,
    info: label(info),
    length: 32,
  );
}

/// The initiator's X3DH output: the shared secret, the session AD, and the
/// fields the prekey message carries.
final class X3dhInitiation {
  const X3dhInitiation._({
    required this.sharedSecret,
    required this.associatedData,
    required this.ephemeralKey,
    required this.signedPrekeyId,
    required this.signedPrekey,
    required this.oneTimePrekeyId,
  });

  final Uint8List sharedSecret;
  final Uint8List associatedData;

  /// EK public key, which also identifies the session (its base key).
  final Uint8List ephemeralKey;
  final int signedPrekeyId;

  /// Bob's SPK, the initial remote ratchet key.
  final Uint8List signedPrekey;
  final int? oneTimePrekeyId;

  @override
  String toString() => 'X3dhInitiation(<redacted>)';
}
