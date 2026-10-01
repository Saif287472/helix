# Cryptographic Design Review — Helix Remote E2EE Protocol

This document performs the formal cryptographic design review (P9-001) for Helix Remote. It details the cryptographic decisions and design specifications resolving tasks P9-002 through P9-018 and P9-023.

> Implementation status (2026-09): sections 2-9 describe the target design.
> Where the code differs:
>
> - **Ratchet (section 4):** `DoubleRatchetSession`
>   (`packages/helix_remote_crypto/lib/src/double_ratchet.dart`) implements the
>   symmetric chains, DH ratchet steps and skipped-message keys, and is used by
>   `app/lib/app/remote_messaging_service/message_crypto.dart`. The replay
>   window in section 6 is not verified, and there is no independent review, so
>   it must not be represented as Signal-equivalent.
> - **Identity (section 2):** the account identity key is one per account, not
>   per device. A device that signs in with the password holds the same key,
>   unwrapped from a password-wrapped copy on the server (section 9a).
> - **Signed prekeys (sections 2, 9):** the default signed-prekey TTL is 30 days
>   (`signedPrekeyTtl` in `packages/helix_remote_crypto/lib/src/prekey_manager.dart`),
>   not a 14-day background rotation.
> - **Linking (section 9, P9-007):** there is no QR-and-sign-by-`IK_A` step.
>   Linking uses a server-stored approval transcript signed by the new device,
>   a six-digit verification code and a 10-minute TTL
>   (`backend/lib/src/modules/auth/devices.dart`). A device can also be added
>   by password sign-in with no approval (section 9a).
> - **Revocation (section 9, P9-009, P9-018):** revocation is an authenticated
>   server call (bearer token of a sibling device: `/devices/revoke`,
>   `/devices/revoke-others`, `/devices/lost-device`), not a published
>   `IK_A`-signed proof.
> - **Attachments (section 8):** ciphertext is stored on the server's local
>   filesystem (`HELIX_REMOTE_ATTACHMENTS_DIR`), not S3.

---

## 1. Cryptographic Primitives (P9-002)
To build a secure, standard, and highly audited end-to-end encryption (E2EE) pipeline, we select the following primitives:
*   **Key Agreement (Diffie-Hellman)**: **X25519** (Curve25519 for DH).
*   **Signatures (Ed25519)**: **Ed25519** for signing prekey bundles, verifying linked devices, and validating sender chains.
*   **Symmetric Encryption**: **AES-256-GCM** (256-bit key, 96-bit nonce, 128-bit authentication tag) for payload encryption.
*   **Key Derivation Function (KDF)**: **HKDF-SHA256** (HMAC-based Key Derivation Function).
*   **Passphrase KDF (Database Backups)**: **Argon2id** (with high memory cost parameters) to derive keys from passphrases.

---

## 2. Key Hierarchy and Identifiers (P9-006)
Every client device maintains a distinct key hierarchy, stored securely inside the platform key storage.

1.  **Account Identity Key (`IK_A`) [Ed25519 Key Pair]**:
    *   Represents the user's master cryptographic identity.
    *   The public key is published to the keys directory on registration.
    *   Used to sign the device's identity keys and verify sibling devices during linking.
2.  **Device Identity Key (`IK_D`) [X25519 Key Pair]**:
    *   Represents the physical device's key agreement identity.
    *   Signed by the Account Identity Key (`IK_A`).
3.  **Signed Prekey (`SPK`) [X25519 Key Pair]**:
    *   A medium-term key pair rotated every 7 to 30 days.
    *   Signed by `IK_A` to prevent active man-in-the-middle (MITM) attacks.
4.  **One-Time Prekeys (`OPK`) [X25519 Key Pairs]**:
    *   A pool of one-time use key pairs.
    *   Uploaded to the server's key directory and consumed upon session establishment.

---

## 3. Session Establishment (P9-003, P9-005)
Helix Remote establishes direct sessions between devices asynchronously using the **X3DH (Extended Triple Diffie-Hellman)** protocol.

