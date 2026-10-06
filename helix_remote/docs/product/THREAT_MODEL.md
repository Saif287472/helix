# Helix Remote Threat Model

Status: rewritten at Phase X (2026-10) for the v2 architecture (ADR-025 to ADR-029).
The mechanisms are described in `docs/protocol/v2/` (REST, realtime, content, crypto,
metadata). The cryptography has **not been externally reviewed**
(`docs/security/EXTERNAL_SECURITY_REVIEW_GATE.md`).

## 1. Trust assumptions
- The server is assumed untrusted for content. Message privacy must not depend on server
  integrity: it holds ciphertext envelopes and public keys, never a key that opens them.
- Object storage (encrypted blobs on the server's local disk, or an S3-compatible store)
  is assumed untrusted.
- Transport (HTTPS and the WebSocket) is encrypted, but routing metadata is exposed to the
  server and to whoever can watch its network (`docs/protocol/v2/METADATA_V2.md`).
- The operator of a server is trusted with availability and with the account directory, not
  with content. A malicious operator can drop or delay messages, and can refuse service.
- A device is trusted with everything on it. SQLCipher and the app lock protect a lost,
  locked phone; they do not protect a phone that is unlocked and in the attacker's hands.

## 2. Threat scopes and mitigations

### T-1: Untrusted server
- **Description**: A compromised or malicious server operator tries to read conversations,
  or to swap a user's keys to read future ones.
- **Mitigation**: End-to-end encryption: one session per (local device, remote device) with
  X3DH and a full Double Ratchet (forward secrecy and post-compromise security), Sender Keys
  for groups. Every device key is certified by the account identity key (AIK); a changed AIK
  is announced in the chat and resets "verified", and safety numbers can be compared out of
  band. Edits, reactions, receipts, deletes, typing, view-once state and timers are inside the
  encrypted content, so the server never routes them.
- **Residual risk**: A server that swaps an unverified contact's keys at first contact is
  detected only if the users compare safety numbers. A malicious server can withhold messages.
  Membership changes are not yet signed, so a hostile server can forge their attribution and plant
  group keys, and the server is trusted for group roles (open items in
  `docs/protocol/v2/CRYPTO_V2.md` section 14, "Independent review pass").

### T-2: Object storage leakage
- **Description**: A leak of the server's blob directory or bucket.
- **Mitigation**: Attachments, avatars and backup media are encrypted on the device with
  random keys before upload (STREAM v2). Object ids are random UUIDs, not content hashes, and
  the server keeps no link between an object and a message. Attachments expire after 30 days.
- **Residual risk**: Object sizes and upload times are visible.

### T-3: Traffic analysis and metadata
- **Description**: Watching server ingress, or reading the database, to learn who talks to
  whom and when.
- **Mitigation**: The server keeps **no conversation graph**: only an undelivered-envelope
  mailbox per device, deleted on acknowledgement (30 days at most). Content sizes are padded to
  160-byte blocks. Push payloads are data-only (kind and call id), never content. Presence and
  typing are ephemeral and never stored.
- **Residual risk**: The server sees the sender and recipient devices of every envelope while
  it is delivered, plus timing and (padded) size. Sealed sender is reserved for later. Federation
  shows both servers the sender, recipients and timing of messages that cross.

### T-4: Multi-device impersonation
- **Description**: Maliciously adding a device to an account.
- **Mitigation**: A device is accepted only if its certificate verifies under the account's AIK
  and its proof verifies under its own signing key. Two paths add one: (1) QR linking, approved on
  an existing device (the link token lives 10 minutes and the new device polls with a private poll
  token); (2) password sign-in, which needs the phone number and the password but no approval. The
  second is limited by a doubling lockout (5 wrong attempts lock for 15 minutes, up to 24 hours,
  shared with password change) and per-address limits. Every other device gets a security event
  and a `device_list_change` signal, and can revoke the new one (`revoke`, `revoke-others`,
  "lost or stolen").
- **Residual risk**: On Helix Global, whoever controls the phone number (a SIM swap) can sign in
  by SMS code. That path replaces the account identity (`replace_existing`) and signs every other
  device out, so it is visible to the user and to contacts as an identity-key change, but it is not
  prevented.

### T-5: Phone-hash enumeration (contacts discovery oracle)
- **Description**: `POST /v1/people/discover` answers "is the owner of this number a Helix user on
  this server?" to anyone who can compute the client hash. Anyone can fetch the discovery salt
  and precompute hashes over the E.164 keyspace, then ask.
- **Mitigation**: Discovery needs authentication, is limited per device, and is capped at 5,000
  matches per account per day. The salt endpoint now needs authentication too. The server stores
  only a pepper-keyed index of the client hash (`HELIX_PHONE_PEPPER`), so a database dump alone
  cannot be used to test numbers, which v1's public-salt hash allowed. Accounts can turn discovery
  off (no index at all); turning it back on needs their own number. Only match volume is logged.
- **Residual risk**: The online oracle remains: an authenticated attacker can still test 5,000
  numbers a day per account. This is an **accepted, documented risk** (the same limitation
  pre-enclave Signal had), not a gap awaiting a fix. Phone-book matches are optional: the app asks
  first and works without them.

### T-6: Code interception (SMS code, invite code)
- **Description**: The phone code is delivered by SMS (BulkSMSBD). Anyone who can read the SMS (SIM
  swap, interception, malware) can use it. The code is never returned in an HTTP response: a
  server without a configured SMS provider cannot register by phone.
- **Mitigation**: Codes are six digits, single use, valid 10 minutes, with 5 attempts per challenge,
  at most 5 per hour per number and a resend gap (`HELIX_OTP_RESEND_SECONDS`); the server stores
  only a peppered hash of the code. A verified-phone token is single use. Invite credentials (personal
  servers) expire after 7 days and are stored hashed; shared links carry the code in the URL fragment,
  which browsers do not send to a server. Interception of the SMS itself is not mitigated (T-4).
- **Residual risk**: SMS is a weak channel; a v2 server run without SMS (personal servers) relies on
  invites and device proofs instead.

### T-7: Offline password guessing from a stolen database
- **Description**: An attacker who copies the database gets, per account, the Argon2id parameters
  and salt, an HMAC verifier of the HKDF-derived auth key, and the AIK private key sealed under a
  password-derived key. They can test guesses offline, without the lockout.
- **Mitigation**: Each guess costs one full Argon2id run plus HKDF, and salts are per account. The
  password never leaves the device; the server sees only the derived auth key. Password sign-in
  answers decoy parameters for unknown numbers, so it is not a number oracle.
- **Residual risk**: A weak password can still be found offline, and a successful guess yields the
  account identity private key.

### T-8: Stolen or intercepted recovery code
- **Description**: An operator-issued recovery code (`HLX-REC-...`, single use, 48 hours) reaches
  someone other than the account owner.
- **Mitigation**: The code alone signs nobody in. Redeeming it rotates the AIK onto a new device and
  signs every other device out, and where the server texts codes it also needs a fresh verification
  of the account's own number. Lookups are rate limited per address and answer only `valid: false`
  for bad codes.
- **Residual risk**: On a server without SMS the code plus the phone number is enough to reset the
  account; its administrator should deliver codes privately.

### T-9: Stolen server database or server secrets
- **Description**: A copy of the Postgres database, a backup of it, or the server's `.env`.
- **Mitigation**: The database holds hashes, public keys, ciphertext and metadata, never a message key
  or a password. Phone hashes and the discovery index are keyed by `HELIX_PHONE_PEPPER`, which belongs
  in `.env` and out of database backups. Idempotent responses are sealed at rest.
- **Residual risk**: A dump contains the federation signing private key (there is no rotation tool yet), and `.env` holds the JWT key ring, the pepper, the SMS and Firebase
  credentials and the TURN secret. Anyone with the JWT keys can mint device tokens until they are
  rotated. Protect the PC, the `.env` file and any dump; see `V2_OPERABILITY.md`, "Backups".

### T-10: Hostile or abusive clients
- **Description**: Floods, oversized bodies, malformed input, replayed or tampered envelopes.
- **Mitigation**: Credentials and signatures are checked before bodies are read; bodies and JSON depth
  are capped; every public route declares a rate-limit policy, and limits live in Postgres so they hold
  across nodes and restarts; sends and WebSocket frames are limited; a tampered or replayed envelope
  becomes a visible "couldn't decrypt" row and never blocks the stream.
- **Residual risk**: A single PC node tops out near 80 sends per second (`docs/operations/LOAD_TESTING.md`);
  a determined flood is an availability problem, not a confidentiality one.
