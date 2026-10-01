import 'dart:typed_data';

import 'package:helix_remote_crypto/src/v2/codec.dart';
import 'package:helix_remote_crypto/src/v2/errors.dart';
import 'package:helix_remote_crypto/src/v2/primitives.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Keys and identities (CRYPTO_V2.md §2): the account identity key (AIK,
/// Ed25519), each device's identity key (DIK, X25519) and signing key (DSK,
/// Ed25519), and the AIK certificate that binds a device to its account.

/// The 16 raw bytes of an account's UUID. A federated `uuid@domain` address
/// contributes its UUID only, the same bytes its home server's certificate
/// uses (CRYPTO_V2.md §14).
Uint8List accountIdBytes(String account) {
  final address = AccountAddress.tryParse(account);
  if (address == null) {
    throw ArgumentError.value(account, 'account', 'is not an account address');
  }
  return uuidBytes(address.id);
}

/// One device of one account: the unit a pairwise session belongs to.
final class DeviceAddress implements Comparable<DeviceAddress> {
  DeviceAddress(this.account, this.device) {
    accountIdBytes(account);
    uuidBytes(device);
  }

  /// Account id, or `uuid@domain` for an account on another server.
  final String account;

  /// Device id (UUID).
  final String device;

  Uint8List get accountBytes => accountIdBytes(account);

  Uint8List get deviceBytes => uuidBytes(device);

  JsonMap toJson() => {'account': account, 'device': device};

  factory DeviceAddress.fromJson(JsonReader json) =>
      DeviceAddress(json.nonEmpty('account'), json.nonEmpty('device'));

  @override
  bool operator ==(Object other) =>
      other is DeviceAddress &&
      other.account == account &&
      other.device == device;

  @override
  int get hashCode => Object.hash(account, device);

  @override
  int compareTo(DeviceAddress other) {
    final a = account.compareTo(other.account);
    return a != 0 ? a : device.compareTo(other.device);
  }

  @override
  String toString() => '$account/$device';
}

/// Signing and checking device certificates (CRYPTO_V2.md §2).
abstract final class DeviceCertificates {
  /// `Ed25519.sign(AIK, cert_body)`.
  static Future<DeviceCertificate> issue({
    required Ed25519KeyPair accountIdentityKey,
    required DeviceAddress device,
    required List<int> identityKey,
    required List<int> signingKey,
    required DateTime createdAt,
  }) async {
    final at = _millis(createdAt);
    final body = deviceCertificateBody(
      accountId: AccountAddress.tryParse(device.account)!.id,
      deviceId: device.device,
      identityKey: identityKey,
      signingKey: signingKey,
      createdAt: at,
    );
    return DeviceCertificate(
      createdAt: at,
      signature: await accountIdentityKey.sign(body),
    );
  }

  static Future<bool> isValid({
    required List<int> accountIdentityKey,
    required DeviceAddress device,
    required List<int> identityKey,
    required List<int> signingKey,
    required DeviceCertificate certificate,
  }) async {
    if (identityKey.length != 32 || signingKey.length != 32) return false;
    final body = deviceCertificateBody(
      accountId: AccountAddress.tryParse(device.account)!.id,
      deviceId: device.device,
      identityKey: identityKey,
      signingKey: signingKey,
      createdAt: certificate.createdAt,
    );
    return ed25519Verify(
      publicKey: accountIdentityKey,
      message: body,
      signature: certificate.signature,
    );
  }

  static DateTime _millis(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
    t.millisecondsSinceEpoch,
    isUtc: true,
  );
}

/// The public identity of a device: what a peer needs to talk to it and to
/// check that it belongs to its account.
final class DeviceIdentity {
  const DeviceIdentity({
    required this.address,
    required this.accountIdentityKey,
    required this.identityKey,
    required this.signingKey,
    required this.certificate,
  });

  final DeviceAddress address;

  /// AIK (Ed25519 public) the certificate is checked under.
  final Uint8List accountIdentityKey;

  /// DIK (X25519 public).
  final Uint8List identityKey;

  /// DSK (Ed25519 public).
  final Uint8List signingKey;
  final DeviceCertificate certificate;

  Future<bool> isCertified() => DeviceCertificates.isValid(
    accountIdentityKey: accountIdentityKey,
    device: address,
    identityKey: identityKey,
    signingKey: signingKey,
    certificate: certificate,
  );

  /// Throws [UntrustedIdentityException] unless the AIK certifies this device.
  Future<DeviceIdentity> requireCertified() async {
    if (accountIdentityKey.length != 32 || !await isCertified()) {
      throw UntrustedIdentityException(
        'device $address is not certified by its account key',
      );
    }
    return this;
  }

  JsonMap toJson() => {
    'v': 1,
    'address': address.toJson(),
    'aik': encodeBytes(accountIdentityKey),
    'dik': encodeBytes(identityKey),
    'dsk': encodeBytes(signingKey),
    'cert': certificate.toJson(),
  };

