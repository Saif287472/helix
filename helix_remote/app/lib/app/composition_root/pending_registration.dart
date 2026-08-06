part of '../composition_root.dart';

class _PendingRegistration {
  const _PendingRegistration({
    required this.phoneNumber,
    required this.phoneHash,
    required this.displayName,
    required this.accountId,
    required this.deviceId,
    required this.deviceName,
    required this.identityKeyPair,
    required this.deviceSigningKeyPair,
    required this.deviceAgreementKeyPair,
    required this.accountIdentityPublicKey,
    required this.identityPrivateKey,
    required this.deviceSigningPublicKey,
    required this.deviceSigningPrivateKey,
    required this.deviceAgreementPublicKey,
    required this.deviceAgreementPrivateKey,
    required this.accountRegistrationSignature,
    required this.deviceRegistrationSignature,
  });

  final String phoneNumber;
  final String phoneHash;
  final String displayName;
  final String accountId;
  final String deviceId;
  final String deviceName;
  final crypto_pkg.SimpleKeyPair identityKeyPair;
  final crypto_pkg.SimpleKeyPair deviceSigningKeyPair;
  final crypto_pkg.SimpleKeyPair deviceAgreementKeyPair;
  final String accountIdentityPublicKey;
  final String identityPrivateKey;
  final String deviceSigningPublicKey;
  final String deviceSigningPrivateKey;
  final String deviceAgreementPublicKey;
  final String deviceAgreementPrivateKey;
  final String accountRegistrationSignature;
  final String deviceRegistrationSignature;

  Uint8List get deviceAgreementPrivateBytes =>
      _base64UrlDecode(deviceAgreementPrivateKey);

  Uint8List get deviceAgreementPublicBytes =>
      _base64UrlDecode(deviceAgreementPublicKey);

  static Future<_PendingRegistration> create({
    required String phoneNumber,
    required String phoneHash,
    required String displayName,
  }) async {
    final ed25519 = crypto_pkg.Ed25519();
    final identityKeyPair = await ed25519.newKeyPair();
    final identityPubKey = await identityKeyPair.extractPublicKey();

    final deviceSigningKeyPair = await ed25519.newKeyPair();
    final deviceSigningPubKey = await deviceSigningKeyPair.extractPublicKey();

    final x25519 = crypto_pkg.X25519();
    final deviceAgreementKeyPair = await x25519.newKeyPair();
    final deviceAgreementPubKey = await deviceAgreementKeyPair
        .extractPublicKey();

    final accountId = _bytesToHex(identityPubKey.bytes.sublist(0, 8));
    final deviceId =
        'dev_${_bytesToHex(deviceSigningPubKey.bytes.sublist(0, 4))}';
    final deviceName = 'Dev ${deviceId.substring(0, 8)}';

    final accountIdentityPublicKey = _base64Url(identityPubKey.bytes);
    final identityPrivateKey = _base64Url(
      await identityKeyPair.extractPrivateKeyBytes(),
    );
    final deviceSigningPublicKey = _base64Url(deviceSigningPubKey.bytes);
    final deviceSigningPrivateKey = _base64Url(
      await deviceSigningKeyPair.extractPrivateKeyBytes(),
    );
    final deviceAgreementPublicKey = _base64Url(deviceAgreementPubKey.bytes);
    final deviceAgreementPrivateKey = _base64Url(
      await deviceAgreementKeyPair.extractPrivateKeyBytes(),
    );

    final transcript = _registrationTranscript(
      accountId: accountId,
      phoneHash: phoneHash,
      accountIdentityPublicKey: accountIdentityPublicKey,
      deviceId: deviceId,
      deviceSigningPublicKey: deviceSigningPublicKey,
      deviceAgreementPublicKey: deviceAgreementPublicKey,
      deviceName: deviceName,
    );
    final accountSignature = await ed25519.sign(
      utf8.encode(transcript),
      keyPair: identityKeyPair,
    );
    final deviceSignature = await ed25519.sign(
      utf8.encode(transcript),
      keyPair: deviceSigningKeyPair,
    );

    return _PendingRegistration(
      phoneNumber: phoneNumber,
      phoneHash: phoneHash,
      displayName: displayName,
      accountId: accountId,
      deviceId: deviceId,
      deviceName: deviceName,
      identityKeyPair: identityKeyPair,
      deviceSigningKeyPair: deviceSigningKeyPair,
      deviceAgreementKeyPair: deviceAgreementKeyPair,
      accountIdentityPublicKey: accountIdentityPublicKey,
      identityPrivateKey: identityPrivateKey,
      deviceSigningPublicKey: deviceSigningPublicKey,
      deviceSigningPrivateKey: deviceSigningPrivateKey,
      deviceAgreementPublicKey: deviceAgreementPublicKey,
      deviceAgreementPrivateKey: deviceAgreementPrivateKey,
      accountRegistrationSignature: _base64Url(accountSignature.bytes),
      deviceRegistrationSignature: _base64Url(deviceSignature.bytes),
    );
  }

