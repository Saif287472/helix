import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';

/// The HKDF salt for derivations that have none: 32 zero bytes, which RFC 5869
/// defines as the value of an absent salt, so keys are unchanged. An empty
/// list must not be passed instead - on Android `cryptography_flutter` runs
/// HMAC natively and Java's `SecretKeySpec` throws on an empty key.
final List<int> hkdfZeroSalt = List.unmodifiable(List<int>.filled(32, 0));

/// Argon2id cost for a password, as the server stores and hands it back.
class PasswordKdfParams {
  const PasswordKdfParams({
    this.memoryKib = 19456,
    this.iterations = 2,
    this.parallelism = 1,
  });

  factory PasswordKdfParams.fromJson(Map<String, dynamic> json) {
    if (json['alg'] != 'argon2id' || json['length'] != 64) {
      throw const FormatException('Unsupported password key stretching');
    }
    return PasswordKdfParams(
      memoryKib: json['memory_kib'] as int,
      iterations: json['iterations'] as int,
      parallelism: json['parallelism'] as int,
    );
  }

  final int memoryKib;
  final int iterations;
  final int parallelism;

  Map<String, dynamic> toJson() => {
    'alg': 'argon2id',
    'memory_kib': memoryKib,
    'iterations': iterations,
    'parallelism': parallelism,
    'length': 64,
  };
}

/// The two keys one password stretches into. [authKey] goes to the server to
/// prove the password; [wrapKey] never leaves the device.
class PasswordKeys {
  const PasswordKeys({required this.authKey, required this.wrapKey});

  /// base64url, 32 bytes.
  final String authKey;
  final List<int> wrapKey;
}

/// Password key stretching and identity-key wrapping.
///
/// The account identity private key signs every device's prekeys, so a new
/// device needs it to be the same account. It travels to the server only
/// encrypted under a key derived from the password; the server holds the
/// ciphertext but can neither read it nor check a password against it
/// without paying for Argon2id on every guess.
class PasswordVault {
  const PasswordVault._();

  static const minimumLength = 8;

  static String? passwordError(String password) {
    if (password.length < minimumLength) {
      return 'Use at least $minimumLength characters.';
    }
    return null;
  }

  static String newSalt() =>
      _b64(List<int>.generate(16, (_) => math.Random.secure().nextInt(256)));

  /// Stretches [password]. Argon2id is deliberately slow (about a second on a
  /// phone), so it runs off the UI isolate.
  static Future<PasswordKeys> deriveKeys({
    required String password,
    required String salt,
    required PasswordKdfParams params,
  }) async {
    final saltBytes = _b64d(salt);
    final master = await Isolate.run(() async {
      final argon = Argon2id(
        memory: params.memoryKib,
        iterations: params.iterations,
        parallelism: params.parallelism,
        hashLength: 64,
      );
      final key = await argon.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: saltBytes,
      );
      return key.extractBytes();
    });
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    Future<List<int>> expand(String info) async => (await hkdf.deriveKey(
      secretKey: SecretKey(master),
      nonce: hkdfZeroSalt,
      info: utf8.encode(info),
    )).extractBytes();
    return PasswordKeys(
      authKey: _b64(await expand('helix.remote.password.auth.v1')),
      wrapKey: await expand('helix.remote.password.wrap.v1'),
    );
  }

  /// Encrypts the identity private key under [wrapKey], bound to the identity
  /// public key so a blob can never be swapped onto another identity.
  static Future<String> wrapIdentityKey({
    required List<int> wrapKey,
    required List<int> identityPrivateKey,
    required String identityPublicKey,
  }) async {
    final nonce = List<int>.generate(
      12,
      (_) => math.Random.secure().nextInt(256),
    );
    final box = await AesGcm.with256bits().encrypt(
      identityPrivateKey,
      secretKey: SecretKey(wrapKey),
      nonce: nonce,
      aad: _aad(identityPublicKey),
    );
    return _b64(
      utf8.encode(
        jsonEncode({
          'v': 1,
          'n': _b64(nonce),
          'ct': _b64([...box.cipherText, ...box.mac.bytes]),
        }),
      ),
    );
  }

  /// Reverses [wrapIdentityKey]. Throws [SecretBoxAuthenticationError] when
  /// the password is wrong or the blob was tampered with.
  static Future<List<int>> unwrapIdentityKey({
    required List<int> wrapKey,
    required String wrapped,
    required String identityPublicKey,
  }) async {
    final json =
        jsonDecode(utf8.decode(_b64d(wrapped))) as Map<String, dynamic>;
    if (json['v'] != 1) {
      throw const FormatException('Unknown wrapped identity key version');
    }
    final payload = _b64d(json['ct'] as String);
    if (payload.length < 16) {
      throw const FormatException('Wrapped identity key is truncated');
    }
    return AesGcm.with256bits().decrypt(
      SecretBox(
        payload.sublist(0, payload.length - 16),
        nonce: _b64d(json['n'] as String),
        mac: Mac(payload.sublist(payload.length - 16)),
      ),
      secretKey: SecretKey(wrapKey),
      aad: _aad(identityPublicKey),
    );
  }

  static List<int> _aad(String identityPublicKey) =>
      utf8.encode('helix.remote.identity-wrap.v1\n$identityPublicKey');

  static String _b64(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static List<int> _b64d(String value) =>
      base64Url.decode(base64Url.normalize(value));
}