  factory DeviceIdentity.fromJson(JsonReader json) =>
      readState('device identity', () {
        requireVersion(json, 1, 'device identity');
        return DeviceIdentity(
          address: DeviceAddress.fromJson(json.object('address')),
          accountIdentityKey: json.bytes('aik'),
          identityKey: json.bytes('dik'),
          signingKey: json.bytes('dsk'),
          certificate: DeviceCertificate.fromJson(json.object('cert')),
        );
      });
}

/// This device's long-term keys. Private: stored only in the local
/// encrypted database, never backed up (CRYPTO_V2.md §13).
final class LocalDeviceKeys {
  const LocalDeviceKeys({
    required this.address,
    required this.accountIdentityKey,
    required this.identityKey,
    required this.signingKey,
    required this.certificate,
  });

  /// Creates a device's DIK and DSK and certifies them with the AIK.
  static Future<LocalDeviceKeys> create({
    required Ed25519KeyPair accountIdentityKey,
    required DeviceAddress address,
    required DateTime createdAt,
    required CryptoRandom random,
  }) async {
    final dik = await X25519KeyPair.generate(random);
    final dsk = await Ed25519KeyPair.generate(random);
    final certificate = await DeviceCertificates.issue(
      accountIdentityKey: accountIdentityKey,
      device: address,
      identityKey: dik.publicKey,
      signingKey: dsk.publicKey,
      createdAt: createdAt,
    );
    return LocalDeviceKeys(
      address: address,
      accountIdentityKey: accountIdentityKey.publicKey,
      identityKey: dik,
      signingKey: dsk,
      certificate: certificate,
    );
  }

  final DeviceAddress address;

  /// AIK public key. The AIK private key is held separately (identity
  /// table); a device needs it only to certify devices and to unwrap
  /// history backups.
  final Uint8List accountIdentityKey;
  final X25519KeyPair identityKey;
  final Ed25519KeyPair signingKey;
  final DeviceCertificate certificate;

  DeviceIdentity get identity => DeviceIdentity(
    address: address,
    accountIdentityKey: accountIdentityKey,
    identityKey: identityKey.publicKey,
    signingKey: signingKey.publicKey,
    certificate: certificate,
  );

  /// The `DeviceRegistration` for registration and device adding: keys,
  /// certificate and a DSK proof of possession over the certificate body.
  Future<DeviceRegistration> registration({
    required String name,
    required DevicePlatform platform,
  }) async {
    final body = deviceCertificateBody(
      accountId: AccountAddress.tryParse(address.account)!.id,
      deviceId: address.device,
      identityKey: identityKey.publicKey,
      signingKey: signingKey.publicKey,
      createdAt: certificate.createdAt,
    );
    return DeviceRegistration(
      deviceId: address.device,
      name: name,
      platform: platform,
      identityKey: identityKey.publicKey,
      signingKey: signingKey.publicKey,
      certificate: certificate,
      proof: await signingKey.sign(body),
    );
  }

  /// DSK signature answering a device sign-in challenge.
  Future<Uint8List> signInSignature(List<int> challenge) =>
      signingKey.sign(signInSignatureBody(challenge));

  JsonMap toJson() => {
    'v': 1,
    'address': address.toJson(),
    'aik': encodeBytes(accountIdentityKey),
    'dik_priv': encodeBytes(identityKey.privateKey),
    'dik': encodeBytes(identityKey.publicKey),
    'dsk_seed': encodeBytes(signingKey.seed),
    'dsk': encodeBytes(signingKey.publicKey),
    'cert': certificate.toJson(),
  };

  factory LocalDeviceKeys.fromJson(JsonReader json) =>
      readState('local device keys', () {
        requireVersion(json, 1, 'local device keys');
        return LocalDeviceKeys(
          address: DeviceAddress.fromJson(json.object('address')),
          accountIdentityKey: json.bytes('aik'),
          identityKey: X25519KeyPair.restore(
            json.bytes('dik_priv'),
            json.bytes('dik'),
          ),
          signingKey: Ed25519KeyPair.restore(
            json.bytes('dsk_seed'),
            json.bytes('dsk'),
          ),
          certificate: DeviceCertificate.fromJson(json.object('cert')),
        );
      });

  Uint8List encode() => encodeStateJson(toJson());

  static LocalDeviceKeys decode(List<int> bytes) => LocalDeviceKeys.fromJson(
    decodeStateJson(bytes, what: 'local device keys'),
  );

  @override
  String toString() => 'LocalDeviceKeys($address, <redacted>)';
}

/// What the first-seen AIK of an account says about a newly presented one
/// (trust on first use, CRYPTO_V2.md §2).
enum AikPinResult {
  /// Nothing pinned yet: pin the presented key.
  firstUse,

