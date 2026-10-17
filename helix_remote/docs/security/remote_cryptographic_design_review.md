# Cryptographic Design Review — Helix Remote E2EE Protocol

This document performs the formal cryptographic design review (P9-001) for Helix Remote. It details the cryptographic decisions and design specifications resolving tasks P9-002 through P9-018 and P9-023.

> **Status at Phase X (2026-10): sections 1-10 are the v1 design review, kept as
> design history.** They describe the v1 implementation (per-conversation
> sessions, symmetric-only ratchet steps in the app, `helix_remote_storage`,
> `double_ratchet.dart`, the SQLite backend), which was deleted at the cutover
> (last v1 commit: tag `v1-final`); the file paths they name no longer exist.
> The current implementation is v2: read **section 11** (the v2 client crypto
> note) and **"Independent review pass, 2026-10-05"** at the end, and the
> specification in `docs/protocol/v2/CRYPTO_V2.md`. Nothing here, v1 or v2, has
> been externally reviewed.

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
  `docs/protocol/v2/CRYPTO_V2.md`. The v1 code described above was deleted at
  Phase X; v2 is the only crypto in the repository.
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

## 12. State commit discipline across engines (2026-10-09, review C-01)

**Not externally reviewed.** This is the author's own note on a defect the
2026-10-09 review found and the change in that batch fixed; it is added here
because a reviewer should look at it, not because anyone has.

- **What was wrong.** The per-message ratchet invariant "commit the state
  before the ciphertext leaves" was only enforced *within* one engine. The app
  and its FCM background isolate are two engines over the same SQLCipher file,
  and nothing stopped both from reading the same session state, encrypting and
  committing. The lease between them is advisory (its own comment says so), and
  its heartbeat rewrote the lease file every five seconds **without checking
  who owned it**, so an app Android had frozen past the lease's 20 seconds
  would wake up and stomp the push isolate's claim.
- **Why it matters more than a lost update.** Two sends taken from the same
  sending chain state produce the *same* message key and the same AES-GCM
  nonce. Both ciphertexts are delivered, so their plaintexts XOR to each other,
  and the GHASH authentication key for that message key is recovered. That is a
  confidentiality break, not just a broken conversation; a later message on the
  ratchet also fails, which is what triggers the §13a resets.
- **What is now in place.** `sessions` carries a `version` per device pair and
  every session write is a compare-and-set on it (`CryptoDao.saveSessions`
  returns false and changes nothing if the stored revision moved;
  `DbSessionStore.save` raises `StaleSessionState`). The engine retries from
  what the winning engine committed, inside the per-device lock
  (`PairwiseCrypto.locked`, `staleAttempts` = 3); nothing is encrypted from a
  state the store has already rejected. Two supporting details matter and are
  easy to undo by accident: a cleared record is written as an empty one-slot
  record rather than deleted (otherwise the revision resets and the next write
  is un-comparable), and every connection sets a 5 s `busy_timeout` (SQLite's
  default of zero fails the second writer before the compare-and-set is even
  reached). On the app side the lease heartbeat checks the file before
  rewriting it: another engine's claim ends this engine's claim, stops its
  engine, and makes the app open a new runtime that takes the lease back.
- **Group sender keys (schema 4, the same day).** The same key/nonce reuse
  existed one layer up: two engines could send a group message from one
  sender-key iteration. `sender_keys` now carries a `version` too, and this
  device's own sending key is saved by compare-and-set
  (`CryptoDao.saveOwnSenderKey`). `DbSenderKeyStore.ownKey` remembers the
  revision it read, a refused commit raises `StaleSenderKeyState` before
  anything is sent, and `GroupMessageSender` encrypts again from the stored
  key (`staleAttempts`). Every own-key read and write happens under the
  group's send lock, so the remembered revision belongs to the write that
  follows it. Keys received from other devices keep revision 0 and save
  last-writer-wins: receiving never encrypts, so a lost update costs at most a
  re-derived key. No crypto code or vector changed: the revision lives in the
  engine's store, not in `SenderKeyState`
  (`packages/helix_remote_engine/test/two_engines_test.dart`, the two group
  tests).
