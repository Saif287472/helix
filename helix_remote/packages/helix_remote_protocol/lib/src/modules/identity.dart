import 'dart:typed_data';

import 'package:helix_remote_protocol/src/json.dart';
import 'package:helix_remote_protocol/src/modules/keys.dart';

// ------------------------------------------------------------------ shared

/// Argon2id parameters for password derivation (CRYPTO_V2.md §11).
final class KdfParams {
  const KdfParams({
    this.memoryKib = defaultMemoryKib,
    this.iterations = defaultIterations,
    this.parallelism = defaultParallelism,
    this.length = outputLength,
  });

  static const algorithm = 'argon2id';
  static const defaultMemoryKib = 19456;
  static const defaultIterations = 2;
  static const defaultParallelism = 1;
  static const outputLength = 64;

  final int memoryKib;
  final int iterations;
  final int parallelism;
  final int length;

  /// The ranges the server accepts (weaker parameters are refused).
  bool get isAcceptable =>
      memoryKib >= defaultMemoryKib &&
      memoryKib <= 262144 &&
      iterations >= 1 &&
      iterations <= 10 &&
      parallelism >= 1 &&
      parallelism <= 4 &&
      length == outputLength;

  JsonMap toJson() => {
    'alg': algorithm,
    'memory_kib': memoryKib,
    'iterations': iterations,
    'parallelism': parallelism,
    'length': length,
  };

  factory KdfParams.fromJson(JsonReader json) {
    if (json.string('alg') != algorithm) {
      throw ProtocolFormatException(
        'unsupported KDF',
        path: '${json.path}.alg',
      );
    }
    return KdfParams(
      memoryKib: json.integer('memory_kib'),
      iterations: json.integer('iterations'),
      parallelism: json.integer('parallelism'),
      length: json.integer('length'),
    );
  }
}

/// Everything the server stores for password sign-in. The password itself
/// never leaves the device.
final class PasswordSetup {
  const PasswordSetup({
    required this.kdf,
    required this.salt,
    required this.authKey,
    required this.wrappedIdentityKey,
  });

  final KdfParams kdf;

  /// 16-64 random bytes chosen by the client.
  final Uint8List salt;

  /// `HKDF(argon2id(password), "helix.v2.password.auth")`, 32 bytes.
  final Uint8List authKey;

  /// The AIK private key sealed with the password wrap key.
  final WrappedKey wrappedIdentityKey;

  JsonMap toJson() => {
    'kdf': kdf.toJson(),
    'salt': encodeBytes(salt),
    'auth_key': encodeBytes(authKey),
    'wrapped_identity_key': wrappedIdentityKey.toJson(),
  };

  factory PasswordSetup.fromJson(JsonReader json) => PasswordSetup(
    kdf: KdfParams.fromJson(json.object('kdf')),
    salt: json.bytes('salt'),
    authKey: json.bytes('auth_key'),
    wrappedIdentityKey: WrappedKey.fromJson(
      json.object('wrapped_identity_key'),
    ),
  );
}

/// AES-256-GCM sealed key material: `ciphertext` includes the 16-byte tag.
final class WrappedKey {
  const WrappedKey({required this.nonce, required this.ciphertext});

  final Uint8List nonce;
  final Uint8List ciphertext;

  JsonMap toJson() => {
    'nonce': encodeBytes(nonce),
    'ciphertext': encodeBytes(ciphertext),
  };

  factory WrappedKey.fromJson(JsonReader json) => WrappedKey(
    nonce: json.bytes('nonce'),
    ciphertext: json.bytes('ciphertext'),
  );
}

enum DevicePlatform implements WireEnum {
  android('android'),
  windows('windows'),
  ios('ios'),
  macos('macos'),
  linux('linux'),
  cli('cli'),
  other('other');

  const DevicePlatform(this.wire);

  @override
  final String wire;
}

/// A device being added to an account: its keys, its AIK certificate, and
/// proof that it holds the DSK (an Ed25519 signature by the DSK over the same
/// certificate body).
final class DeviceRegistration {
  const DeviceRegistration({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.identityKey,
    required this.signingKey,
    required this.certificate,
    required this.proof,
  });

  static const maxNameLength = 80;

  /// Client-chosen UUIDv7.
  final String deviceId;
  final String name;
  final DevicePlatform platform;

  /// DIK (X25519).
  final Uint8List identityKey;

