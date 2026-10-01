import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/src/ids.dart';
import 'package:helix_remote_protocol/src/json.dart';

/// X25519 signed prekey (CRYPTO_V2.md §2-3). [signature] is
/// `Ed25519(DSK, signedPrekeySignatureBody(id, publicKey))`.
final class SignedPrekey {
  const SignedPrekey({
    required this.id,
    required this.publicKey,
    required this.signature,
  });

  final int id;
  final Uint8List publicKey;
  final Uint8List signature;

  JsonMap toJson() => {
    'id': id,
    'public_key': encodeBytes(publicKey),
    'signature': encodeBytes(signature),
  };

  factory SignedPrekey.fromJson(JsonReader json) => SignedPrekey(
    id: json.integer('id'),
    publicKey: json.bytes('public_key'),
    signature: json.bytes('signature'),
  );
}

final class OneTimePrekey {
  const OneTimePrekey({required this.id, required this.publicKey});

  final int id;
  final Uint8List publicKey;

  JsonMap toJson() => {'id': id, 'public_key': encodeBytes(publicKey)};

  factory OneTimePrekey.fromJson(JsonReader json) => OneTimePrekey(
    id: json.integer('id'),
    publicKey: json.bytes('public_key'),
  );
}

/// The prekeys a device publishes when it is added.
final class PrekeyUpload {
  const PrekeyUpload({
    required this.signedPrekey,
    required this.oneTimePrekeys,
  });

  final SignedPrekey signedPrekey;
  final List<OneTimePrekey> oneTimePrekeys;

  JsonMap toJson() => {
    'signed_prekey': signedPrekey.toJson(),
    'one_time_prekeys': [for (final k in oneTimePrekeys) k.toJson()],
  };

  factory PrekeyUpload.fromJson(JsonReader json) => PrekeyUpload(
    signedPrekey: SignedPrekey.fromJson(json.object('signed_prekey')),
    oneTimePrekeys: json.objects('one_time_prekeys', OneTimePrekey.fromJson),
  );
}

/// `POST /v1/keys/one-time-prekeys`.
final class AddOneTimePrekeysRequest {
  const AddOneTimePrekeysRequest({required this.keys});

  /// At most [maxBatch] per request.
  static const maxBatch = 200;

  final List<OneTimePrekey> keys;

  JsonMap toJson() => {
    'keys': [for (final k in keys) k.toJson()],
  };

  factory AddOneTimePrekeysRequest.fromJson(JsonReader json) =>
      AddOneTimePrekeysRequest(
        keys: json.objects('keys', OneTimePrekey.fromJson),
      );
}

/// `GET /v1/keys/status`.
final class KeyStatus {
  const KeyStatus({
    required this.oneTimeRemaining,
    this.signedPrekeyId,
    this.signedPrekeyUpdatedAt,
  });

  /// Below this, the server sends `prekeys_low`.
  static const lowWatermark = 20;

  final int oneTimeRemaining;
  final int? signedPrekeyId;
  final DateTime? signedPrekeyUpdatedAt;

  JsonMap toJson() => compact({
    'one_time_remaining': oneTimeRemaining,
    'signed_prekey_id': signedPrekeyId,
    'signed_prekey_updated_at': signedPrekeyUpdatedAt == null
        ? null
        : toWireTime(signedPrekeyUpdatedAt!),
  });

  factory KeyStatus.fromJson(JsonReader json) => KeyStatus(
    oneTimeRemaining: json.integer('one_time_remaining'),
    signedPrekeyId: json.optInt('signed_prekey_id'),
    signedPrekeyUpdatedAt: json.optTime('signed_prekey_updated_at'),
  );
}

/// AIK signature binding a device to its account (CRYPTO_V2.md §2).
final class DeviceCertificate {
  const DeviceCertificate({required this.createdAt, required this.signature});

  final DateTime createdAt;
  final Uint8List signature;

  JsonMap toJson() => {
    'created_at': toWireTime(createdAt),
    'signature': encodeBytes(signature),
  };

  factory DeviceCertificate.fromJson(JsonReader json) => DeviceCertificate(
    createdAt: json.time('created_at'),
    signature: json.bytes('signature'),
  );
}

