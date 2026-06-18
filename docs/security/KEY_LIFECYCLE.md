# Key Lifecycle

> **Status:** Finalized — Stage 5 review.

## Key Types

| Key | Algorithm | Lifetime | Storage |
|---|---|---|---|
| Static identity key pair | RSA (current) | App lifetime; reset on identity reset | Private key in flutter_secure_storage; public key in TLS cert |
| Session pairing key | Argon2id(secret_sentence, salt) | Single pairing session | RAM only; never persisted |
| TLS session keys | Negotiated by platform TLS stack | TLS connection lifetime | Managed by platform; not directly accessible |
| Chain key / ratchet state | HKDF-SHA256 | Per-message; ratchets forward | RAM; zeroed on channel close |
| Group shared key | Derived from group state (TBD) | Group session | RAM only |

## Generation

- Identity key pairs are generated locally on first run using the platform's secure random source.
- Session pairing keys are derived from the user-supplied secret sentence using Argon2id with a fresh random salt per pairing session.
- Chain keys are derived during channel establishment using HKDF-SHA256.

## Storage

| Material | Where | Protection |
|---|---|---|
| RSA private key | flutter_secure_storage | Android Keystore / iOS Secure Enclave / Windows DPAPI |
| RSA public key fingerprint | SQLite peers_cache (trust decisions) | Integrity only; not confidential |
| Trust records | flutter_secure_storage | Same as private key |
| Session ID | flutter_secure_storage | Persisted across app restarts for reconnect |
| Secret sentence | flutter_secure_storage (during setup only) | Cleared after identity is established |

Private keys and session keys must **never** appear in:
- Application logs or diagnostics output
- Riverpod state
- App domain models
- Network frames (beyond the TLS-required public key in the certificate)

## Derivation

The current derivation chain is:

```
secret_sentence + random_salt
        │
        ▼ Argon2id (time=3, memory=64 MB, parallelism=1)
        │
pairing_key (32 bytes)
        │
        ▼ HKDF-SHA256 with session context
        │
chain_key → per-message_key (ratchets forward with each message)
```

**Open item:** The pairing_key above is derived from a *secret* sentence. However, the channel setup also uses the static RSA public keys (which are public). An explicit DH or ECDH step is needed to produce a shared secret that a passive observer cannot reproduce. This must be verified and documented before forward-secrecy claims.

## Rotation

- **Identity reset:** Generates a new RSA key pair; old fingerprint trust records and sessions are invalidated.
- **Session reconnect:** A new chain key is derived; the previous channel's key material is not reused.
- **Automatic rotation:** Not yet designed.

## Erasure (Dart Runtime Limitations)

Dart is a garbage-collected managed runtime. Absolute zeroization of secret material cannot always be guaranteed.

Best-effort policy:
- Keep secret material in mutable `Uint8List` buffers; zero the buffer before releasing the reference.
- Avoid immutable `String` representations for key material.
- Minimize copies and object lifetime.
- Use platform secure storage for long-lived keys.
- Document every location where guaranteed zeroization is not technically possible.

Current zeroing points:
- Chain key material: zeroed in `session_key_derivation.dart` after derivation.
- Pairing key: lives in Argon2 call stack only; not stored.
- Private key bytes: only ever in flutter_secure_storage; never in app heap as `Uint8List`.

## Wipe Behavior

| Operation | What Is Cleared |
|---|---|
| Thread wipe | In-memory thread messages and chat state for that thread |
| Application wipe | All threads, sessions, media cache, trust records in RAM |
| Identity reset | All of the above + platform secure storage (identity, secret sentence, trust records, session ID) |
| 5-minute auto-wipe | In-memory content of a single disconnected thread |

Ephemeral message content is **never** written to SQLite; wipe of in-memory state is sufficient.