  /// DSK (Ed25519).
  final Uint8List signingKey;
  final DeviceCertificate certificate;
  final Uint8List proof;

  JsonMap toJson() => {
    'device_id': deviceId,
    'name': name,
    'platform': platform.wire,
    'identity_key': encodeBytes(identityKey),
    'signing_key': encodeBytes(signingKey),
    'certificate': certificate.toJson(),
    'proof': encodeBytes(proof),
  };

  factory DeviceRegistration.fromJson(JsonReader json) => DeviceRegistration(
    deviceId: json.nonEmpty('device_id'),
    name: json.nonEmpty('name'),
    platform: json.enumValue(
      'platform',
      DevicePlatform.values,
      orElse: DevicePlatform.other,
    ),
    identityKey: json.bytes('identity_key'),
    signingKey: json.bytes('signing_key'),
    certificate: DeviceCertificate.fromJson(json.object('certificate')),
    proof: json.bytes('proof'),
  );
}

/// Tokens for a device. Every sign-in path returns this (and the server
/// mints it in exactly one place, ADR-026).
final class Session {
  const Session({
    required this.accountId,
    required this.deviceId,
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
  });

  final String accountId;
  final String deviceId;
  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;
  final DateTime refreshExpiresAt;

  JsonMap toJson() => {
    'account_id': accountId,
    'device_id': deviceId,
    'access_token': accessToken,
    'access_expires_at': toWireTime(accessExpiresAt),
    'refresh_token': refreshToken,
    'refresh_expires_at': toWireTime(refreshExpiresAt),
  };

  factory Session.fromJson(JsonReader json) => Session(
    accountId: json.nonEmpty('account_id'),
    deviceId: json.nonEmpty('device_id'),
    accessToken: json.nonEmpty('access_token'),
    accessExpiresAt: json.time('access_expires_at'),
    refreshToken: json.nonEmpty('refresh_token'),
    refreshExpiresAt: json.time('refresh_expires_at'),
  );

  @override
  String toString() => 'Session($accountId/$deviceId, tokens redacted)';
}

// ------------------------------------------------------------- phone codes

enum PhonePurpose implements WireEnum {
  register('register'),
  signIn('sign_in'),
  resetPassword('reset_password'),
  recover('recover');

  const PhonePurpose(this.wire);

  @override
  final String wire;
}

/// `POST /v1/auth/phone/challenges` (Helix Global). The number is sent over
/// TLS because the server must text it; the server keeps only a keyed hash
/// and the last four digits.
final class PhoneChallengeRequest {
  const PhoneChallengeRequest({
    required this.phoneNumber,
    required this.purpose,
  });

  /// E.164, e.g. `+8801712345678`.
  final String phoneNumber;
  final PhonePurpose purpose;

  JsonMap toJson() => {'phone_number': phoneNumber, 'purpose': purpose.wire};

  factory PhoneChallengeRequest.fromJson(JsonReader json) =>
      PhoneChallengeRequest(
        phoneNumber: json.nonEmpty('phone_number'),
        purpose: json.enumValue('purpose', PhonePurpose.values),
      );

  @override
  String toString() =>
      'PhoneChallengeRequest(${purpose.wire}, number redacted)';
}

final class PhoneChallengeResponse {
  const PhoneChallengeResponse({
    required this.challengeId,
    required this.expiresAt,
    required this.resendAfter,
  });

  final String challengeId;
  final DateTime expiresAt;
  final Duration resendAfter;

  JsonMap toJson() => {
    'challenge_id': challengeId,
    'expires_at': toWireTime(expiresAt),
    'resend_after_s': resendAfter.inSeconds,
  };

  factory PhoneChallengeResponse.fromJson(JsonReader json) =>
      PhoneChallengeResponse(
        challengeId: json.nonEmpty('challenge_id'),
        expiresAt: json.time('expires_at'),
        resendAfter: Duration(seconds: json.integer('resend_after_s')),
      );
}

/// `POST /v1/auth/phone/verify`. Consumes the code and returns a short-lived,
/// single-use token that later requests present instead of the code.
final class PhoneVerifyRequest {
  const PhoneVerifyRequest({required this.challengeId, required this.code});

  final String challengeId;
  final String code;

  JsonMap toJson() => {'challenge_id': challengeId, 'code': code};

