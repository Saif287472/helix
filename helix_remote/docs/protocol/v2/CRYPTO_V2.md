# Helix Remote v2 — Cryptographic Protocol

Status: **specified 2026-10-01 (Phase P1), pending user review.** Not externally
reviewed; nothing here may be described as externally reviewed until a review
happens (ADR-028). Implemented in Phase C2 (`helix_remote_crypto`) with test
vectors; deviations found during implementation are recorded in §14.

This replaces, for v2, the client crypto described in
`docs/security/remote_cryptographic_design_review.md`. v1 findings that drove
the changes (2026-10-01 survey): the app performs only symmetric chain steps
(no DH ratchet → no post-compromise security); sessions are keyed per
conversation; group messages are encrypted pairwise; group epoch keys encrypt
nothing; edits, poll votes, RSVPs and live-location updates are encrypted with
the *sender's own local* key so recipients cannot read them; reactions,
receipts, typing, `view_once` and retention deadlines reach the server in
plaintext; no SPK rotation, no OTK top-up, no check that a device key belongs
to its account.

## 1. Primitives

| Use | Primitive |
|---|---|
| Diffie-Hellman | X25519 |
| Signatures | Ed25519 |
| KDF | HKDF-SHA256 (RFC 5869) |
| Chain KDF / MAC | HMAC-SHA256 |
| AEAD | AES-256-GCM, 96-bit nonce, 128-bit tag |
| Hash | SHA-256, SHA-512 (safety numbers) |
| Password KDF | Argon2id |
| Randomness | OS CSPRNG (`Random.secure`) |

All available in `package:cryptography` (already a dependency). Every HKDF
`info` string starts with `helix.v2.` so v2 keys can never collide with v1
derivations. `‖` is byte concatenation; `u32(x)`/`u64(x)` are big-endian.

## 2. Keys and identities

| Key | Type | Where | Lifetime |
|---|---|---|---|
| **AIK** account identity key | Ed25519 | every device of the account; a password-wrapped copy on the server (§11) | until rotation (SMS takeover on Helix Global, recovery redeem) |
| **DIK** device identity key | X25519 | one device | the device's life |
| **DSK** device signing key | Ed25519 | one device | the device's life |
| **SPK** signed prekey | X25519 | one device; public part on server | rotated every 7 days; private kept 30 days after rotation |
| **OPK** one-time prekeys | X25519 | one device; public parts on server | single use; private deleted after first use |

**Device certificate.** Binds a device to its account (closes the v1 gap where
nothing proved a device key belonged to the account):

```
cert_body = "helix.v2.device-cert" ‖ u8(1) ‖ account_id(16) ‖ device_id(16)
            ‖ DIK_pub(32) ‖ DSK_pub(32) ‖ u64(created_at_ms)
cert      = Ed25519.sign(AIK, cert_body)
```

(ids are the 16 raw UUID bytes.) Every prekey bundle carries the certificate.
A client accepts a device only if the certificate verifies under the AIK it
has for that account. **SPK signature:** `Ed25519.sign(DSK, "helix.v2.spk" ‖
u32(spk_id) ‖ SPK_pub)`.

**AIK pinning.** The first AIK seen for an account is pinned (trust on first
use). A different AIK later is a **key change**: the client stops using old
sessions, shows "Safety number changed" in every conversation with that
account, and resets its verified flag (§10). The server keeps no record of
who talks to whom, so it cannot announce key changes to contacts. Clients
detect them when a bundle's AIK differs from the pinned one, or when a
prekey message arrives whose device certificate verifies only under a new
AIK. (`key_change` envelopes are reserved for the account's own devices.)

## 2a. Device linking (provisioning)

v1's QR linking could not complete (the new device was never given the
transcript it had to sign). v2 uses a provisioning message, as Signal does:

1. The new device creates an ephemeral X25519 key pair `E_new`, calls
   `POST /v1/auth/links` with `E_new.pub`, and shows a QR code:
   `helix-link:1:<server origin>:<link_id>:<b64url(E_new.pub)>`. The
   `poll_token` it receives is kept private.
