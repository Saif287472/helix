import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as crypto;

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

  Map<String, dynamic> toJson() => {
    'backup_id': backupId,
    'version': version,
    'kdf': kdf,
    'salt': base64Url.encode(salt),
    'nonce': base64Url.encode(nonce),
    'ciphertext': base64Url.encode(ciphertext),
    'mac': base64Url.encode(mac),
    'backup_key_hint': backupKeyHint,
    'created_at': createdAt,
    'deletion_watermark': deletionWatermark,
  };

  factory RemoteBackupEnvelope.fromJson(Map<String, dynamic> json) {
    return RemoteBackupEnvelope(
      backupId: json['backup_id'] as String,
      version: json['version'] as int,
      kdf: json['kdf'] as String,
      salt: base64Url.decode(base64Url.normalize(json['salt'] as String)),
      nonce: base64Url.decode(base64Url.normalize(json['nonce'] as String)),
      ciphertext: base64Url.decode(
        base64Url.normalize(json['ciphertext'] as String),
      ),
      mac: base64Url.decode(base64Url.normalize(json['mac'] as String)),
      backupKeyHint: json['backup_key_hint'] as String? ?? '',
      createdAt: json['created_at'] as int,
      deletionWatermark: json['deletion_watermark'] as int? ?? 0,
    );
  }
}

class RemoteBackupCrypto {
  final crypto.AesGcm aesGcm = crypto.AesGcm.with256bits();
  static const int currentBackupVersion = 1;
  static const String currentKdf = 'PBKDF2-HMAC-SHA256-100000';

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

  /// Derives a 256-bit key from a recovery passphrase using PBKDF2-SHA256.
  Future<crypto.SecretKey> deriveBackupKey({
    required String passphrase,
    required Uint8List salt,
  }) async {
    final pbkdf2 = crypto.Pbkdf2(
      macAlgorithm: crypto.Hmac(crypto.Sha256()),
      iterations: 100000,
      bits: 256,
    );

    return pbkdf2.deriveKey(
      secretKey: crypto.SecretKey(passphrase.codeUnits),
      nonce: salt,
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

  Future<Uint8List> decryptBackupEnvelope(
    RemoteBackupEnvelope envelope, {
    required String passphrase,
  }) async {
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
}
