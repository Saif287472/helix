import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:helix_remote_server/src/kernel/crypto.dart';

/// Argon2id parameters, stored with each hash so they can be raised later
/// without invalidating existing passwords.
final class Argon2Params {
  const Argon2Params({
    required this.memoryKib,
    required this.iterations,
    this.parallelism = 1,
  });

  /// OWASP's minimum for Argon2id: 19 MiB, 2 passes, 1 lane.
  static const recommended = Argon2Params(memoryKib: 19456, iterations: 2);

  final int memoryKib;
  final int iterations;
  final int parallelism;

  Map<String, Object?> toJson() => {
    'alg': 'argon2id',
    'm': memoryKib,
    't': iterations,
    'p': parallelism,
  };

  static Argon2Params fromJson(Map<String, Object?> json) {
    if (json['alg'] != 'argon2id') {
      throw const FormatException('unsupported password hash');
    }
    return Argon2Params(
      memoryKib: json['m']! as int,
      iterations: json['t']! as int,
      parallelism: json['p']! as int,
    );
  }
}

/// A stored admin password: parameters, salt and Argon2id output.
final class PasswordHash {
  const PasswordHash({
    required this.params,
    required this.salt,
    required this.hash,
  });

  final Argon2Params params;
  final Uint8List salt;
  final Uint8List hash;

  /// Hashes [password] with a fresh salt, on a separate isolate (Argon2id
  /// is deliberately slow and must not stall request handling).
  static Future<PasswordHash> create(
    String password,
    Argon2Params params,
  ) async {
    final salt = randomBytes(16);
    final hash = await _derive(password, salt, params);
    return PasswordHash(params: params, salt: salt, hash: hash);
  }

  /// Constant-time comparison of [password]'s hash with this one.
  Future<bool> verify(String password) async =>
      constantTimeEquals(await _derive(password, salt, params), hash);

  static Future<Uint8List> _derive(
    String password,
    Uint8List salt,
    Argon2Params params,
  ) => Isolate.run(() async {
    final algorithm = DartArgon2id(
      parallelism: params.parallelism,
      memory: params.memoryKib,
      iterations: params.iterations,
      hashLength: 32,
    );
    final key = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  });
}