2. A signed-in device scans the code, asks the user to confirm, and seals a
   provisioning message to `E_new.pub`:
   ```
   E_old   = fresh X25519 key pair
   k       = HKDF(ikm = X25519(E_old, E_new.pub), salt = 0x00*32,
                  info = "helix.v2.provision", len = 44)   -> aes_key, nonce
   sealed  = E_old.pub(32) ‖ AES-256-GCM(aes_key, nonce, provision_json,
                                          aad = "helix.v2.provision" ‖ link_id)
   provision_json = {"account_id", "identity_key_private" (AIK seed, 32 B),
                     "identity_key", "profile_key", "approver_device_id"}
   ```
   and posts it to `POST /v1/devices/links/{link_id}/approve`.
3. The new device long-polls `GET /v1/auth/links/{link_id}` (bearer
   `poll_token`), opens the provisioning message, generates its DIK/DSK,
   signs its certificate with the AIK, and calls `POST /v1/auth/devices`
   with the single-use `link_token`.

The server relays the sealed message but cannot read it. Links expire after
10 minutes. Every other device gets an `account_signal` (`new_sign_in`).

## 3. Prekeys

- Registration and device linking publish: SPK + 100 OPKs.
- The server hands out at most one OPK per bundle fetch and deletes it; when
  a device has fewer than 20 OPKs left it receives a `prekeys_low` envelope
  and uploads 100 more. With no OPKs left, bundles carry only the SPK (X3DH
  without DH4 — still secure, less replay-resistant).
- SPK rotates every 7 days (client-driven, on app start or in background);
  the previous SPK private key is kept 30 days for in-flight prekey messages,
  then deleted. A prekey message naming an unknown SPK id is rejected (no v1
  fallback to "the last SPK").

## 4. X3DH session setup (per device pair)

Alice's device A starts a session with Bob's device B from B's bundle
(certificate verified, SPK signature verified first):

```
EK   = fresh X25519 key pair
DH1  = X25519(DIK_A, SPK_B)
DH2  = X25519(EK,    DIK_B)
DH3  = X25519(EK,    SPK_B)
DH4  = X25519(EK,    OPK_B)            (only if an OPK was provided)
SK   = HKDF(ikm = 0xFF*32 ‖ DH1 ‖ DH2 ‖ DH3 [‖ DH4],
            salt = 0x00*32, info = "helix.v2.x3dh", len = 32)
AD   = "helix.v2.ad" ‖ account_A(16) ‖ device_A(16) ‖ DIK_A_pub
                     ‖ account_B(16) ‖ device_B(16) ‖ DIK_B_pub
```

`SK` seeds the Double Ratchet (§5) with B's SPK as Bob's initial ratchet key,
exactly as in the Signal Double Ratchet specification. **A session belongs to
the device pair (A, B), not to a conversation:** the conversation travels
inside the encrypted content (CONTENT_V2.md). One session therefore carries
direct messages, group sender-key distributions, receipts, typing and call
signals between those two devices.

## 5. Double Ratchet (full, with DH steps)

Follows the Signal Double Ratchet specification with these instantiations:

```
KDF_RK(rk, dh_out) = HKDF(ikm = dh_out, salt = rk, info = "helix.v2.ratchet.root", len = 64)
                     -> (rk' = out[0:32], ck = out[32:64])
KDF_CK(ck)         -> mk  = HMAC-SHA256(ck, 0x01)
                      ck' = HMAC-SHA256(ck, 0x02)
message key        -> HKDF(ikm = mk, salt = 0x00*32, info = "helix.v2.message", len = 44)
                      aes_key = [0:32], nonce = [32:44]
header             =  { dh: ratchet public key (32), pn: u32, n: u32 }
ciphertext         =  AES-256-GCM(aes_key, nonce, plaintext,
                                  aad = AD ‖ header_bytes)
header_bytes       =  "helix.v2.hdr" ‖ dh(32) ‖ u32(pn) ‖ u32(n)
```

- A new ratchet key pair is generated each time the sending side turns
  (standard DH ratchet), giving post-compromise security.
- **Skipped keys:** at most 1,000 skipped per chain step (`MAX_SKIP`), at
  most 2,000 stored per session (oldest evicted), each discarded after 30
  days. A message whose key was already used or evicted is rejected
  (replay protection).