  factory PhoneVerifyRequest.fromJson(JsonReader json) => PhoneVerifyRequest(
    challengeId: json.nonEmpty('challenge_id'),
    code: json.nonEmpty('code'),
  );

  @override
  String toString() => 'PhoneVerifyRequest($challengeId, code redacted)';
}

final class PhoneVerifyResponse {
  const PhoneVerifyResponse({
    required this.verificationToken,
    required this.expiresAt,
    required this.accountExists,
    required this.hasPassword,
    this.accountId,
  });

  final String verificationToken;
  final DateTime expiresAt;
  final bool accountExists;
  final bool hasPassword;

  /// The existing account's id, when [accountExists]: the caller has just
  /// proved they hold the number, and needs the id to certify a device for
  /// `RegisterRequest.replaceExisting`.
  final String? accountId;

  JsonMap toJson() => compact({
    'verification_token': verificationToken,
    'expires_at': toWireTime(expiresAt),
    'account_exists': accountExists,
    'has_password': hasPassword,
    'account_id': accountId,
  });

  factory PhoneVerifyResponse.fromJson(JsonReader json) => PhoneVerifyResponse(
    verificationToken: json.nonEmpty('verification_token'),
    expiresAt: json.time('expires_at'),
    accountExists: json.boolean('account_exists'),
    hasPassword: json.boolean('has_password'),
    accountId: json.optString('account_id'),
  );
}

// ----------------------------------------------------------------- invites

final class InviteLookupRequest {
  const InviteLookupRequest({required this.inviteCode});

  final String inviteCode;

  JsonMap toJson() => {'invite_code': inviteCode};

  factory InviteLookupRequest.fromJson(JsonReader json) =>
      InviteLookupRequest(inviteCode: json.nonEmpty('invite_code'));

  @override
  String toString() => 'InviteLookupRequest(code redacted)';
}

enum InviteInvalidReason implements WireEnum {
  notFound('not_found'),
  used('used'),
  cancelled('cancelled'),
  expired('expired'),
  unknown('unknown');

  const InviteInvalidReason(this.wire);

  @override
  final String wire;
}

final class InviteLookupResponse {
  const InviteLookupResponse({
    required this.valid,
    this.reason,
    this.serverName,
  });

  final bool valid;
  final InviteInvalidReason? reason;
  final String? serverName;

  JsonMap toJson() => compact({
    'valid': valid,
    'reason': reason?.wire,
    'server_name': serverName,
  });

  factory InviteLookupResponse.fromJson(JsonReader json) =>
      InviteLookupResponse(
        valid: json.boolean('valid'),
        reason: json.optEnum(
          'reason',
          InviteInvalidReason.values,
          orElse: InviteInvalidReason.unknown,
        ),
        serverName: json.optString('server_name'),
      );
}

final class InviteSelfIssueResponse {
  const InviteSelfIssueResponse({
    required this.inviteCode,
    required this.expiresAt,
  });

  final String inviteCode;
  final DateTime expiresAt;

  JsonMap toJson() => {
    'invite_code': inviteCode,
    'expires_at': toWireTime(expiresAt),
  };

  factory InviteSelfIssueResponse.fromJson(JsonReader json) =>
      InviteSelfIssueResponse(
        inviteCode: json.nonEmpty('invite_code'),
        expiresAt: json.time('expires_at'),
      );
}

// ------------------------------------------------------------ registration

/// `POST /v1/auth/register`. Creates the account and its first device and
/// returns a [Session].
///
/// Helix Global requires [verificationToken] (phone verified). Personal
/// servers require [inviteCode]. If the verified phone already has an
/// account the server answers `account_exists` unless [replaceExisting] is
/// set, in which case the account moves to this device: its AIK becomes
/// [identityKey], every other device is signed out, and contacts receive a
/// `key_change` (the v1 "SMS takeover", now explicit).
final class RegisterRequest {
  const RegisterRequest({
    required this.accountId,
    required this.identityKey,
    required this.device,
    required this.prekeys,
    this.verificationToken,
    this.inviteCode,
    this.password,
    this.termsVersion,
    this.replaceExisting = false,
  });

  /// Client-chosen UUIDv7. Ignored (the existing id is kept) when an
  /// existing account is replaced.
  final String accountId;

  /// AIK public key (Ed25519).
  final Uint8List identityKey;
  final DeviceRegistration device;
  final PrekeyUpload prekeys;
  final String? verificationToken;
  final String? inviteCode;
  final PasswordSetup? password;

