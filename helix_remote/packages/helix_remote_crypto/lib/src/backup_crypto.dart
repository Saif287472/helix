import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as crypto;

class RemoteBackupKdfParameters {
  const RemoteBackupKdfParameters({
    required this.algorithm,
    required this.memoryKb,
    required this.iterations,
    required this.parallelism,
    required this.outputBytes,
  });

  final String algorithm;
  final int memoryKb;
  final int iterations;
  final int parallelism;
  final int outputBytes;

  Map<String, dynamic> toJson() => {
    'algorithm': algorithm,
    'memory_kb': memoryKb,
    'iterations': iterations,
    'parallelism': parallelism,
    'output_bytes': outputBytes,
  };

  factory RemoteBackupKdfParameters.fromJson(Map<String, dynamic> json) {
    return RemoteBackupKdfParameters(
      algorithm: json['algorithm'] as String? ?? 'PBKDF2-HMAC-SHA256',
      memoryKb: json['memory_kb'] as int? ?? 0,
      iterations: json['iterations'] as int? ?? 100000,
      parallelism: json['parallelism'] as int? ?? 1,
      outputBytes: json['output_bytes'] as int? ?? 32,
    );
  }
}

class RemoteBackupMediaObject {
  const RemoteBackupMediaObject({
    required this.objectId,
    required this.attachmentId,
    required this.sizeBytes,
    required this.sha256,
    this.contentType = 'application/octet-stream',
  });

  final String objectId;
  final String attachmentId;
  final int sizeBytes;
  final String sha256;
  final String contentType;

  Map<String, dynamic> toJson() => {
    'object_id': objectId,
    'attachment_id': attachmentId,
    'size_bytes': sizeBytes,
    'sha256': sha256,
    'content_type': contentType,
  };

  factory RemoteBackupMediaObject.fromJson(Map<String, dynamic> json) {
    return RemoteBackupMediaObject(
      objectId: json['object_id'] as String,
      attachmentId: json['attachment_id'] as String,
      sizeBytes: json['size_bytes'] as int,
      sha256: json['sha256'] as String,
      contentType:
          json['content_type'] as String? ?? 'application/octet-stream',
    );
  }
}