- **Simultaneous initiation:** each peer device keeps one *active* session
  and up to 5 *previous* sessions. Decryption tries the active one, then the
  previous ones; a successfully decrypted prekey message creates a new active
  session. Sending always uses the active session.
- State is committed only after the AEAD tag verifies (decrypt-before-commit,
  kept from v1 Phase 9).
- Header encryption is not used in v2.0 (headers are inside the sealed
  pairwise payload, which only the two devices and the server's routing see;
  the server sees no header fields — see §8).

## 6. Plaintext padding

Before encryption every plaintext is padded: `content_bytes ‖ 0x80 ‖ 0x00…`
to the next multiple of 160 bytes. Receivers strip from the last `0x80`.
Hides exact message lengths from the server.

## 7. Sender Keys (groups)

Each sending device keeps, per group, a **sender key** identified by a random
`dist_id` (UUID):

```
state       = { dist_id, iteration: u32, chain_key: 32 bytes, signing: Ed25519 key pair }
step        : mk = HMAC-SHA256(chain_key, 0x01); chain_key' = HMAC-SHA256(chain_key, 0x02); iteration += 1
message key : HKDF(ikm = mk, salt = 0x00*32, info = "helix.v2.sender-key", len = 44) -> aes_key, nonce
ciphertext  : AES-256-GCM(aes_key, nonce, padded_plaintext,
                          aad = "helix.v2.sk" ‖ group_id(16) ‖ dist_id(16) ‖ u32(iteration))
signature   : Ed25519.sign(signing_priv, "helix.v2.sk-sig" ‖ group_id ‖ dist_id ‖ u32(iteration) ‖ ciphertext)
```

- **Distribution:** a `sender_key_distribution` content message
  (`{group_id, dist_id, iteration, chain_key, signing_pub}`) sent over the
  pairwise sessions (§4–5) to every member device that does not have the
  current sender key. The client tracks which devices have it.
- **Sending:** one ciphertext per group message, posted once; the server fans
  it out to every member device (`group_message` envelope). Devices that
  still lack the key get the distribution in the same request (§8).
- **Receivers** keep each sender's key per `(account, device, dist_id)`;
  forward skip up to 2,000 iterations; old message keys cached up to 2,000
  per sender, 30 days.
- **Rotation:** a new `dist_id` (fresh chain key and signing key) whenever a
  member is removed or leaves, a member's device is revoked, or the sender's
  own device list changes; and at the latest every 7 days or 10,000
  messages. Adding a member does not rotate: the new member receives the
  current key at the current iteration and cannot read earlier messages.
- `GroupCryptoProtocol` is the engine's interface for this, so MLS can be
  added later without touching callers.

## 8. What the server sees

Pairwise messages travel as `SealedMessage` (the mailbox payload, opaque to
the server):

```json
{"v":2,"t":"prekey", "dik":"…","ek":"…","spk":12,"opk":345,"h":{"dh":"…","pn":0,"n":0},"ct":"…"}
{"v":2,"t":"ratchet","h":{"dh":"…","pn":3,"n":7},"ct":"…"}
```

Group messages travel as `SenderKeyMessage`:

```json
{"v":2,"t":"sender_key","dist":"<uuid>","it":42,"ct":"…","sig":"…"}
```

The server routes these by recipient device and never parses them. Server
knowledge per message: sender account and device, recipient devices (or group
id), size (padded), time. **Not** visible to the server (unlike v1): content
type, reactions, receipts, edits, deletes, typing, view-once, disappearing
timers, replies, group names, avatars or descriptions. Sealed sender (hiding
the sender from the server) is reserved for a later version: `Envelope.from`
is optional in the wire format for that reason.

## 9. Group state, profile keys

- **Group master key (GMK):** 32 random bytes per group *epoch*. Encrypts the
  group state blob stored on the server (`name`, `description`, `avatar`
  pointer, display settings): `AES-256-GCM(HKDF(GMK, info="helix.v2.group-state",
  len=44), state_json, aad = "helix.v2.gs" ‖ group_id ‖ u32(epoch))`. Shared
  pairwise in `group_key` content when a member joins; a new epoch and GMK on
  removal or leave. The server knows the roster and roles (it enforces them)
  but not the group's name or picture.
