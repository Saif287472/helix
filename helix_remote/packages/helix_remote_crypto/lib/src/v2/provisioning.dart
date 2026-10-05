import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_crypto/src/v2/errors.dart';
import 'package:helix_remote_crypto/src/v2/identity.dart';
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

/// What the approving device gives the new one: the account and its AIK, and
/// the proof that an approver of that account made this approval for this
/// link (CRYPTO_V2.md §2a).
///
/// The approver signs `link_id ‖ E_new ‖ account ‖ AIK` with its device
/// signing key and attaches its certificate. The new device checks that the
/// certificate is valid under the AIK it is handed, that the account id is
/// the approver's, and that the signature is over *this* link and *this*
/// ephemeral key: a provisioning message cannot be lifted from another link,
/// and an account id cannot be paired with an AIK that does not certify an
/// approver. What it cannot prove is that this is the account the user means
/// (anyone can approve a link they saw with an account of their own), which
/// is why the engine shows the account and asks before keeping anything.
final class ProvisionMessage {
  const ProvisionMessage({
    required this.accountId,
    required this.identityKeySeed,
    required this.identityKey,
    required this.profileKey,
    required this.approver,
    required this.approval,
    this.phoneMask,
    this.helixName,
  });

  final String accountId;

  /// AIK private seed (32 bytes).
  final Uint8List identityKeySeed;

  /// AIK public key.
  final Uint8List identityKey;
  final Uint8List profileKey;

  /// The approving device, with its certificate under [identityKey].
  final DeviceIdentity approver;

  /// The approver's DSK signature over [Provisioning.approvalBody].
  final Uint8List approval;

  /// The account's phone number, masked (`+88017*****01`), and its
  /// `~Helix name`: claims of the approver, for the new device's user to
  /// compare with the account they expect. Not authenticated by anything but
  /// the approver.
  final String? phoneMask;
  final String? helixName;

  String get approverDeviceId => approver.address.device;

  JsonMap toJson() => compact({
    'account_id': accountId,
    'identity_key_private': encodeBytes(identityKeySeed),
    'identity_key': encodeBytes(identityKey),
    'profile_key': encodeBytes(profileKey),
    'approver': approver.toJson(),
    'approval': encodeBytes(approval),
    'phone_mask': phoneMask,
    'helix_name': helixName,
  });

  factory ProvisionMessage.fromJson(JsonReader json) => ProvisionMessage(
    accountId: json.nonEmpty('account_id'),
    identityKeySeed: json.bytes('identity_key_private'),
    identityKey: json.bytes('identity_key'),
    profileKey: json.bytes('profile_key'),
    approver: DeviceIdentity.fromJson(json.object('approver')),
    approval: json.bytes('approval'),
    phoneMask: json.optString('phone_mask'),
    helixName: json.optString('helix_name'),
  );

  @override
  String toString() => 'ProvisionMessage($accountId, <redacted>)';
}

abstract final class Provisioning {
  static const info = 'helix.v2.provision';

  static Uint8List associatedData(String linkId) =>
      concatBytes([label(info), uuidBytes(linkId)]);

  /// What the approver's DSK signs:
  /// `"helix.v2.provision-approval" ‖ link_id(16) ‖ E_new(32) ‖ account(16)
  /// ‖ AIK(32)`.
  static Uint8List approvalBody({
    required String linkId,
    required List<int> ephemeralKey,
    required String accountId,
    required List<int> identityKey,
  }) => concatBytes([
    label('helix.v2.provision-approval'),
    uuidBytes(linkId),
    ephemeralKey,
    accountIdBytes(accountId),
    identityKey,
  ]);

  /// A short form of an AIK for the new device's user to compare (and for the
  /// UI to show): 20 hex digits of `SHA-256("helix.v2.aik-fingerprint" ‖
  /// AIK)` in groups of four.
  static String keyCode(List<int> identityKey) {
    final digest = sha256(
      concatBytes([label('helix.v2.aik-fingerprint'), identityKey]),
    );
    final hex = [
      for (final b in digest.sublist(0, 10))
        b.toRadixString(16).padLeft(2, '0'),
    ].join();
    return [
      for (var i = 0; i < hex.length; i += 4) hex.substring(i, i + 4),
    ].join(' ');
  }

  /// Approving side: seals the account's identity key and profile key to the
  /// new device's [linkCode], signed as [approver] (a device of the account,
  /// holding [accountKey]).
  static Future<Uint8List> seal({
    required LinkCode linkCode,
    required LocalDeviceKeys approver,
    required Ed25519KeyPair accountKey,
    required List<int> profileKey,
    required CryptoRandom random,
    String? phoneMask,
    String? helixName,
  }) async {
    final message = ProvisionMessage(
      accountId: approver.address.account,
      identityKeySeed: accountKey.seed,
      identityKey: accountKey.publicKey,
      profileKey: copyBytes(profileKey),
      approver: approver.identity,
      approval: await approver.signingKey.sign(
        approvalBody(
          linkId: linkCode.linkId,
          ephemeralKey: linkCode.ephemeralKey,
          accountId: approver.address.account,
          identityKey: accountKey.publicKey,
        ),
      ),
      phoneMask: phoneMask,
      helixName: helixName,
    );
    final ephemeral = await X25519KeyPair.generate(random);
    final shared = await ephemeral.agree(linkCode.ephemeralKey);
    final ciphertext = await AeadKey.derive(shared, info).seal(
      utf8.encode(jsonEncode(message.toJson())),
      aad: associatedData(linkCode.linkId),
    );
    return concatBytes([ephemeral.publicKey, ciphertext]);
  }

  /// New device: opens the provisioning message with its ephemeral key and
  /// checks that the AIK seed matches the AIK public key it claims, that the
  /// approver is certified by that AIK as a device of the account, and that
  /// the approver signed *this* link and ephemeral key. Throws
  /// [UntrustedIdentityException] otherwise.
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
        message.identityKey.length != 32 ||
        message.profileKey.length != 32) {
      throw const MalformedCryptoInputException('provisioning key lengths');
    }
    final derived = await Ed25519KeyPair.fromSeed(message.identityKeySeed);
    if (!bytesEqual(derived.publicKey, message.identityKey)) {
      throw const UntrustedIdentityException(
        'provisioned identity key does not match its seed',
      );
    }
    final approver = message.approver;
    if (approver.address.account != message.accountId ||
        !bytesEqual(approver.accountIdentityKey, message.identityKey)) {
      throw const UntrustedIdentityException(
        'the approver does not belong to the provisioned account',
      );
    }
    await approver.requireCertified();
    final signedBody = approvalBody(
      linkId: linkId,
      ephemeralKey: ephemeralKey.publicKey,
      accountId: message.accountId,
      identityKey: message.identityKey,
    );
    if (!await ed25519Verify(
      publicKey: approver.signingKey,
      message: signedBody,
      signature: message.approval,
    )) {
      throw const UntrustedIdentityException(
        'the approval was not made for this link',
      );
    }
    return message;
  }
}
