# Cryptographic Design Review — Helix Remote E2EE Protocol

This document performs the formal cryptographic design review (P9-001) for Helix Remote. It details the cryptographic decisions and design specifications resolving tasks P9-002 through P9-018 and P9-023.

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
