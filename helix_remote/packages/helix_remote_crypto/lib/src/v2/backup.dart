import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as c;
import 'package:helix_remote_crypto/src/v2/codec.dart';
import 'package:helix_remote_crypto/src/v2/errors.dart';
import 'package:helix_remote_crypto/src/v2/identity.dart';
import 'package:helix_remote_crypto/src/v2/primitives.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Backups (CRYPTO_V2.md §13). Session and prekey private state is never
/// part of a backup.

/// Argon2id parameters for recovery secrets (F2: m = 8192 KiB, t = 2, p = 1).
final class BackupKdfParams {
  const BackupKdfParams({
    this.memoryKib = minMemoryKib,
    this.iterations = minIterations,
    this.parallelism = 1,
  });

  static const minMemoryKib = 8192;
  static const maxMemoryKib = 262144;
  static const minIterations = 2;
  static const length = 32;

  final int memoryKib;
  final int iterations;
  final int parallelism;

  /// Envelopes naming weaker (or absurd) parameters are refused, so a
  /// tampered envelope cannot downgrade the KDF.
  bool get isAcceptable =>
      memoryKib >= minMemoryKib &&
      memoryKib <= maxMemoryKib &&
      iterations >= minIterations &&
      iterations <= 10 &&
      parallelism >= 1 &&
      parallelism <= 4;

  JsonMap toJson() => {
    'alg': 'argon2id',
    'memory_kib': memoryKib,
    'iterations': iterations,
    'parallelism': parallelism,
    'length': length,
  };

  factory BackupKdfParams.fromJson(JsonReader json) {
    if (json.string('alg') != 'argon2id' || json.integer('length') != length) {
      throw const MalformedCryptoInputException('unsupported backup KDF');
    }
    return BackupKdfParams(
      memoryKib: json.integer('memory_kib'),
      iterations: json.integer('iterations'),
      parallelism: json.integer('parallelism'),
    );
  }
}

enum BackupKeyWrapMethod implements WireEnum {
  /// Argon2id of the user's recovery secret.
  recoverySecret('recovery_secret'),

  /// A key held by the platform credential store (Android Block Store,
  /// Windows credential locker), supplied by the app.
  platformCredential('platform_credential');

  const BackupKeyWrapMethod(this.wire);

  @override
  final String wire;
}

/// The random backup key sealed by one method.
final class BackupKeyWrap {
  const BackupKeyWrap({
    required this.method,
    required this.nonce,
    required this.ciphertext,
    this.salt,
    this.kdf,
  });

  final BackupKeyWrapMethod method;
  final Uint8List? salt;
  final BackupKdfParams? kdf;
  final Uint8List nonce;
  final Uint8List ciphertext;

  JsonMap toJson() => {
    'method': method.wire,
    'salt': ?(salt == null ? null : encodeBytes(salt!)),
    'kdf': ?kdf?.toJson(),
    'nonce': encodeBytes(nonce),
    'ciphertext': encodeBytes(ciphertext),
  };

  factory BackupKeyWrap.fromJson(JsonReader json) => BackupKeyWrap(
    method: json.enumValue('method', BackupKeyWrapMethod.values),
    salt: json.optBytes('salt'),
    kdf: json.has('kdf') ? BackupKdfParams.fromJson(json.object('kdf')) : null,
    nonce: json.bytes('nonce'),
    ciphertext: json.bytes('ciphertext'),
  );
}

/// The full-backup envelope, v3 (`FullBackup.envelope`). Field names avoid
/// the ones the server refuses (`backup_key`, `passphrase`,
/// `recovery_phrase`).
final class BackupEnvelope {
  const BackupEnvelope({
    required this.backupId,
    required this.backupVersion,
    required this.createdAt,
    required this.nonce,
    required this.ciphertext,
    required this.keyWraps,
  });

  static const format = 'helix.v2.backup';
  static const envelopeVersion = 3;

  /// UUID; part of every AEAD's associated data.
  final String backupId;

  /// `FullBackup.version`; part of every AEAD's associated data, so the
  /// server cannot present an older backup under a newer version.
  final int backupVersion;
  final DateTime createdAt;
  final Uint8List nonce;
  final Uint8List ciphertext;
  final List<BackupKeyWrap> keyWraps;