### Protocol Steps (Client Alice initiating session with Client Bob):
1.  Alice requests Bob's `PreKeyBundle` (containing Bob's identity key `IK_D_Bob`, signed prekey `SPK_Bob` with signature, and optionally a one-time prekey `OPK_Bob`) from the key directory.
2.  Alice verifies Bob's `SPK_Bob` signature against Bob's Account Identity Key `IK_A_Bob`.
3.  Alice generates an ephemeral key pair `EK_Alice` (X25519).
4.  Alice computes four Diffie-Hellman values:
    *   `DH1 = ECDH(IK_D_Alice, SPK_Bob)`
    *   `DH2 = ECDH(EK_Alice, IK_D_Bob)`
    *   `DH3 = ECDH(EK_Alice, SPK_Bob)`
    *   `DH4 = ECDH(EK_Alice, OPK_Bob)` (if `OPK` was returned; otherwise omitted)
5.  Alice computes the master shared secret `SK` using HKDF-SHA256:
    *   `SK = HKDF-Extract(salt = 0, IKM = DH1 || DH2 || DH3 [ || DH4 ])`
6.  Alice uses `SK` to initialize her local Double Ratchet session for Bob.
7.  Alice sends her ephemeral public key `EK_Alice` and the ID of Bob's consumed prekeys in the first encrypted message envelope so Bob can reconstruct `SK`.

---

## 4. Per-Message Ratchet (P9-004)
Once the X3DH session is initialized, Alice and Bob communicate using the **Double Ratchet Protocol**:

*   **KDF Chains (Symmetric Ratchet)**:
    *   The session maintains three KDF chains: a Root Chain, a Sending Chain, and a Receiving Chain.
    *   Each message sent ratchets the Sending Chain forward, deriving a unique symmetric Message Key (`MK`) and updating the chain key.
    *   Each message received ratchets the Receiving Chain forward, deriving the corresponding Message Key.
*   **Diffie-Hellman Ratchet (Asymmetric Ratchet)**:
    *   When receiving a new DH public key from the peer, the client ratchets the Root Chain, creating new Sending and Receiving chain keys, and instantiates a new DH ratchet key pair.
    *   This guarantees **Forward Secrecy** (compromise of current keys does not expose past messages) and **Post-Compromise Security** (the session heals itself automatically after a key compromise once a new DH exchange completes).

---

## 5. Metadata Visibility and Server Trust (P9-013, P9-023)
*   **No Server Plaintext**: The server stores only opaque ciphertexts. Plaintext content and private keys are never stored on the server (P9-023).
*   **Visible Metadata**:
    *   Event UUID, timestamp, and schema version.
    *   Sender account ID and sender device ID.
    *   Recipient device ID (needed for routing).
*   **Hidden Metadata**:
    *   Actual message content (decrypted client-side only).
    *   File names, dimensions, types, and encryption keys of attachments.
    *   Group names and participant identities are encrypted inside group envelopes.

---

## 6. Replay Protection & Duplicate Handling (P9-014, P9-015)
*   **Replay Protection**: The client tracks the list of active session identifiers and rejects incoming messages that reuse a sequence number or a timestamp that is older than the session's sliding sequence window (e.g. 1000 messages or 30 days).
*   **Out-of-Order Handling**: If a message arrives out of order, the client ratchets the symmetric chain key forward, derives the skipped Message Key, and stores it in a secure local database table `skipped_message_keys` (with a max lifetime of 30 days) to allow decryption when the skipped message eventually arrives.
*   **Idempotency**: Clients discard duplicate messages based on the envelope's unique `event_id`.

---

## 7. Group Encryption Strategy (P9-010)
To scale E2EE groups efficiently without expensive direct fanned-out pairwise messages for every text sent:
*   We use the **Sender Keys Protocol** (Signal Group Protocol).
*   When a group conversation is created, each participant generates a **Sender Key Chain** (consisting of a starting chain key and an X25519 signature key).
*   The participant distributes their Sender Key to all other group members individually using fanned-out 1:1 Double Ratchet channels.
*   When a member sends a message to the group:
    *   The member ratchets their own Sender Key symmetric chain, derives a Message Key, encrypts the payload using AES-256-GCM, and sends the ciphertext to the server.
    *   The server broadcasts the identical ciphertext payload to all group members.
    *   Members decrypt the message using the sender's previously shared Sender Key.
*   **Key Rotation (Membership Change)**: If a member leaves or is removed from the group, all active members rotate their Sender Keys. This ensures **Future Secrecy** (removed members cannot decrypt subsequent group messages).

---

## 8. Attachment and Backup Encryption (P9-011, P9-012)
*   **Attachment Encryption**:
    1.  The client generates a random 256-bit symmetric key (`K_file`) and a 96-bit IV (`IV_file`).
    2.  The client encrypts the file payload using AES-256-GCM.
    3.  The client uploads the encrypted ciphertext to S3 and receives an opaque file ID.
    4.  The file manifest (containing `file_id`, `K_file`, and `IV_file`) is encrypted inside the message payload and sent securely to recipients via the Double Ratchet channel.