- **Bookkeeping, not state.** `DeviceSessions.version` is
  storage bookkeeping: it is carried through the record's transformations and
  is **not** part of the encoded state, so no test vector changed with it
  (`test/v2/session_test.dart`, "the store revision travels with the record but
  is not stored state").
- **Where to look.** `packages/helix_remote_db/lib/src/daos/crypto_dao.dart`
  (the compare-and-set), `packages/helix_remote_engine/lib/src/crypto/db_stores.dart`
  and `pairwise_crypto.dart` (the refusal and the retry),
  `app/lib/core/platform/engine_lease.dart` (the ownership check), and
  `packages/helix_remote_engine/test/two_engines_test.dart` (two engines on one
  database file).

## 13. One-time prekey hand-out (2026-10-10, review A-12)

**Not externally reviewed.** Server behaviour, no crypto code or vector
changed. Bundle fetches used to share one 600-an-hour bucket per target
account, so five accounts could keep it empty and nobody new could start a
session with the victim. The shared bucket is gone for local fetches (other
servers' fetches keep it); the limit is per (requesting account, target), 20
an hour. To keep one-time prekeys from being drained without that bucket, a
requesting account gets at most one OPK per target device an hour
(`keys:otk:` markers in the ephemeral store, `KeysModule.oneTimePrekeyGap`);
later bundles carry the signed prekey only, and the session starts without
DH4 (CRYPTO_V2 §3). The cost is that a second session from the same account
within the hour (a reset, another of its devices) has no one-time prekey,
which weakens replay resistance of its first message, not its secrecy.
`test/modules/server_hardening_test.dart` covers it.

## 14. Reported phone numbers at rest (2026-10-14, ADR-030)

**Not externally reviewed.** Server-side storage, not end-to-end crypto; no
client crypto changed. An app reports its account's own number; the server
takes it only when `HMAC(HELIX_PHONE_PEPPER, number)` equals the stored phone
hash (constant-time compare), then seals it with AES-256-GCM
(`package:cryptography`, random 96-bit nonce, 128-bit tag) under
`HELIX_PHONE_KEY`, a 32-byte secret kept outside the database, with
`"helix.v2.phone-number\n" + account id` as associated data, so a sealed
number copied to another account's row does not open. Stored as nonce ‖
ciphertext ‖ tag in `identity.accounts.phone_sealed`; the admin console and
the account's export open it. There is one key and no key id: rotating it
leaves old rows unreadable until apps report again. `server/test/modules/
phone_seal_test.dart` covers the round trip, the account binding,
tampering and a wrong key. Display names are sent in the clear by design
(ADR-030) and involve no crypto.

## Independent review pass, 2026-10-05

An independent, read-only review of the v2 client crypto and engine was done
and its confirmed findings were fixed in the commit `fix(client): v2 security
review pass - crypto and engine`: re-send requests answered to anyone (high);
crafted numbers in content stalling the inbound queue, deleted keys left in
the database file, server-driven group state and membership, device linking
without confirmation (medium); reserved kinds from peers, weak KDF and
recovery-secret floors, unbounded response bodies (low). What changed, the
test behind each fix and what stays open (signed membership changes,
key-change handling, forced-reset replay, retired base-key cap, HTTPS
enforcement, group key planting, server-trusted roles) is in CRYPTO_V2.md
section 14 ("Independent review pass") and the MODULE.md of the engine, db
and api packages. **This is still not an external review**: the design and
code have not been audited by a third party, and nothing here should be read
as a claim that they have. The residual risk "the server can roll group state
back within an epoch" above is closed by binding the state version into the
blob's AAD; a hostile server can still forge the attribution of a membership
change.
