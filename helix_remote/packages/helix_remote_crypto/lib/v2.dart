/// Helix Remote v2 client cryptography (docs/protocol/v2/CRYPTO_V2.md).
///
/// Pure Dart on `package:cryptography` and `package:crypto`; no Flutter, no
/// `dart:io`, no storage. State is plain data that `helix_remote_db` stores
/// and the engine commits. Not externally reviewed (ADR-028).
///
/// The v1 API (`helix_remote_crypto.dart`) is separate and unchanged until
/// cutover.
library;

export 'src/v2/attachments.dart';
export 'src/v2/backup.dart';
export 'src/v2/blobs.dart';
export 'src/v2/errors.dart';
export 'src/v2/group_protocol.dart';
export 'src/v2/identity.dart';
export 'src/v2/password.dart';
export 'src/v2/prekeys.dart';
export 'src/v2/primitives.dart'
    show
        Aead,
        AeadKey,
        CryptoRandom,
        Ed25519KeyPair,
        SecureCryptoRandom,
        X25519KeyPair,
        bytesEqual,
        ed25519Verify;
export 'src/v2/provisioning.dart';
export 'src/v2/ratchet.dart';
export 'src/v2/safety_number.dart';
export 'src/v2/sender_keys.dart';
export 'src/v2/session.dart';
export 'src/v2/x3dh.dart';