*   **Backup Encryption**:
    *   Derived via the **Argon2id** KDF using the user's recovery passphrase and a secure salt.
    *   The derived 256-bit key is used to encrypt local database snapshots via AES-256-GCM before uploading to the server's backup storage. The server never receives the passphrase or the derived key.

---

## 9. Key Lifecycle, Revocation, and Security Events (P9-007, P9-008, P9-009, P9-016, P9-017, P9-018)
*   **Device Linking (P9-007)**: Adding a new device requires the primary device to scan a QR code containing the new device's public identity key, sign it using `IK_A`, and publish the new device descriptor to the directory.
*   **Key Change UX (P9-008)**: When a contact rotates their identity key (e.g. after reinstalling the app), the client prompts a warning: *"Bob's security keys have changed. Verify their fingerprint before sending sensitive data."*
*   **Device Revocation (P9-009)**: If Alice revokes one of her devices:
    *   She signs a revocation proof using `IK_A` and publishes it.
    *   Sibling and peer devices receive the revocation event, immediately delete all active Double Ratchet sessions with the revoked device, and rotate their group Sender Keys.
*   **Cryptographic Version Negotiation (P9-016)**: The X3DH header contains a protocol version byte. If the recipient does not support the version, it rejects the session setup with a `version_mismatch` error signal.
*   **Key Rotation (P9-017)**: Signed Prekeys are automatically rotated and re-signed every 14 days by a client background job.
*   **Lost Device Response (P9-018)**: If a device is lost, the user logs into another active device (or uses the offline recovery phrase) to push a revocation signature, invalidating the lost device's access tokens and session states.

---

## 9a. Password-Wrapped Account Identity Key (implemented 2026-09)

Every account has a password. The server never sees it.

1. The app runs **Argon2id** over the password with a per-account random salt
   and the server-provided cost (default m=19456 KiB, t=2, p=1, 64-byte output;
   the server refuses cheaper parameters) in a background isolate.
2. **HKDF-SHA256** splits the output into two independent keys:
   - `authKey`, sent to the server on sign-in, password verify and password
     change. The server stores only a salted SHA-256 of it (the Argon2id cost is
     already paid, so a stolen table still costs one Argon2id run per guess).
   - `wrapKey`, which never leaves the device.
3. `wrapKey` encrypts the account identity private key with **AES-256-GCM**,
   AAD bound to the identity public key. The ciphertext is stored server-side
   (`account_passwords.wrapped_identity_key`) and returned by
   `POST /api/v1/accounts/password/login`, so a new device that knows the
   password joins as the same account without replacing the other devices.
4. The sign-in request is signed with the new device's Ed25519 key over a
   transcript binding the device keys to the phone hash.
5. Online guessing is limited by a lockout: 5 failures lock for 15 minutes,
   doubling up to 24 hours, plus per-IP rate limits.
6. When the identity key rotates (SMS-OTP sign-in on Global, recovery) the
   wrapped copy and the history backup made under the old key are deleted.

The automatic text-history backup uses a key derived by HKDF from the identity
private key (info `helix.remote.history-backup.v1`), gzip and AES-GCM with AAD
bound to the identity public key.

Files: `backend/lib/src/modules/auth/password.dart`,
`app/lib/app/password_vault.dart`,
`app/lib/app/composition_root/password_auth.dart`,
`app/lib/app/history_backup_codec.dart`.

---

## 10. Phone Discovery Hashing (Contacts Sync)

Added with the phone identity/invite/contacts-sync overhaul. This is a
**separate primitive with a separate purpose** from everything above - it
exists to let the server answer "is this phone number a registered account?"
without ever learning the plaintext number, not to protect message content.
It must not be conflated with the E2EE session cryptography in sections 1-9,
and does not itself provide forward secrecy, deniability, or any Double
Ratchet property; it is a keyed lookup hash, nothing more.

*   **Primitive**: `HMAC-SHA256`, keyed by a per-deployment 32-byte random
    salt (`crypto.Hmac(crypto.sha256, saltBytes)` from the already-imported
    `crypto` package - no new cryptographic primitive was introduced for
    this, per the project's existing preference against adding cryptographic
    surface area unnecessarily).