  /// The terms version the user accepted (Helix Global).
  final String? termsVersion;
  final bool replaceExisting;

  JsonMap toJson() => compact({
    'account_id': accountId,
    'identity_key': encodeBytes(identityKey),
    'device': device.toJson(),
    'prekeys': prekeys.toJson(),
    'verification_token': verificationToken,
    'invite_code': inviteCode,
    'password': password?.toJson(),
    'terms_version': termsVersion,
    if (replaceExisting) 'replace_existing': true,
  });

  factory RegisterRequest.fromJson(JsonReader json) => RegisterRequest(
    accountId: json.nonEmpty('account_id'),
    identityKey: json.bytes('identity_key'),
    device: DeviceRegistration.fromJson(json.object('device')),
    prekeys: PrekeyUpload.fromJson(json.object('prekeys')),
    verificationToken: json.optString('verification_token'),
    inviteCode: json.optString('invite_code'),
    password: json.has('password')
        ? PasswordSetup.fromJson(json.object('password'))
        : null,
    termsVersion: json.optString('terms_version'),
    replaceExisting: json.flag('replace_existing'),
  );
}

final class RegisterResponse {
  const RegisterResponse({
    required this.session,
    this.replacedExisting = false,
  });

  final Session session;
  final bool replacedExisting;

  JsonMap toJson() => {
    'session': session.toJson(),
    'replaced_existing': replacedExisting,
  };

  factory RegisterResponse.fromJson(JsonReader json) => RegisterResponse(
    session: Session.fromJson(json.object('session')),
    replacedExisting: json.flag('replaced_existing'),
  );
}

// ---------------------------------------------------------------- password

/// `POST /v1/auth/password/params`. For a number without a password the
/// server returns stable, plausible decoy parameters, so this route does not
/// reveal who has an account.
final class PasswordParamsRequest {
  const PasswordParamsRequest({required this.phoneNumber});

  final String phoneNumber;

  JsonMap toJson() => {'phone_number': phoneNumber};

  factory PasswordParamsRequest.fromJson(JsonReader json) =>
      PasswordParamsRequest(phoneNumber: json.nonEmpty('phone_number'));

  @override
  String toString() => 'PasswordParamsRequest(number redacted)';
}

final class PasswordParamsResponse {
  const PasswordParamsResponse({required this.kdf, required this.salt});

  final KdfParams kdf;
  final Uint8List salt;

  JsonMap toJson() => {'kdf': kdf.toJson(), 'salt': encodeBytes(salt)};

  factory PasswordParamsResponse.fromJson(JsonReader json) =>
      PasswordParamsResponse(
        kdf: KdfParams.fromJson(json.object('kdf')),
        salt: json.bytes('salt'),
      );
}

/// `POST /v1/auth/password/sign-in`, step one of password sign-in: proves
/// the password and returns the wrapped AIK plus a short-lived
/// [PasswordSignInResponse.signInToken]. Step two is [AddDeviceRequest],
/// once the client has unwrapped the AIK and certified its new device.
final class PasswordSignInRequest {
  const PasswordSignInRequest({
    required this.phoneNumber,
    required this.authKey,
  });

  final String phoneNumber;
  final Uint8List authKey;

  JsonMap toJson() => {
    'phone_number': phoneNumber,
    'auth_key': encodeBytes(authKey),
  };

  factory PasswordSignInRequest.fromJson(JsonReader json) =>
      PasswordSignInRequest(
        phoneNumber: json.nonEmpty('phone_number'),
        authKey: json.bytes('auth_key'),
      );

  @override
  String toString() => 'PasswordSignInRequest(redacted)';
}

final class PasswordSignInResponse {
  const PasswordSignInResponse({
    required this.accountId,
    required this.identityKey,
    required this.wrappedIdentityKey,
    required this.signInToken,
    required this.expiresAt,
  });

  final String accountId;
  final Uint8List identityKey;
  final WrappedKey wrappedIdentityKey;
  final String signInToken;
  final DateTime expiresAt;

  JsonMap toJson() => {
    'account_id': accountId,
    'identity_key': encodeBytes(identityKey),
    'wrapped_identity_key': wrappedIdentityKey.toJson(),
    'sign_in_token': signInToken,
    'expires_at': toWireTime(expiresAt),
  };

