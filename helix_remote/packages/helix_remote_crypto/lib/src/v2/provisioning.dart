import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_crypto/src/v2/errors.dart';
import 'package:helix_remote_crypto/src/v2/primitives.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Device linking (CRYPTO_V2.md §2a): the provisioning message a signed-in
/// device seals to a new device's ephemeral key.
///
/// ```
/// k      = HKDF(X25519(E_old, E_new.pub), salt = 0x00*32,
///               info = "helix.v2.provision", len = 44)   -> key, nonce
/// sealed = E_old.pub(32) ‖ AES-256-GCM(key, nonce, provision_json,
///                                      aad = "helix.v2.provision" ‖ link_id(16))
/// ```

/// The QR code a new device shows:
/// `helix-link:1:<server origin>:<link_id>:<b64url(E_new.pub)>`.
final class LinkCode {
  LinkCode({
    required this.serverOrigin,
    required this.linkId,
    required List<int> ephemeralKey,
  }) : ephemeralKey = copyBytes(ephemeralKey) {
    requireLength(ephemeralKey, 32, 'link ephemeral key');
    if (!Uuid.isValid(linkId)) {
      throw const MalformedCryptoInputException('link id');
    }
    if (!_isOrigin(serverOrigin)) {
      throw const MalformedCryptoInputException('link server origin');
    }
  }

  static const prefix = 'helix-link:1:';

  /// `https://host[:port]`, no path.
  final String serverOrigin;
  final String linkId;
  final Uint8List ephemeralKey;

  String encode() =>
      '$prefix$serverOrigin:$linkId:${encodeBytes(ephemeralKey)}';

  /// Parses from the right, since the origin itself contains colons.
  static LinkCode parse(String text) {
    if (!text.startsWith(prefix)) {
      throw const MalformedCryptoInputException('not a Helix link code');
    }
    final rest = text.substring(prefix.length);
    final keyAt = rest.lastIndexOf(':');
    final idAt = keyAt <= 0 ? -1 : rest.lastIndexOf(':', keyAt - 1);
    if (idAt <= 0) {
      throw const MalformedCryptoInputException('malformed link code');
    }
    final Uint8List key;
    try {
      key = decodeBytes(rest.substring(keyAt + 1));
    } on FormatException {
      throw const MalformedCryptoInputException('link code key');
    }
    return LinkCode(
      serverOrigin: rest.substring(0, idAt),
      linkId: rest.substring(idAt + 1, keyAt),
      ephemeralKey: key,
    );
  }

  static bool _isOrigin(String origin) {
    final uri = Uri.tryParse(origin);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        (uri.path.isEmpty) &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        uri.userInfo.isEmpty;
  }
}

/// What the approving device gives the new one: the account and its AIK.
final class ProvisionMessage {
  const ProvisionMessage({
    required this.accountId,
    required this.identityKeySeed,
    required this.identityKey,
    required this.profileKey,
    required this.approverDeviceId,
  });

  final String accountId;

  /// AIK private seed (32 bytes).
  final Uint8List identityKeySeed;

  /// AIK public key.
  final Uint8List identityKey;
  final Uint8List profileKey;
  final String approverDeviceId;

  JsonMap toJson() => {
    'account_id': accountId,
    'identity_key_private': encodeBytes(identityKeySeed),
    'identity_key': encodeBytes(identityKey),
    'profile_key': encodeBytes(profileKey),
    'approver_device_id': approverDeviceId,
  };

  factory ProvisionMessage.fromJson(JsonReader json) => ProvisionMessage(
    accountId: json.nonEmpty('account_id'),
    identityKeySeed: json.bytes('identity_key_private'),
    identityKey: json.bytes('identity_key'),
    profileKey: json.bytes('profile_key'),
    approverDeviceId: json.nonEmpty('approver_device_id'),
  );

  @override
  String toString() => 'ProvisionMessage($accountId, <redacted>)';
}

abstract final class Provisioning {
  static const info = 'helix.v2.provision';

  static Uint8List associatedData(String linkId) =>
      concatBytes([label(info), uuidBytes(linkId)]);

  /// Approving side: seals [message] to the new device's [linkCode].
  static Future<Uint8List> seal({
    required LinkCode linkCode,
    required ProvisionMessage message,
    required CryptoRandom random,
  }) async {
    final ephemeral = await X25519KeyPair.generate(random);
    final shared = await ephemeral.agree(linkCode.ephemeralKey);
    final ciphertext = await AeadKey.derive(shared, info).seal(
      utf8.encode(jsonEncode(message.toJson())),
      aad: associatedData(linkCode.linkId),
    );
    return concatBytes([ephemeral.publicKey, ciphertext]);
  }

  /// New device: opens the provisioning message with its ephemeral key and
  /// checks that the AIK seed matches the AIK public key it claims.
  static Future<ProvisionMessage> open({
    required X25519KeyPair ephemeralKey,
    required String linkId,
    required List<int> sealed,
  }) async {
    if (sealed.length < 32 + Aead.tagLength) {
      throw const MalformedCryptoInputException('provisioning message');
    }
    final shared = await ephemeralKey.agree(sealed.sublist(0, 32));
    final plain = await AeadKey.derive(
      shared,
      info,
    ).open(sealed.sublist(32), aad: associatedData(linkId));
    final ProvisionMessage message;
    try {
      message = ProvisionMessage.fromJson(
        JsonReader.decode(utf8.decode(plain)),
      );
    } on FormatException {
      throw const MalformedCryptoInputException('provisioning content');
    }
    if (message.identityKeySeed.length != 32 ||
        message.profileKey.length != 32) {
      throw const MalformedCryptoInputException('provisioning key lengths');
    }
    final derived = await Ed25519KeyPair.fromSeed(message.identityKeySeed);
    if (!bytesEqual(derived.publicKey, message.identityKey)) {
      throw const UntrustedIdentityException(
        'provisioned identity key does not match its seed',
      );
    }
    return message;
  }
}