  factory _PendingRegistration.fromJson(Map<String, dynamic> json) {
    final accountIdentityPublicKey = _requireString(
      json,
      'account_identity_public_key',
    );
    final identityPrivateKey = _requireString(json, 'identity_private_key');
    final deviceSigningPublicKey = _requireString(
      json,
      'device_signing_public_key',
    );
    final deviceSigningPrivateKey = _requireString(
      json,
      'device_signing_private_key',
    );
    final deviceAgreementPublicKey = _requireString(
      json,
      'device_agreement_public_key',
    );
    final deviceAgreementPrivateKey = _requireString(
      json,
      'device_agreement_private_key',
    );

    return _PendingRegistration(
      phoneNumber: _requireString(json, 'phone_number'),
      phoneHash: _requireString(json, 'phone_hash'),
      displayName: _requireString(json, 'display_name'),
      accountId: _requireString(json, 'account_id'),
      deviceId: _requireString(json, 'device_id'),
      deviceName: _requireString(json, 'device_name'),
      identityKeyPair: _keyPair(
        privateKey: identityPrivateKey,
        publicKey: accountIdentityPublicKey,
        type: crypto_pkg.KeyPairType.ed25519,
      ),
      deviceSigningKeyPair: _keyPair(
        privateKey: deviceSigningPrivateKey,
        publicKey: deviceSigningPublicKey,
        type: crypto_pkg.KeyPairType.ed25519,
      ),
      deviceAgreementKeyPair: _keyPair(
        privateKey: deviceAgreementPrivateKey,
        publicKey: deviceAgreementPublicKey,
        type: crypto_pkg.KeyPairType.x25519,
      ),
      accountIdentityPublicKey: accountIdentityPublicKey,
      identityPrivateKey: identityPrivateKey,
      deviceSigningPublicKey: deviceSigningPublicKey,
      deviceSigningPrivateKey: deviceSigningPrivateKey,
      deviceAgreementPublicKey: deviceAgreementPublicKey,
      deviceAgreementPrivateKey: deviceAgreementPrivateKey,
      accountRegistrationSignature: _requireString(
        json,
        'account_registration_signature',
      ),
      deviceRegistrationSignature: _requireString(
        json,
        'device_registration_signature',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'phone_number': phoneNumber,
    'phone_hash': phoneHash,
    'display_name': displayName,
    'account_id': accountId,
    'device_id': deviceId,
    'device_name': deviceName,
    'account_identity_public_key': accountIdentityPublicKey,
    'identity_private_key': identityPrivateKey,
    'device_signing_public_key': deviceSigningPublicKey,
    'device_signing_private_key': deviceSigningPrivateKey,
    'device_agreement_public_key': deviceAgreementPublicKey,
    'device_agreement_private_key': deviceAgreementPrivateKey,
    'account_registration_signature': accountRegistrationSignature,
    'device_registration_signature': deviceRegistrationSignature,
  };

  static crypto_pkg.SimpleKeyPairData _keyPair({
    required String privateKey,
    required String publicKey,
    required crypto_pkg.KeyPairType type,
  }) {
    return crypto_pkg.SimpleKeyPairData(
      _base64UrlDecode(privateKey),
      publicKey: crypto_pkg.SimplePublicKey(
        _base64UrlDecode(publicKey),
        type: type,
      ),
      type: type,
    );
  }

  static String _requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('Missing pending registration field: $key');
    }
    return value;
  }
}