  JsonMap toJson() => {
    'format': format,
    'v': envelopeVersion,
    'backup_id': backupId,
    'version': backupVersion,
    'created_at': toWireTime(createdAt),
    'nonce': encodeBytes(nonce),
    'ciphertext': encodeBytes(ciphertext),
    'key_wraps': [for (final w in keyWraps) w.toJson()],
  };

  factory BackupEnvelope.fromJson(JsonReader json) =>
      readState('backup envelope', () {
        if (json.string('format') != format) {
          throw const MalformedCryptoInputException('not a v2 backup');
        }
        requireVersion(json, envelopeVersion, 'backup envelope');
        return BackupEnvelope(
          backupId: json.nonEmpty('backup_id'),
          backupVersion: json.integer('version'),
          createdAt: json.time('created_at'),
          nonce: json.bytes('nonce'),
          ciphertext: json.bytes('ciphertext'),
          keyWraps: json.objects('key_wraps', BackupKeyWrap.fromJson),
        );
      });
}

abstract final class BackupCrypto {
  /// `"helix.v2.backup" ‖ backup_id(16) ‖ u32(version)`.
  static Uint8List associatedData(String backupId, int version) => concatBytes([
    label('helix.v2.backup'),
    uuidBytes(backupId),
    u32(version),
  ]);

  /// The F2 recovery-secret rule: at least 16 characters or 6 words.
  static bool isValidRecoverySecret(String secret) {
    final words = secret
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    return secret.length >= 16 || words.length >= 6;
  }

  /// Encrypts [plaintext] under a random backup key, wrapped by the recovery
  /// secret and, when given, by [platformKey].
  static Future<BackupEnvelope> seal({
    required List<int> plaintext,
    required String backupId,
    required int backupVersion,
    required String recoverySecret,
    required DateTime createdAt,
    required CryptoRandom random,
    List<int>? platformKey,
    BackupKdfParams kdf = const BackupKdfParams(),
  }) async {
    if (!isValidRecoverySecret(recoverySecret)) {
      throw ArgumentError('recovery secret does not meet the policy');
    }
    if (!kdf.isAcceptable) throw ArgumentError('weak backup KDF');
    final aad = associatedData(backupId, backupVersion);
    final backupKey = random.nextBytes(32);
    final nonce = random.nextBytes(Aead.nonceLength);
    final ciphertext = await Aead.seal(
      key: backupKey,
      nonce: nonce,
      plaintext: plaintext,
      aad: aad,
    );
    final salt = random.nextBytes(32);
    final wraps = [
      await _wrap(
        BackupKeyWrapMethod.recoverySecret,
        await _recoveryKey(recoverySecret, salt, kdf),
        backupKey,
        aad,
        random,
        salt: salt,
        kdf: kdf,
      ),
      if (platformKey != null)
        await _wrap(
          BackupKeyWrapMethod.platformCredential,
          platformKey,
          backupKey,
          aad,
          random,
        ),
    ];
    return BackupEnvelope(
      backupId: backupId,
      backupVersion: backupVersion,
      createdAt: createdAt.toUtc(),
      nonce: nonce,
      ciphertext: ciphertext,
      keyWraps: wraps,
    );
  }

  /// Opens with [platformKey] if given and a platform wrap exists, otherwise
  /// with [recoverySecret]. Throws [DecryptionFailedException] for a wrong
  /// secret or a tampered envelope.
  static Future<Uint8List> open(
    BackupEnvelope envelope, {
    String? recoverySecret,
    List<int>? platformKey,
  }) async {
    final aad = associatedData(envelope.backupId, envelope.backupVersion);
    Uint8List? backupKey;
    final platform = envelope.keyWraps
        .where((w) => w.method == BackupKeyWrapMethod.platformCredential)
        .firstOrNull;
    if (platformKey != null && platform != null) {
      backupKey = await _unwrap(platform, platformKey, aad);
    } else if (recoverySecret != null) {
      final wrap = envelope.keyWraps
          .where((w) => w.method == BackupKeyWrapMethod.recoverySecret)
          .firstOrNull;
      final kdf = wrap?.kdf;
      final salt = wrap?.salt;
      if (wrap == null || kdf == null || salt == null || salt.length < 16) {
        throw const MalformedCryptoInputException('no recovery-secret wrap');
      }
      if (!kdf.isAcceptable) {
        throw const MalformedCryptoInputException('backup KDF is too weak');
      }
      backupKey = await _unwrap(
        wrap,
        await _recoveryKey(recoverySecret, salt, kdf),
        aad,
      );
    } else {
      throw ArgumentError('a recovery secret or platform key is required');
    }
    return Aead.open(
      key: backupKey,
      nonce: envelope.nonce,
      ciphertext: envelope.ciphertext,
      aad: aad,
    );
  }