- **Profile key:** 32 random bytes per account. Encrypts the account's
  profile blob on the server (display name, about, avatar pointer) the same
  way with info `helix.v2.profile`, aad `"helix.v2.pf" ‖ account_id ‖
  u32(version)`. Shared with everyone the account messages, inside content
  (`profile_key` field). Rotated when the account blocks someone.

## 10. Safety numbers

Per pair of accounts, from each account's AIK:

```
h_0                  = SHA-512(u16(0) ‖ AIK_pub ‖ account_id(16))
h_(i+1)              = SHA-512(h_i ‖ AIK_pub)              for i = 0 … 5,199
digits(account)      = first 30 bytes of h_5200 -> six 5-byte chunks
                       -> each as u40 mod 100000, zero-padded to 5 digits
safety number        = digits of the lower account id first, then the other: 60 digits
```

Shown as 12 groups of 5 digits plus a QR code. Scanning compares both halves.
A changed AIK changes the number (§2 key change). Device additions do not:
devices are vouched for by the AIK certificate.

## 11. Passwords and the password-wrapped identity key (kept from v1 F1 §9a)

- Password KDF: Argon2id, m = 19,456 KiB, t = 2, p = 1, 64-byte output, salt
  from the server's `password params` (per account). Then
  `auth_key = HKDF(out, info="helix.v2.password.auth", 32)` and
  `wrap_key = HKDF(out, info="helix.v2.password.wrap", 32)`.
- **Only `auth_key` is ever sent** (the password never leaves the device).
  The server stores a hash of `auth_key` (Argon2id with a server-side salt),
  locks out after 5 failures for 15 minutes, doubling to 24 hours.
- `wrapped_aik = AES-256-GCM(wrap_key, AIK_priv, aad = "helix.v2.wrapped-aik" ‖ account_id)`
  is stored on the server so password sign-in on a new device needs no other
  device (T-4 in the threat model, unchanged).

## 12. Attachments

- Per attachment: random 32-byte key; encrypted with AES-256-GCM in the
  **STREAM** construction (64 KiB chunks; nonce = 7-byte random prefix ‖
  u32(counter) ‖ u8(is_last)); AAD per chunk = file header ‖ u32(counter) ‖
  u8(is_last). The header (magic `HXS2`, version, chunk size, nonce prefix)
  is authenticated, and the last chunk is flagged, closing both v1 gaps
  (unauthenticated header, truncation detected only by length). This is the
  existing, unused `RemoteAttachmentCrypto` STREAM format, re-versioned.
- `digest = SHA-256(ciphertext)` goes in the encrypted pointer and is checked
  on download.
- The server object id is a random UUID, **not** the ciphertext hash (v1 was
  content-addressed, which lets the server link identical uploads), and the
  server does not learn which message references an object (no v1
  `register-reference`). Objects expire 30 days after upload (§ mailbox TTL).
- Thumbnails: an inline `blurhash` plus an optional separately encrypted
  thumbnail object.

## 13. Backups

Kept from v1 F2 with one fix: every AES-GCM operation gains AAD
(`"helix.v2.backup" ‖ backup_id ‖ u32(version)`). Envelope v3 otherwise
matches F2 (Argon2id m=8192 KiB t=2 p=1 for recovery secrets; random backup
key wrapped by recovery secret and platform credential). The automatic
history backup keeps its key derivation from the AIK (`HKDF(AIK_priv,
info="helix.v2.history-backup")`) and is deleted when the AIK rotates.
Session and prekey private state is never backed up; after a restore, peers'
first messages fail to decrypt and trigger §13a.

### 13a. Decryption failure and session reset

A device that cannot decrypt a pairwise message (unknown session, evicted
key) sends a `decryption_error` content message to the sender device over a
**new** session (fresh X3DH), naming the message id. The sender, if the
message is under 24 hours old, re-sends it over the new session. The
receiver shows a "waiting for this message" placeholder meanwhile.

## 14. Implementation notes and deviations

(Filled in during Phase C2.)