  factory PasswordSignInResponse.fromJson(JsonReader json) =>
      PasswordSignInResponse(
        accountId: json.nonEmpty('account_id'),
        identityKey: json.bytes('identity_key'),
        wrappedIdentityKey: WrappedKey.fromJson(
          json.object('wrapped_identity_key'),
        ),
        signInToken: json.nonEmpty('sign_in_token'),
        expiresAt: json.time('expires_at'),
      );
}

/// `PUT /v1/account/password`. Changing a password needs either the current
/// one ([currentAuthKey]) or a fresh phone verification.
final class SetPasswordRequest {
  const SetPasswordRequest({
    required this.password,
    this.currentAuthKey,
    this.verificationToken,
  });

  final PasswordSetup password;
  final Uint8List? currentAuthKey;
  final String? verificationToken;

  JsonMap toJson() => compact({
    'password': password.toJson(),
    'current_auth_key': currentAuthKey == null
        ? null
        : encodeBytes(currentAuthKey!),
    'verification_token': verificationToken,
  });

  factory SetPasswordRequest.fromJson(JsonReader json) => SetPasswordRequest(
    password: PasswordSetup.fromJson(json.object('password')),
    currentAuthKey: json.optBytes('current_auth_key'),
    verificationToken: json.optString('verification_token'),
  );
}

// ---------------------------------------------------------- device linking

/// `POST /v1/auth/links`: a new device starts linking. It shows a QR code
/// with [LinkCreateResponse.linkId] and its [ephemeralKey]; the
/// [LinkCreateResponse.pollToken] never leaves the new device.
final class LinkCreateRequest {
  const LinkCreateRequest({required this.ephemeralKey});

  /// Fresh X25519 public key for the provisioning message (CRYPTO_V2.md §2a).
  final Uint8List ephemeralKey;

  JsonMap toJson() => {'ephemeral_key': encodeBytes(ephemeralKey)};

  factory LinkCreateRequest.fromJson(JsonReader json) =>
      LinkCreateRequest(ephemeralKey: json.bytes('ephemeral_key'));
}

final class LinkCreateResponse {
  const LinkCreateResponse({
    required this.linkId,
    required this.pollToken,
    required this.expiresAt,
  });

  final String linkId;

  /// Bearer token for `GET /v1/auth/links/{link_id}`.
  final String pollToken;
  final DateTime expiresAt;

  JsonMap toJson() => {
    'link_id': linkId,
    'poll_token': pollToken,
    'expires_at': toWireTime(expiresAt),
  };

  factory LinkCreateResponse.fromJson(JsonReader json) => LinkCreateResponse(
    linkId: json.nonEmpty('link_id'),
    pollToken: json.nonEmpty('poll_token'),
    expiresAt: json.time('expires_at'),
  );
}

/// `POST /v1/devices/links/{link_id}/approve`, by a signed-in device that
/// scanned the QR code. [provision] is the provisioning message sealed to
/// the new device's ephemeral key (CRYPTO_V2.md §2a); the server cannot
/// read it.
final class LinkApproveRequest {
  const LinkApproveRequest({required this.provision});

  final Uint8List provision;

  JsonMap toJson() => {'provision': encodeBytes(provision)};

  factory LinkApproveRequest.fromJson(JsonReader json) =>
      LinkApproveRequest(provision: json.bytes('provision'));
}

enum LinkStatus implements WireEnum {
  pending('pending'),
  approved('approved'),
  expired('expired');

  const LinkStatus(this.wire);

  @override
  final String wire;
}

/// `GET /v1/auth/links/{link_id}` (long-poll, `?wait_s=` up to 30).
final class LinkPollResponse {
  const LinkPollResponse({
    required this.status,
    this.provision,
    this.linkToken,
  });

  final LinkStatus status;
  final Uint8List? provision;

  /// Single-use token for [AddDeviceRequest.linkToken], set once approved.
  final String? linkToken;

  JsonMap toJson() => compact({
    'status': status.wire,
    'provision': provision == null ? null : encodeBytes(provision!),
    'link_token': linkToken,
  });

  factory LinkPollResponse.fromJson(JsonReader json) => LinkPollResponse(
    status: json.enumValue('status', LinkStatus.values),
    provision: json.optBytes('provision'),
    linkToken: json.optString('link_token'),
  );
}