class RemoteBackupKeyWrap {
  const RemoteBackupKeyWrap({
    required this.label,
    required this.method,
    required this.salt,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  final String label;
  final String method;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List mac;

  Map<String, dynamic> toJson() => {
    'label': label,
    'method': method,
    'salt': base64Url.encode(salt),
    'nonce': base64Url.encode(nonce),
    'ciphertext': base64Url.encode(ciphertext),
    'mac': base64Url.encode(mac),
  };

  factory RemoteBackupKeyWrap.fromJson(Map<String, dynamic> json) {
    return RemoteBackupKeyWrap(
      label: json['label'] as String,
      method: json['method'] as String,
      salt: base64Url.decode(base64Url.normalize(json['salt'] as String)),
      nonce: base64Url.decode(base64Url.normalize(json['nonce'] as String)),
      ciphertext: base64Url.decode(
        base64Url.normalize(json['ciphertext'] as String),
      ),
      mac: base64Url.decode(base64Url.normalize(json['mac'] as String)),
    );
  }
}

class RemoteBackupEnvelope {
  const RemoteBackupEnvelope({
    required this.backupId,
    required this.version,
    required this.kdf,
    required this.salt,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    required this.backupKeyHint,
    required this.createdAt,
    this.deletionWatermark = 0,
    this.snapshotVersion = RemoteBackupCrypto.currentSnapshotVersion,
    this.attachmentManifestVersion =
        RemoteBackupCrypto.currentAttachmentManifestVersion,
    this.kdfParameters = RemoteBackupCrypto.currentKdfParameters,
    this.mediaObjects = const [],
    this.keyWraps = const [],
    this.restoreSemantics = 'replace_local_state',
  });

  final String backupId;
  final int version;
  final String kdf;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List mac;
  final String backupKeyHint;
  final int createdAt;
  final int deletionWatermark;
  final int snapshotVersion;
  final int attachmentManifestVersion;
  final RemoteBackupKdfParameters kdfParameters;
  final List<RemoteBackupMediaObject> mediaObjects;
  final List<RemoteBackupKeyWrap> keyWraps;
  final String restoreSemantics;

  Map<String, dynamic> toJson() => {
    'backup_id': backupId,
    'version': version,
    'snapshot_version': snapshotVersion,
    'attachment_manifest_version': attachmentManifestVersion,
    'kdf': kdf,
    'kdf_parameters': kdfParameters.toJson(),
    'salt': base64Url.encode(salt),
    'nonce': base64Url.encode(nonce),
    'ciphertext': base64Url.encode(ciphertext),
    'mac': base64Url.encode(mac),
    'backup_key_hint': backupKeyHint,
    'created_at': createdAt,
    'deletion_watermark': deletionWatermark,
    'restore_semantics': restoreSemantics,
    'media_manifest': {
      'version': attachmentManifestVersion,
      'objects': mediaObjects.map((object) => object.toJson()).toList(),
    },
    'key_wraps': keyWraps.map((wrap) => wrap.toJson()).toList(),
  };

  factory RemoteBackupEnvelope.fromJson(Map<String, dynamic> json) {
    final mediaManifest = json['media_manifest'] as Map<String, dynamic>?;
    final keyWrapsJson = json['key_wraps'] as List<dynamic>? ?? const [];
    return RemoteBackupEnvelope(
      backupId: json['backup_id'] as String,
      version: json['version'] as int,
      snapshotVersion: json['snapshot_version'] as int? ?? 1,
      attachmentManifestVersion:
          json['attachment_manifest_version'] as int? ??
          (mediaManifest?['version'] as int? ?? 1),
      kdf: json['kdf'] as String,
      kdfParameters: json['kdf_parameters'] is Map<String, dynamic>
          ? RemoteBackupKdfParameters.fromJson(
              json['kdf_parameters'] as Map<String, dynamic>,
            )
          : const RemoteBackupKdfParameters(
              algorithm: 'PBKDF2-HMAC-SHA256',
              memoryKb: 0,
              iterations: 100000,
              parallelism: 1,
              outputBytes: 32,
            ),
      salt: base64Url.decode(base64Url.normalize(json['salt'] as String)),
      nonce: base64Url.decode(base64Url.normalize(json['nonce'] as String)),
      ciphertext: base64Url.decode(
        base64Url.normalize(json['ciphertext'] as String),
      ),
      mac: base64Url.decode(base64Url.normalize(json['mac'] as String)),
      backupKeyHint: json['backup_key_hint'] as String? ?? '',
      createdAt: json['created_at'] as int,
      deletionWatermark: json['deletion_watermark'] as int? ?? 0,
      restoreSemantics:
          json['restore_semantics'] as String? ?? 'replace_local_state',
      mediaObjects: ((mediaManifest?['objects'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(RemoteBackupMediaObject.fromJson)
          .toList(),
      keyWraps: keyWrapsJson
          .cast<Map<String, dynamic>>()
          .map(RemoteBackupKeyWrap.fromJson)
          .toList(),
    );
  }
}

class RemoteBackupCrypto {
  final crypto.AesGcm aesGcm = crypto.AesGcm.with256bits();
  static const int currentBackupVersion = 2;
  static const int legacyBackupVersion = 1;
  static const int currentSnapshotVersion = 2;
  static const int currentAttachmentManifestVersion = 1;
  static const String legacyKdf = 'PBKDF2-HMAC-SHA256-100000';
  static const String currentKdf = 'Argon2id-v1-m8192-t2-p1';
  static const RemoteBackupKdfParameters currentKdfParameters =
      RemoteBackupKdfParameters(
        algorithm: 'Argon2id',
        memoryKb: 8192,
        iterations: 2,
        parallelism: 1,
        outputBytes: 32,
      );
  static const String platformKeyWrapMethod =
      'helix.remote.backup-key-wrap.platform-aes-gcm.v1';
  static const String recoveryKeyWrapMethod =
      'helix.remote.backup-key-wrap.recovery-argon2id-aes-gcm.v1';

  Uint8List generateSalt() {
    return Uint8List.fromList(
      aesGcm.newNonce().followedBy(aesGcm.newNonce()).toList(),
    );
  }

  bool isValidRecoverySecret(String secret) {
    final words = secret
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    return secret.length >= 16 || words.length >= 6;
  }

  /// Derives a 256-bit key from a recovery passphrase using Argon2id.
  Future<crypto.SecretKey> deriveBackupKey({
    required String passphrase,
    required Uint8List salt,
  }) async {
    final argon2id = crypto.Argon2id(
      parallelism: currentKdfParameters.parallelism,
      memory: currentKdfParameters.memoryKb,
      iterations: currentKdfParameters.iterations,
      hashLength: currentKdfParameters.outputBytes,
    );
    return argon2id.deriveKey(
      secretKey: crypto.SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  Future<crypto.SecretKey> deriveLegacyBackupKey({
    required String passphrase,
    required Uint8List salt,
  }) async {
    final pbkdf2 = crypto.Pbkdf2(
      macAlgorithm: crypto.Hmac(crypto.Sha256()),
      iterations: 100000,
      bits: 256,
    );

    return pbkdf2.deriveKey(
      secretKey: crypto.SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  Uint8List generateBackupKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
  }

  /// Encrypt backup payload.
  Future<Uint8List> encryptBackup(
    Uint8List plaintext,
    crypto.SecretKey derivedKey,
  ) async {
    final nonce = aesGcm.newNonce();
    final box = await aesGcm.encrypt(
      plaintext,
      secretKey: derivedKey,
      nonce: nonce,
    );
    return Uint8List.fromList(box.concatenation());
  }

  /// Decrypt backup payload.
  Future<Uint8List> decryptBackup(
    Uint8List ciphertextBytes,
    crypto.SecretKey derivedKey,
  ) async {
    final box = crypto.SecretBox.fromConcatenation(
      ciphertextBytes,
      nonceLength: 12,
      macLength: 16,
    );
    final plaintext = await aesGcm.decrypt(box, secretKey: derivedKey);
    return Uint8List.fromList(plaintext);
  }

  Future<RemoteBackupEnvelope> encryptBackupEnvelope({
    required Uint8List plaintext,
    required String passphrase,
    required String backupId,
    required String backupKeyHint,
    Uint8List? salt,
    int? deletionWatermark,
  }) async {
    if (!isValidRecoverySecret(passphrase)) {
      throw ArgumentError('Recovery secret does not meet Helix Remote policy');
    }

    final actualSalt = salt ?? generateSalt();
    final key = await deriveBackupKey(passphrase: passphrase, salt: actualSalt);
    final nonce = aesGcm.newNonce();
    final box = await aesGcm.encrypt(plaintext, secretKey: key, nonce: nonce);
    return RemoteBackupEnvelope(
      backupId: backupId,
      version: currentBackupVersion,
      kdf: currentKdf,
      salt: actualSalt,
      nonce: Uint8List.fromList(box.nonce),
      ciphertext: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
      backupKeyHint: backupKeyHint,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      deletionWatermark: deletionWatermark ?? 0,
    );
  }

  Future<RemoteBackupEnvelope> encryptBackupEnvelopeWithWrappedKey({
    required Uint8List plaintext,
    required String recoverySecret,
    required Uint8List platformWrappingKey,
    required String backupId,
    required String backupKeyHint,
    List<RemoteBackupMediaObject> mediaObjects = const [],
    Uint8List? salt,
    int? deletionWatermark,
  }) async {
    if (!isValidRecoverySecret(recoverySecret)) {
      throw ArgumentError('Recovery secret does not meet Helix Remote policy');
    }
    final backupKeyBytes = generateBackupKey();
    final backupKey = crypto.SecretKey(backupKeyBytes);
    final actualSalt = salt ?? generateSalt();
    final nonce = aesGcm.newNonce();
    final box = await aesGcm.encrypt(
      plaintext,
      secretKey: backupKey,
      nonce: nonce,
    );
    final recoveryWrap = await wrapBackupKeyWithRecoverySecret(
      backupKey: backupKeyBytes,
      recoverySecret: recoverySecret,
      salt: actualSalt,
    );
    final platformWrap = await wrapBackupKeyWithPlatformKey(
      backupKey: backupKeyBytes,
      platformWrappingKey: platformWrappingKey,
      salt: generateSalt(),
    );
    return RemoteBackupEnvelope(
      backupId: backupId,
      version: currentBackupVersion,
      kdf: currentKdf,
      salt: actualSalt,
      nonce: Uint8List.fromList(box.nonce),
      ciphertext: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
      backupKeyHint: backupKeyHint,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      deletionWatermark: deletionWatermark ?? 0,
      mediaObjects: mediaObjects,
      keyWraps: [recoveryWrap, platformWrap],
    );
  }

  Future<Uint8List> decryptBackupEnvelope(
    RemoteBackupEnvelope envelope, {
    required String passphrase,
    Uint8List? platformWrappingKey,
  }) async {
    final keyWrap = _selectUsableKeyWrap(envelope, platformWrappingKey);
    if (keyWrap != null) {
      final backupKeyBytes = keyWrap.method == platformKeyWrapMethod
          ? await unwrapBackupKeyWithPlatformKey(
              wrap: keyWrap,
              platformWrappingKey: platformWrappingKey!,
            )
          : await unwrapBackupKeyWithRecoverySecret(
              wrap: keyWrap,
              recoverySecret: passphrase,
            );
      final box = crypto.SecretBox(
        envelope.ciphertext,
        nonce: envelope.nonce,
        mac: crypto.Mac(envelope.mac),
      );
      final plaintext = await aesGcm.decrypt(
        box,
        secretKey: crypto.SecretKey(backupKeyBytes),
      );
      return Uint8List.fromList(plaintext);
    }

    if (envelope.version == legacyBackupVersion && envelope.kdf == legacyKdf) {
      final key = await deriveLegacyBackupKey(
        passphrase: passphrase,
        salt: envelope.salt,
      );
      final box = crypto.SecretBox(
        envelope.ciphertext,
        nonce: envelope.nonce,
        mac: crypto.Mac(envelope.mac),
      );
      final plaintext = await aesGcm.decrypt(box, secretKey: key);
      return Uint8List.fromList(plaintext);
    }
    if (envelope.version != currentBackupVersion ||
        envelope.kdf != currentKdf) {
      throw UnsupportedError('Unsupported backup envelope version or KDF');
    }
    final key = await deriveBackupKey(
      passphrase: passphrase,
      salt: envelope.salt,
    );
    final box = crypto.SecretBox(
      envelope.ciphertext,
      nonce: envelope.nonce,
      mac: crypto.Mac(envelope.mac),
    );
    final plaintext = await aesGcm.decrypt(box, secretKey: key);
    return Uint8List.fromList(plaintext);
  }

  RemoteBackupKeyWrap? _selectUsableKeyWrap(
    RemoteBackupEnvelope envelope,
    Uint8List? platformWrappingKey,
  ) {
    if (platformWrappingKey != null) {
      for (final wrap in envelope.keyWraps) {
        if (wrap.method == platformKeyWrapMethod) return wrap;
      }
    }
    for (final wrap in envelope.keyWraps) {
      if (wrap.method == recoveryKeyWrapMethod) return wrap;
    }
    return null;
  }

  Future<RemoteBackupKeyWrap> wrapBackupKeyWithRecoverySecret({
    required Uint8List backupKey,
    required String recoverySecret,
    Uint8List? salt,
  }) async {
    final actualSalt = salt ?? generateSalt();
    final wrappingKey = await deriveBackupKey(
      passphrase: recoverySecret,
      salt: actualSalt,
    );
    return _wrapBackupKey(
      label: 'recovery_secret',
      method: recoveryKeyWrapMethod,
      backupKey: backupKey,
      wrappingKey: wrappingKey,
      salt: actualSalt,
    );
  }

  Future<Uint8List> unwrapBackupKeyWithRecoverySecret({
    required RemoteBackupKeyWrap wrap,
    required String recoverySecret,
  }) async {
    if (wrap.method != recoveryKeyWrapMethod) {
      throw ArgumentError('Unexpected recovery key wrap method');
    }
    final wrappingKey = await deriveBackupKey(
      passphrase: recoverySecret,
      salt: wrap.salt,
    );
    return _unwrapBackupKey(wrap: wrap, wrappingKey: wrappingKey);
  }

  Future<RemoteBackupKeyWrap> wrapBackupKeyWithPlatformKey({
    required Uint8List backupKey,
    required Uint8List platformWrappingKey,
    Uint8List? salt,
  }) async {
    return _wrapBackupKey(
      label: 'platform_credential',
      method: platformKeyWrapMethod,
      backupKey: backupKey,
      wrappingKey: crypto.SecretKey(platformWrappingKey),
      salt: salt ?? Uint8List(0),
    );
  }

  Future<Uint8List> unwrapBackupKeyWithPlatformKey({
    required RemoteBackupKeyWrap wrap,
    required Uint8List platformWrappingKey,
  }) async {
    if (wrap.method != platformKeyWrapMethod) {
      throw ArgumentError('Unexpected platform key wrap method');
    }
    return _unwrapBackupKey(
      wrap: wrap,
      wrappingKey: crypto.SecretKey(platformWrappingKey),
    );
  }

  Future<RemoteBackupKeyWrap> _wrapBackupKey({
    required String label,
    required String method,
    required Uint8List backupKey,
    required crypto.SecretKey wrappingKey,
    required Uint8List salt,
  }) async {
    final nonce = aesGcm.newNonce();
    final box = await aesGcm.encrypt(
      backupKey,
      secretKey: wrappingKey,
      nonce: nonce,
    );
    return RemoteBackupKeyWrap(
      label: label,
      method: method,
      salt: salt,
      nonce: Uint8List.fromList(box.nonce),
      ciphertext: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
    );
  }

  Future<Uint8List> _unwrapBackupKey({
    required RemoteBackupKeyWrap wrap,
    required crypto.SecretKey wrappingKey,
  }) async {
    final box = crypto.SecretBox(
      wrap.ciphertext,
      nonce: wrap.nonce,
      mac: crypto.Mac(wrap.mac),
    );
    final key = await aesGcm.decrypt(box, secretKey: wrappingKey);
    return Uint8List.fromList(key);
  }
}
