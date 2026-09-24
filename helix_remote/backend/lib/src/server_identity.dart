import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_backend/src/database.dart';

String generateUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (i) => random.nextInt(256));

  // Set version to 4 (0100)
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  // Set variant to RFC 4122 (10xx)
  bytes[8] = (bytes[8] & 0x3F) | 0x80;

  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    if (i == 4 || i == 6 || i == 8 || i == 10) {
      buffer.write('-');
    }
    buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

class ServerIdentity {
  final String serverId;
  final crypto.SimpleKeyPair serverKeyPair;

  ServerIdentity({
    required this.serverId,
    required this.serverKeyPair,
  });

  static Future<ServerIdentity> loadOrCreate(
    BackendDatabase db, {
    DateTime Function()? now,
  }) async {
    final serverId = db.getServerConfig('server_id');
    final publicKeyBase64 = db.getServerConfig('server_public_key');
    final privateKeyBase64 = db.getServerConfig('server_private_key');

    final String resolvedServerId;
    final crypto.SimpleKeyPair keyPair;
    if (serverId != null &&
        publicKeyBase64 != null &&
        privateKeyBase64 != null) {
      final pubBytes = base64Decode(publicKeyBase64);
      final privBytes = base64Decode(privateKeyBase64);
      keyPair = crypto.SimpleKeyPairData(
        privBytes,
        publicKey: crypto.SimplePublicKey(
          pubBytes,
          type: crypto.KeyPairType.ed25519,
        ),
        type: crypto.KeyPairType.ed25519,
      );
      resolvedServerId = serverId;
    } else {
      // Generate new Server ID and Keypair
      resolvedServerId = generateUuidV4();
      final algorithm = crypto.Ed25519();
      final newKeyPair = await algorithm.newKeyPair();
      final newPublicKey = await newKeyPair.extractPublicKey();
      final newPrivateKeyBytes = await newKeyPair.extractPrivateKeyBytes();
      db.setServerConfig('server_id', resolvedServerId);
      db.setServerConfig('server_public_key', base64Encode(newPublicKey.bytes));
      db.setServerConfig(
        'server_private_key',
        base64Encode(newPrivateKeyBytes),
      );
      keyPair = newKeyPair;
    }

    return ServerIdentity(
      serverId: resolvedServerId,
      serverKeyPair: keyPair,
    );
  }
}