/// `POST /v1/auth/devices`: adds a device to an existing account, after
/// password sign-in ([signInToken]) or an approved link ([linkToken]).
/// Exactly one token is required.
final class AddDeviceRequest {
  const AddDeviceRequest({
    required this.device,
    required this.prekeys,
    this.signInToken,
    this.linkToken,
  });

  final DeviceRegistration device;
  final PrekeyUpload prekeys;
  final String? signInToken;
  final String? linkToken;

  JsonMap toJson() => compact({
    'device': device.toJson(),
    'prekeys': prekeys.toJson(),
    'sign_in_token': signInToken,
    'link_token': linkToken,
  });

  factory AddDeviceRequest.fromJson(JsonReader json) => AddDeviceRequest(
    device: DeviceRegistration.fromJson(json.object('device')),
    prekeys: PrekeyUpload.fromJson(json.object('prekeys')),
    signInToken: json.optString('sign_in_token'),
    linkToken: json.optString('link_token'),
  );
}

// ----------------------------------------------------- device-key sign-in

/// `POST /v1/auth/challenges`: for a device whose refresh token lapsed.
final class DeviceChallengeRequest {
  const DeviceChallengeRequest({
    required this.accountId,
    required this.deviceId,
  });

  final String accountId;
  final String deviceId;

  JsonMap toJson() => {'account_id': accountId, 'device_id': deviceId};

  factory DeviceChallengeRequest.fromJson(JsonReader json) =>
      DeviceChallengeRequest(
        accountId: json.nonEmpty('account_id'),
        deviceId: json.nonEmpty('device_id'),
      );
}

final class DeviceChallengeResponse {
  const DeviceChallengeResponse({
    required this.challengeId,
    required this.challenge,
    required this.expiresAt,
  });

  /// Random id of this challenge, sent back with the signature. Challenges
  /// are not keyed by the (public) device id, so nobody else can replace
  /// or spend a device's challenge.
  final String challengeId;

  /// Random bytes; the device signs `signInSignatureBody(challenge)`.
  final Uint8List challenge;
  final DateTime expiresAt;

  JsonMap toJson() => {
    'challenge_id': challengeId,
    'challenge': encodeBytes(challenge),
    'expires_at': toWireTime(expiresAt),
  };

  factory DeviceChallengeResponse.fromJson(JsonReader json) =>
      DeviceChallengeResponse(
        challengeId: json.nonEmpty('challenge_id'),
        challenge: json.bytes('challenge'),
        expiresAt: json.time('expires_at'),
      );
}

/// `POST /v1/auth/sessions`.
final class DeviceSignInRequest {
  const DeviceSignInRequest({
    required this.accountId,
    required this.deviceId,
    required this.challengeId,
    required this.challenge,
    required this.signature,
  });

  final String accountId;
  final String deviceId;

  /// `DeviceChallengeResponse.challengeId`.
  final String challengeId;
  final Uint8List challenge;
  final Uint8List signature;

  JsonMap toJson() => {
    'account_id': accountId,
    'device_id': deviceId,
    'challenge_id': challengeId,
    'challenge': encodeBytes(challenge),
    'signature': encodeBytes(signature),
  };

  factory DeviceSignInRequest.fromJson(JsonReader json) => DeviceSignInRequest(
    accountId: json.nonEmpty('account_id'),
    deviceId: json.nonEmpty('device_id'),
    challengeId: json.nonEmpty('challenge_id'),
    challenge: json.bytes('challenge'),
    signature: json.bytes('signature'),
  );
}

/// `POST /v1/auth/sessions/refresh`. Refresh tokens rotate on every use;
/// presenting an already-used one revokes all of the device's tokens.
final class RefreshRequest {
  const RefreshRequest({required this.refreshToken});

  final String refreshToken;

  JsonMap toJson() => {'refresh_token': refreshToken};

  factory RefreshRequest.fromJson(JsonReader json) =>
      RefreshRequest(refreshToken: json.nonEmpty('refresh_token'));

  @override
  String toString() => 'RefreshRequest(redacted)';
}

// ---------------------------------------------------------------- recovery

final class RecoveryLookupRequest {
  const RecoveryLookupRequest({required this.recoveryCode});

  final String recoveryCode;

  JsonMap toJson() => {'recovery_code': recoveryCode};

  factory RecoveryLookupRequest.fromJson(JsonReader json) =>
      RecoveryLookupRequest(recoveryCode: json.nonEmpty('recovery_code'));

  @override
  String toString() => 'RecoveryLookupRequest(redacted)';
}