  /// The pinned key.
  matches,

  /// A different key: a key change. Stop using old sessions, show "Safety
  /// number changed", reset the verified flag, then pin the new key.
  changed,
}

AikPinResult checkAikPin({
  required List<int>? pinned,
  required List<int> presented,
}) {
  if (pinned == null) return AikPinResult.firstUse;
  return bytesEqual(pinned, presented)
      ? AikPinResult.matches
      : AikPinResult.changed;
}

/// A device's prekey bundle whose certificate (under the account's AIK) and
/// SPK signature (under the device's DSK) both verified.
final class VerifiedPrekeyBundle {
  const VerifiedPrekeyBundle._({
    required this.identity,
    required this.signedPrekeyId,
    required this.signedPrekey,
    this.oneTimePrekeyId,
    this.oneTimePrekey,
  });

  final DeviceIdentity identity;
  final int signedPrekeyId;
  final Uint8List signedPrekey;
  final int? oneTimePrekeyId;
  final Uint8List? oneTimePrekey;

  /// Verifies the certificate first, then the SPK signature. Throws
  /// [UntrustedIdentityException] or [InvalidSignatureException]; never
  /// returns an unverified bundle.
  static Future<VerifiedPrekeyBundle> verify({
    required String account,
    required List<int> accountIdentityKey,
    required DeviceBundle bundle,
  }) async {
    final DeviceAddress address;
    try {
      address = DeviceAddress(account, bundle.deviceId);
    } on ArgumentError {
      throw const MalformedCryptoInputException('bundle device id');
    }
    if (bundle.identityKey.length != 32 ||
        bundle.signingKey.length != 32 ||
        bundle.signedPrekey.publicKey.length != 32 ||
        (bundle.oneTimePrekey != null &&
            bundle.oneTimePrekey!.publicKey.length != 32)) {
      throw const MalformedCryptoInputException('bundle key lengths');
    }
    if (!isU32(bundle.signedPrekey.id) ||
        (bundle.oneTimePrekey != null && !isU32(bundle.oneTimePrekey!.id))) {
      throw const MalformedCryptoInputException('bundle prekey ids');
    }
    final identity = await DeviceIdentity(
      address: address,
      accountIdentityKey: copyBytes(accountIdentityKey),
      identityKey: bundle.identityKey,
      signingKey: bundle.signingKey,
      certificate: bundle.certificate,
    ).requireCertified();
    await requireSignature(
      publicKey: bundle.signingKey,
      message: signedPrekeySignatureBody(
        bundle.signedPrekey.id,
        bundle.signedPrekey.publicKey,
      ),
      signature: bundle.signedPrekey.signature,
      what: 'signed prekey of $address',
    );
    return VerifiedPrekeyBundle._(
      identity: identity,
      signedPrekeyId: bundle.signedPrekey.id,
      signedPrekey: bundle.signedPrekey.publicKey,
      oneTimePrekeyId: bundle.oneTimePrekey?.id,
      oneTimePrekey: bundle.oneTimePrekey?.publicKey,
    );
  }
}

/// `GET /v1/keys/{account}` after verification.
final class VerifiedAccountKeys {
  const VerifiedAccountKeys._({
    required this.account,
    required this.accountIdentityKey,
    required this.pin,
    required this.devices,
  });

  final String account;
  final Uint8List accountIdentityKey;

  /// How the presented AIK compares with the pinned one. The caller decides
  /// what a [AikPinResult.changed] means for the UI; the bundles themselves
  /// verified under the presented AIK.
  final AikPinResult pin;
  final List<VerifiedPrekeyBundle> devices;

  /// Verifies every device bundle. One bad bundle fails the whole response:
  /// the server requires messages to address every device, so an
  /// unverifiable device cannot be skipped silently.
  static Future<VerifiedAccountKeys> verify({
    required String account,
    required AccountKeys keys,
    List<int>? pinnedAccountIdentityKey,
  }) async {
    final requested = AccountAddress.tryParse(account);
    final answered = AccountAddress.tryParse(keys.account);
    if (requested == null || answered == null || requested.id != answered.id) {
      throw const UntrustedIdentityException('keys are for another account');
    }
    if (keys.identityKey.length != 32) {
      throw const MalformedCryptoInputException('AIK must be 32 bytes');
    }
    final devices = [
      for (final bundle in keys.devices)
        await VerifiedPrekeyBundle.verify(
          account: account,
          accountIdentityKey: keys.identityKey,
          bundle: bundle,
        ),
    ];
    return VerifiedAccountKeys._(
      account: account,
      accountIdentityKey: keys.identityKey,
      pin: checkAikPin(
        pinned: pinnedAccountIdentityKey,
        presented: keys.identityKey,
      ),
      devices: devices,
    );
  }
}