/// One device in `GET /v1/keys/{account}`.
final class DeviceBundle {
  const DeviceBundle({
    required this.deviceId,
    required this.identityKey,
    required this.signingKey,
    required this.certificate,
    required this.signedPrekey,
    this.oneTimePrekey,
  });

  final String deviceId;

  /// DIK (X25519).
  final Uint8List identityKey;

  /// DSK (Ed25519).
  final Uint8List signingKey;
  final DeviceCertificate certificate;
  final SignedPrekey signedPrekey;

  /// Consumed by this fetch; null when the device has none left.
  final OneTimePrekey? oneTimePrekey;

  JsonMap toJson() => compact({
    'device_id': deviceId,
    'identity_key': encodeBytes(identityKey),
    'signing_key': encodeBytes(signingKey),
    'certificate': certificate.toJson(),
    'signed_prekey': signedPrekey.toJson(),
    'one_time_prekey': oneTimePrekey?.toJson(),
  });

  factory DeviceBundle.fromJson(JsonReader json) => DeviceBundle(
    deviceId: json.nonEmpty('device_id'),
    identityKey: json.bytes('identity_key'),
    signingKey: json.bytes('signing_key'),
    certificate: DeviceCertificate.fromJson(json.object('certificate')),
    signedPrekey: SignedPrekey.fromJson(json.object('signed_prekey')),
    oneTimePrekey: json.has('one_time_prekey')
        ? OneTimePrekey.fromJson(json.object('one_time_prekey'))
        : null,
  );
}

/// `GET /v1/keys/{account}` (optionally `?device=<id>&device=<id>`).
final class AccountKeys {
  const AccountKeys({
    required this.account,
    required this.identityKey,
    required this.devices,
  });

  final String account;

  /// AIK (Ed25519).
  final Uint8List identityKey;
  final List<DeviceBundle> devices;

  JsonMap toJson() => {
    'account': account,
    'identity_key': encodeBytes(identityKey),
    'devices': [for (final d in devices) d.toJson()],
  };

  factory AccountKeys.fromJson(JsonReader json) => AccountKeys(
    account: json.nonEmpty('account'),
    identityKey: json.bytes('identity_key'),
    devices: json.objects('devices', DeviceBundle.fromJson),
  );
}

// ------------------------------------------------------------ signed bytes

/// The 16 raw bytes of a canonical UUID.
Uint8List uuidBytes(String uuid) {
  if (!Uuid.isValid(uuid)) {
    throw ArgumentError.value(uuid, 'uuid', 'is not a canonical UUID');
  }
  final hex = uuid.replaceAll('-', '');
  return Uint8List.fromList([
    for (var i = 0; i < 32; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);

Uint8List _u64(int v) => Uint8List(8)..buffer.asByteData().setUint64(0, v);

/// Bytes the AIK signs in a device certificate (CRYPTO_V2.md §2). The DSK
/// also signs these bytes as proof of possession when a device is added.
Uint8List deviceCertificateBody({
  required String accountId,
  required String deviceId,
  required List<int> identityKey,
  required List<int> signingKey,
  required DateTime createdAt,
}) {
  if (identityKey.length != 32 || signingKey.length != 32) {
    throw ArgumentError('device keys must be 32 bytes');
  }
  return (BytesBuilder(copy: false)
        ..add(ascii.encode('helix.v2.device-cert'))
        ..addByte(1)
        ..add(uuidBytes(accountId))
        ..add(uuidBytes(deviceId))
        ..add(identityKey)
        ..add(signingKey)
        ..add(_u64(createdAt.toUtc().millisecondsSinceEpoch)))
      .toBytes();
}

/// Bytes the DSK signs for a signed prekey (CRYPTO_V2.md §2).
Uint8List signedPrekeySignatureBody(int id, List<int> publicKey) {
  if (publicKey.length != 32) {
    throw ArgumentError('prekeys must be 32 bytes');
  }
  return (BytesBuilder(copy: false)
        ..add(ascii.encode('helix.v2.spk'))
        ..add(_u32(id))
        ..add(publicKey))
      .toBytes();
}

/// Bytes the DSK signs to answer a sign-in challenge.
Uint8List signInSignatureBody(List<int> challenge) =>
    (BytesBuilder(copy: false)
          ..add(ascii.encode('helix.v2.sign-in'))
          ..add(challenge))
        .toBytes();