final class RecoveryLookupResponse {
  const RecoveryLookupResponse({
    required this.valid,
    this.verificationRequired = false,
    this.serverName,
    this.accountId,
  });

  final bool valid;

  /// A phone verification token must accompany the redeem.
  final bool verificationRequired;
  final String? serverName;

  /// The account the code belongs to; present only when [valid]. A recovery
  /// code names no account of its own, and the new device's certificate must
  /// (CRYPTO_V2.md §2), so the client takes the id from here. Holding a valid
  /// code is the whole authority to learn it (the code is an unguessable
  /// bearer secret and the id is not secret), so there is nothing to
  /// enumerate: an unknown, used or expired code answers `valid: false` with
  /// no other field.
  final String? accountId;

  JsonMap toJson() => compact({
    'valid': valid,
    'verification_required': verificationRequired,
    'server_name': serverName,
    'account_id': accountId,
  });

  factory RecoveryLookupResponse.fromJson(JsonReader json) =>
      RecoveryLookupResponse(
        valid: json.boolean('valid'),
        verificationRequired: json.flag('verification_required'),
        serverName: json.optString('server_name'),
        accountId: json.optString('account_id'),
      );
}

/// `POST /v1/auth/recovery/redeem`: moves the account to this device with a
/// new AIK. Every other device is signed out; the history backup (keyed by
/// the old AIK) is deleted.
final class RecoveryRedeemRequest {
  const RecoveryRedeemRequest({
    required this.recoveryCode,
    required this.identityKey,
    required this.device,
    required this.prekeys,
    this.verificationToken,
    this.password,
  });

  final String recoveryCode;
  final Uint8List identityKey;
  final DeviceRegistration device;
  final PrekeyUpload prekeys;
  final String? verificationToken;
  final PasswordSetup? password;

  JsonMap toJson() => compact({
    'recovery_code': recoveryCode,
    'identity_key': encodeBytes(identityKey),
    'device': device.toJson(),
    'prekeys': prekeys.toJson(),
    'verification_token': verificationToken,
    'password': password?.toJson(),
  });

  factory RecoveryRedeemRequest.fromJson(JsonReader json) =>
      RecoveryRedeemRequest(
        recoveryCode: json.nonEmpty('recovery_code'),
        identityKey: json.bytes('identity_key'),
        device: DeviceRegistration.fromJson(json.object('device')),
        prekeys: PrekeyUpload.fromJson(json.object('prekeys')),
        verificationToken: json.optString('verification_token'),
        password: json.has('password')
            ? PasswordSetup.fromJson(json.object('password'))
            : null,
      );
}

// ------------------------------------------------------- account, devices

/// `GET /v1/account`.
final class AccountInfo {
  const AccountInfo({
    required this.accountId,
    required this.identityKey,
    required this.createdAt,
    required this.hasPassword,
    this.helixName,
    this.phoneLast4,
    this.passwordUpdatedAt,
  });

  final String accountId;
  final Uint8List identityKey;
  final DateTime createdAt;
  final bool hasPassword;
  final String? helixName;
  final String? phoneLast4;
  final DateTime? passwordUpdatedAt;

  JsonMap toJson() => compact({
    'account_id': accountId,
    'identity_key': encodeBytes(identityKey),
    'created_at': toWireTime(createdAt),
    'has_password': hasPassword,
    'helix_name': helixName,
    'phone_last4': phoneLast4,
    'password_updated_at': passwordUpdatedAt == null
        ? null
        : toWireTime(passwordUpdatedAt!),
  });

  factory AccountInfo.fromJson(JsonReader json) => AccountInfo(
    accountId: json.nonEmpty('account_id'),
    identityKey: json.bytes('identity_key'),
    createdAt: json.time('created_at'),
    hasPassword: json.boolean('has_password'),
    helixName: json.optString('helix_name'),
    phoneLast4: json.optString('phone_last4'),
    passwordUpdatedAt: json.optTime('password_updated_at'),
  );
}

/// `PUT /v1/account/helix-name`. Names are 3-32 characters of `[a-z0-9_.]`,
/// starting with a letter, stored lowercase; shown as `~name`.
final class SetHelixNameRequest {
  const SetHelixNameRequest({required this.name});

  static final RegExp pattern = RegExp(r'^[a-z][a-z0-9_.]{2,31}$');

  final String name;

  JsonMap toJson() => {'name': name};

