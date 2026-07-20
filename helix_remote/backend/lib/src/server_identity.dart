import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:crypto/crypto.dart' as crypto_pkg;
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
  final String? adminToken; // Set only if generated on first boot

  ServerIdentity({
    required this.serverId,
    required this.serverKeyPair,
    this.adminToken,
  });

  static Future<ServerIdentity> loadOrCreate(BackendDatabase db) async {
    final serverId = db.getServerConfig('server_id');
    final publicKeyBase64 = db.getServerConfig('server_public_key');
    final privateKeyBase64 = db.getServerConfig('server_private_key');

    final String resolvedServerId;
    final crypto.SimpleKeyPair keyPair;
    if (serverId != null && publicKeyBase64 != null && privateKeyBase64 != null) {
      final pubBytes = base64Decode(publicKeyBase64);
      final privBytes = base64Decode(privateKeyBase64);
      keyPair = crypto.SimpleKeyPairData(
        privBytes,
        publicKey: crypto.SimplePublicKey(pubBytes, type: crypto.KeyPairType.ed25519),
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
      db.setServerConfig('server_private_key', base64Encode(newPrivateKeyBytes));
      keyPair = newKeyPair;
    }

    // Admin token generation is intentionally independent of server identity
    // (above): it fires whenever no token hash is on record, regardless of
    // whether the server identity itself is new or pre-existing. This lets
    // an operator who lost their token recover by clearing just
    // 'admin_token_hash' (e.g. via bin/reset_admin_token.dart) without
    // regenerating the server's federation identity/keypair as a side
    // effect.
    String? generatedAdminToken;
    if (db.getServerConfig('admin_token_hash') == null) {
      final random = Random.secure();
      final tokenBytes = List<int>.generate(24, (i) => random.nextInt(256));
      generatedAdminToken = base64UrlEncodeNoPadding(tokenBytes);
      final hash = crypto_pkg.sha256.convert(utf8.encode(generatedAdminToken)).toString();
      db.setServerConfig('admin_token_hash', hash);
    }

    return ServerIdentity(
      serverId: resolvedServerId,
      serverKeyPair: keyPair,
      adminToken: generatedAdminToken,
    );
  }

  static String base64UrlEncodeNoPadding(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