  static Future<Uint8List> _recoveryKey(
    String secret,
    List<int> salt,
    BackupKdfParams kdf,
  ) async {
    final argon = c.Argon2id(
      parallelism: kdf.parallelism,
      memory: kdf.memoryKib,
      iterations: kdf.iterations,
      hashLength: BackupKdfParams.length,
    );
    final key = await argon.deriveKey(
      secretKey: c.SecretKey(utf8.encode(secret)),
      nonce: copyBytes(salt),
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  static Future<BackupKeyWrap> _wrap(
    BackupKeyWrapMethod method,
    List<int> wrappingKey,
    Uint8List backupKey,
    Uint8List aad,
    CryptoRandom random, {
    Uint8List? salt,
    BackupKdfParams? kdf,
  }) async {
    requireLength(wrappingKey, 32, 'backup wrapping key');
    final nonce = random.nextBytes(Aead.nonceLength);
    return BackupKeyWrap(
      method: method,
      salt: salt,
      kdf: kdf,
      nonce: nonce,
      ciphertext: await Aead.seal(
        key: wrappingKey,
        nonce: nonce,
        plaintext: backupKey,
        aad: aad,
      ),
    );
  }

  static Future<Uint8List> _unwrap(
    BackupKeyWrap wrap,
    List<int> wrappingKey,
    Uint8List aad,
  ) async {
    requireLength(wrappingKey, 32, 'backup wrapping key');
    final key = await Aead.open(
      key: wrappingKey,
      nonce: wrap.nonce,
      ciphertext: wrap.ciphertext,
      aad: aad,
    );
    requireLength(key, 32, 'backup key');
    return key;
  }
}

/// The automatic history backup (`HistoryBackup.data`), keyed from the AIK
/// and therefore unreadable after an AIK rotation:
///
/// ```
/// key  = HKDF(AIK seed, salt = 0x00*32, info = "helix.v2.history-backup", 32)
/// data = u8(1) ‖ nonce(12) ‖ AES-256-GCM(key, nonce, plaintext,
///        aad = "helix.v2.backup" ‖ account_id(16) ‖ u32(version))
/// ```
abstract final class HistoryBackupCrypto {
  static const formatVersion = 1;

  static Uint8List deriveKey(List<int> identityKeySeed) {
    requireLength(identityKeySeed, 32, 'AIK seed');
    return hkdf(
      ikm: identityKeySeed,
      salt: zeroSalt,
      info: label('helix.v2.history-backup'),
      length: 32,
    );
  }

  static Uint8List associatedData(String accountId, int version) => concatBytes(
    [label('helix.v2.backup'), accountIdBytes(accountId), u32(version)],
  );

  static Future<Uint8List> seal({
    required List<int> identityKeySeed,
    required String accountId,
    required int version,
    required List<int> plaintext,
    required CryptoRandom random,
  }) async {
    final nonce = random.nextBytes(Aead.nonceLength);
    return concatBytes([
      u8(formatVersion),
      nonce,
      await Aead.seal(
        key: deriveKey(identityKeySeed),
        nonce: nonce,
        plaintext: plaintext,
        aad: associatedData(accountId, version),
      ),
    ]);
  }

  static Future<Uint8List> open({
    required List<int> identityKeySeed,
    required String accountId,
    required int version,
    required List<int> data,
  }) {
    if (data.length < 1 + Aead.nonceLength + Aead.tagLength ||
        data[0] != formatVersion) {
      throw const MalformedCryptoInputException('not a v2 history backup');
    }
    return Aead.open(
      key: deriveKey(identityKeySeed),
      nonce: data.sublist(1, 1 + Aead.nonceLength),
      ciphertext: data.sublist(1 + Aead.nonceLength),
      aad: associatedData(accountId, version),
    );
  }
}