  factory SetHelixNameRequest.fromJson(JsonReader json) =>
      SetHelixNameRequest(name: json.nonEmpty('name'));
}

/// One entry of `GET /v1/devices`. Push tokens are never listed (v1 exposed
/// sibling devices' tokens).
final class DeviceInfo {
  const DeviceInfo({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.createdAt,
    required this.current,
    this.lastSeenOn,
  });

  final String deviceId;
  final String name;
  final DevicePlatform platform;
  final DateTime createdAt;

  /// Day granularity (midnight UTC), to keep activity coarse.
  final DateTime? lastSeenOn;

  /// The device making the request.
  final bool current;

  JsonMap toJson() => compact({
    'device_id': deviceId,
    'name': name,
    'platform': platform.wire,
    'created_at': toWireTime(createdAt),
    'last_seen_on': lastSeenOn == null ? null : toWireTime(lastSeenOn!),
    'current': current,
  });

  factory DeviceInfo.fromJson(JsonReader json) => DeviceInfo(
    deviceId: json.nonEmpty('device_id'),
    name: json.string('name'),
    platform: json.enumValue(
      'platform',
      DevicePlatform.values,
      orElse: DevicePlatform.other,
    ),
    createdAt: json.time('created_at'),
    lastSeenOn: json.optTime('last_seen_on'),
    current: json.flag('current'),
  );
}

final class DeviceList {
  const DeviceList({required this.devices});

  final List<DeviceInfo> devices;

  JsonMap toJson() => {
    'devices': [for (final d in devices) d.toJson()],
  };

  factory DeviceList.fromJson(JsonReader json) =>
      DeviceList(devices: json.objects('devices', DeviceInfo.fromJson));
}

/// `PATCH /v1/devices/{device_id}`.
final class RenameDeviceRequest {
  const RenameDeviceRequest({required this.name});

  final String name;

  JsonMap toJson() => {'name': name};

  factory RenameDeviceRequest.fromJson(JsonReader json) =>
      RenameDeviceRequest(name: json.nonEmpty('name'));
}

final class RevokeOthersResponse {
  const RevokeOthersResponse({required this.revoked});

  final int revoked;

  JsonMap toJson() => {'revoked': revoked};

  factory RevokeOthersResponse.fromJson(JsonReader json) =>
      RevokeOthersResponse(revoked: json.integer('revoked'));
}

enum PushTokenKind implements WireEnum {
  fcm('fcm'),
  apns('apns'),
  apnsVoip('apns_voip');

  const PushTokenKind(this.wire);

  @override
  final String wire;
}

/// `PUT /v1/devices/self/push-token`.
final class PushTokenRequest {
  const PushTokenRequest({required this.token, this.kind = PushTokenKind.fcm});

  final String token;
  final PushTokenKind kind;

  JsonMap toJson() => {'token': token, 'kind': kind.wire};

  factory PushTokenRequest.fromJson(JsonReader json) => PushTokenRequest(
    token: json.nonEmpty('token'),
    kind: json.enumValue('kind', PushTokenKind.values),
  );

  @override
  String toString() => 'PushTokenRequest(${kind.wire}, token redacted)';
}

enum SecurityEventKind implements WireEnum {
  signedIn('signed_in'),
  deviceAdded('device_added'),
  deviceRevoked('device_revoked'),
  passwordChanged('password_changed'),
  recoveryUsed('recovery_used'),
  identityChanged('identity_changed'),
  unknown('unknown');

  const SecurityEventKind(this.wire);

  @override
  final String wire;
}

/// One entry of `GET /v1/account/security-events` (paged).
final class SecurityEvent {
  const SecurityEvent({
    required this.kind,
    required this.at,
    this.deviceId,
    this.deviceName,
  });

  final SecurityEventKind kind;
  final DateTime at;
  final String? deviceId;
  final String? deviceName;

  JsonMap toJson() => compact({
    'kind': kind.wire,
    'at': toWireTime(at),
    'device_id': deviceId,
    'device_name': deviceName,
  });

  factory SecurityEvent.fromJson(JsonReader json) => SecurityEvent(
    kind: json.enumValue(
      'kind',
      SecurityEventKind.values,
      orElse: SecurityEventKind.unknown,
    ),
    at: json.time('at'),
    deviceId: json.optString('device_id'),
    deviceName: json.optString('device_name'),
  );
}