*   **Discovery salt generation and distribution**: Each server self-heals
    its salt on first request to `GET /contacts/discovery-salt` (CSPRNG,
    32 bytes, persisted via the existing `server_configuration` key-value
    store) and never rotates it afterward - rotating would silently
    invalidate every phone-hash match already made by every client. The
    endpoint is intentionally unauthenticated: signup itself needs the salt
    before an account or session exists.
*   **Computation**: `phoneHash(saltBase64, e164Number) = hex(HMAC-SHA256(salt, utf8(e164Number)))`,
    implemented identically in `backend/lib/src/phone_hash.dart` and
    `app/lib/app/phone_hashing.dart`. Byte-for-byte parity between the two is
    load-bearing - a divergence would silently break every phone-hash
    comparison (signup, login, and contacts matching alike) - and is pinned
    by a shared known-answer test vector.
*   **Where it is used**: phone-number-based account identity at
    registration (`phone_hash` is the account's permanent identifier - there
    is no plaintext username, and no change-number flow), and the contacts-
    sync matching lookup (`POST /contacts/match`).
*   **Accepted, documented limitation**: a per-server salt does not stop an
    attacker who can call the salt endpoint from precomputing a table against
    the roughly 10^10 E.164 keyspace for a given country code and then
    querying `/contacts/match` (authenticated, rate-limited, batch-capped) to
    test candidates. This is the same limitation pre-enclave Signal had. It
    is tracked as an accepted risk, not a defect - see
    `docs/product/THREAT_MODEL.md` T-5, and note this is explicitly a
    property of hash-based contact discovery in general, not something a
    different HMAC construction would fix.
*   **Federation note**: cross-server contact matching between two federated
    Helix Remote servers is out of scope by construction - each server has an
    independent salt, so a hash computed for one server is meaningless on
    another.

## 11. v2 client crypto (Phase C2, 2026-10-02) - internal review note

**Not externally reviewed.** This note is the author's own review, required
by ARCHITECTURE_V2_PLAN.md §5. Nothing in v2 may be described as externally
reviewed or Signal-equivalent until an independent review happens (ADR-028).

- **Scope:** `packages/helix_remote_crypto/lib/v2.dart` implements
  `docs/protocol/v2/CRYPTO_V2.md`. The v1 code above is unchanged and stays
  in use until cutover.
- **What changed from v1:**
  - Full Double Ratchet with DH steps (post-compromise security), with
    `MAX_SKIP` 1,000 per chain, 2,000 stored keys per session and a 30-day
    expiry.
  - Sessions per device pair, not per conversation.
  - Device certificates under the AIK, checked before any DH. SPK
    signatures under the DSK. No fallback to "the last SPK".
  - Sender Keys with a per-message Ed25519 signature, rotation on removal or
    device change, and one ciphertext per group message.
  - Attachment STREAM with an authenticated header and a last-chunk flag.
  - AAD on every backup AEAD.
  - A working provisioning message for device linking.
- **Invariants and tests (`test/v2/`):**
  - Decrypt-before-commit: operations are pure and return state only after
    the AEAD tag (and, for groups, the signature) verifies. Tests check
    that a failure leaves the stored bytes unchanged.
  - Replay of messages and of prekey messages is rejected, including
    no-OPK prekey messages after their session was dropped.
  - Tampered header, ciphertext or AD are rejected; wrong identities
    (certificate, SPK signature, DIK mismatch, unknown device) are refused.
  - Skip caps and eviction are enforced; previous sessions are capped at 5.
  - §13a reset and simultaneous initiation converge; sender-key rotation
    behaves as specified.
  - Known-answer tests against RFC 5869, RFC 7748 and RFC 8032.
  - Byte layouts are rebuilt by hand from CRYPTO_V2.md and compared with the
    implementation.
  - Golden vectors are regenerated and also consumed from the files.
- **Spec deviation found:** CRYPTO_V2.md §9 derived the group-state and
  profile-blob nonce from the key, which would repeat the GCM nonce across
  versions. A random nonce is implemented instead (CRYPTO_V2.md §14,
  proposed change-log entry).
- **Residual risks:**
  - Pure-Dart primitives from `package:cryptography` (not constant-time
    audited).
  - No header encryption or sealed sender (by design in v2.0).
  - The server can roll group state back within an epoch.
  - X3DH without an OPK is replayable at the X3DH level; this is mitigated
    by remembered base keys and envelope de-duplication.
  - Passwords are not Unicode-normalised.
