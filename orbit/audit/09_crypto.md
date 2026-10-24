# Sweep 9 — `helix_remote_crypto` (v2)

Read (2026-10-23, ~4,100 lines of `lib/` line-by-line, ~1,600 of `test/`
targeted): every file in `packages/helix_remote_crypto/lib/src/v2/` —
`primitives.dart` (374), `x3dh.dart` (131), `identity.dart` (457),
`prekeys.dart` (209), `ratchet.dart` (463), `codec.dart` (38), `errors.dart`
(91), `session.dart` (595), `sender_keys.dart` (521), `group_protocol.dart`
(236), `backup.dart` (427), `provisioning.dart` (295), `attachments.dart`
(287), `password.dart` (135), `safety_number.dart` (94), `blobs.dart` (99),
plus `lib/v2.dart`; all seven test files by name and `layout_test.dart`,
`misc_test.dart`, `session_test.dart`, `sender_keys_test.dart`,
`vectors_test.dart` in part. Cross-checks outside the package: `KdfParams`
bounds ([identity.dart:9-53](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/modules/identity.dart#L9)),
the engine's password unwrap with `expectedPublicKey`
([account_service.dart:258-301](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/account_service.dart#L258)),
the stored-session store ([db_stores.dart:1-97](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/crypto/db_stores.dart#L1)),
`PairwiseCrypto` ([pairwise_crypto.dart:97-200](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/crypto/pairwise_crypto.dart#L97)),
the backup restore path ([full_backup.dart:208-302](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/full_backup.dart#L208)),
the app's backup gateway ([backup_gateway.dart:203-241](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/application/backup_gateway.dart#L203)),
the server's 4 KiB cap on a provisioning approval
([sign_in.dart:184](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/application/sign_in.dart#L184)),
and the limits in `CRYPTO_V2.md`.

## What is sound

- **X3DH binds everything that matters**: the AD is label + both account ids +
  both device ids + both DIKs, the four DHs are in spec order, and the
  all-zero shared secret (a low-order public key) is refused
  ([x3dh.dart:35-131](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/x3dh.dart#L35),
  [primitives.dart:262-285](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/primitives.dart#L262)).
- **Sender-key messages verify before decrypting** and the signature covers
  group id + distribution id + iteration + the whole ciphertext; a control
  message that swaps the signing key under an existing `dist_id` is refused
  ([sender_keys.dart:409-440](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/sender_keys.dart#L409),
  [group_protocol.dart:180-236](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/group_protocol.dart#L180)).
- **The ratchet is bounded and side-effect free**: 1,000 skipped keys per
  message, 2,000 stored, 30-day lifetime, 20 remembered remote ratchet keys;
  every decrypt works on a copy and returns "the state to keep", and the
  random generator is only touched *after* the AEAD authenticates
  ([ratchet.dart:286-400](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/ratchet.dart#L286)).
- **Replay is handled by state, not hope**: a replayed prekey message creates
  no second session, used/unknown/retired prekeys are refused without falling
  back to another one, and at most five previous sessions and 100 retired base
  keys are kept
  ([session.dart:471-540](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/session.dart#L471)).
- **Provisioning cannot be lifted**: the approval signs link id + `E_new` +
  account + AIK, the approver must be certified by that AIK and belong to the
  account, the AIK seed must derive the AIK it claims, and the server caps the
  blob at 4 KiB
  ([provisioning.dart:238-295](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/provisioning.dart#L238)).
- **Password and backup KDF floors are enforced at open, not only at seal**:
  Argon2id parameters below the v2 minimum are refused whoever supplied them,
  the wrapped AIK binds the account in its AAD, and sign-in checks the
  unwrapped key against the account's AIK
  ([password.dart:41-105](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/password.dart#L41),
  [backup.dart:283-293](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/backup.dart#L283)).
- **Envelope and blob AAD bind the version**: the full backup binds
  `backup_id` + version, the history backup binds account + version, the group
  state binds epoch + state version, and every sealed blob uses a random nonce
  ([backup.dart:164-169](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/backup.dart#L164),
  [blobs.dart:20-46](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/blobs.dart#L20)).
- **Attachments are chunk-authenticated**: the HXS2 header is in every
  chunk's AAD, the last-chunk flag defeats truncation at a boundary, extension
  fails, and the caller may also check the SHA-256 of the ciphertext
  ([attachments.dart:52-145](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/attachments.dart#L52)).
- **Only `SecureCryptoRandom` is used in product code** (engine, app, CLI);
  `SeededRandom` is test-only, and `AeadKey` (the derived-nonce construction)
  is only used for one-shot secrets — one ratchet message key, one sender-key
  message key, one provisioning ephemeral.
- **The tests pin the layouts, not just the behaviour**: RFC 7748/8032/5869
  vectors, by-hand byte layouts rebuilt independently of the helpers, padding
  in 160-byte steps, random interleavings with drops, tamper/truncate/reorder,
  and one end-to-end seeded vector per construction.

## Findings

### AUD-9-1 Stored crypto state decodes any-length keys and any counters, so a damaged row either wedges a peer or silently breaks its ratchet

**Severity:** P3
**Confidence:** confirmed
**Where:** [ratchet.dart:174-196](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/ratchet.dart#L174), [ratchet.dart:59-64](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/ratchet.dart#L59), [sender_keys.dart:202-223](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/sender_keys.dart#L202), [sender_keys.dart:325-340](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/sender_keys.dart#L325), [session.dart:118-135](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/session.dart#L118), [codec.dart:23-38](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/codec.dart#L23), [db_stores.dart:68-92](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/crypto/db_stores.dart#L68).

**What:** the state factories read key bytes with `json.bytes(...)` and
counters with `json.integer(...)` without the `requireLength`/`isU32` the wire
decoders apply: `rk`, `cks`, `ckr`, `dhr` (ratchet), `mk` (skipped), `ck`,
`sig_pub` (sender keys), `remote_dik`, `remote_aik`, `local_dik`, `base_key`
(session) and `ns`, `pn`, `nr`, `it`. It is inconsistent even inside one
factory: `X25519KeyPair.restore` *does* check 32 bytes
([ratchet.dart:179-182](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/ratchet.dart#L179)).
There are two outcomes:

- a wrong-length `rk`/`cks`/`ckr`/`ck` does **not** throw: HKDF and HMAC
  accept a key of any length, so the record loads, the next encrypt derives a
  different chain, seals successfully and commits the advanced state
  ([ratchet.dart:247-286](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/ratchet.dart#L247));
- a wrong-length `dhr` throws later, inside `agree`, on the next decrypt.

**Trigger:** corruption of one `sessions`/`sender_keys` row — SQLCipher page
damage, a bad restore of the database file, or a step-migration that rewrites
the blob. Not peer-controlled: no wire field is copied into these bytes.

**Evidence:** the decode sites above run inside `DbSessionStore.decode`
([db_stores.dart:68-92](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/crypto/db_stores.dart#L68)),
which `load` calls and whose exception propagates
([db_stores.dart:37-45](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/crypto/db_stores.dart#L37)).
The send path loads first through `withoutSession`
([pairwise_crypto.dart:97-103](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/crypto/pairwise_crypto.dart#L97)).
Starting a fresh session also loads first
([session.dart:375](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/session.dart#L375)),
so a reset cannot overwrite the bad row, and `MalformedCryptoInputException`
does not request a reset
([errors.dart:11-14](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/errors.dart#L11)).

**Impact:** a corrupt row either makes every send to that one device fail
forever (surviving restarts, re-pairing and session reset) or, worse, lets the
device send ciphertext the peer can never derive while advancing its own
chain — a silent, permanent break with no on-screen cause.

**Fix sketch:** validate length and counter range in the crypto decoders and
raise one local-state exception (S9-1); have the engine treat a decode failure
in `load` as "no session" and delete the row so the normal reset path rebuilds
it. No wire or schema change; the bytes written stay identical.

**Test that proves it:** a crypto test that decodes a state with a 16-byte
`rk`/`ck` and a non-`u32` counter and expects an exception *at decode*; an
engine test that corrupts a `sessions` row and asserts the next send recreates
the session instead of failing.

**Overlap:** AUD-2-2 (session reset), S9-1.

### AUD-9-2 `DeviceSessions` has two serializations; the one the app stores lives in the engine and the other is dead

**Severity:** P3
**Confidence:** confirmed
**Where:** [session.dart:236-264](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/session.dart#L236), [db_stores.dart:58-92](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/crypto/db_stores.dart#L58), [session_test.dart:95-105](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/test/v2/session_test.dart#L95), [util_test.dart:147-160](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/test/util_test.dart#L147).

**What:** `DeviceSessions.toJson/fromJson/encode/decode` is one JSON document
holding `remote`, `active`, `previous[]` and `retired[]`. Production
`DbSessionStore` writes a different layout — slot 0 is
`{v, retired[], active}`, slots 1-5 are one `PairwiseSession` each, and the
remote comes from the row key — and never calls `DeviceSessions.decode`. The
crypto codec is used only by crypto tests and the crypto test fake.

**Trigger:** any future change to the stored envelope (a per-session flag, a
change to the retired-key encoding, a state version bump): it is made in
`DeviceSessions`, proven by `session_test.dart:95-105`, and the bytes the app
actually writes are unchanged.

**Evidence:** `DeviceSessions.decode` appears only under `test/`
([session_test.dart:100](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/test/v2/session_test.dart#L100),
[session_test.dart:126](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/test/v2/session_test.dart#L126),
[layout_test.dart:127](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/test/v2/layout_test.dart#L127));
the production encode/decode is
[db_stores.dart:58-92](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/crypto/db_stores.dart#L58)
and is round-tripped by [util_test.dart:158-160](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/test/util_test.dart#L158).

**Impact:** the package's own doc says state is plain data it owns ("that
`helix_remote_db` stores and the engine commits",
[v2.dart:1-9](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/v2.dart#L1)),
but the codec that stores it is in the engine. A reader or a test can change
the unused shape and stay green while the stored shape rots, and the reverse
change has no test in the package that owns the type. No runtime bug today.

**Fix sketch:** move the slot codec into crypto as
`DeviceSessions.encodeSlots/decodeSlots`, have `DbSessionStore` delegate, and
delete the document codec (or make the store use it). Stored bytes unchanged;
no wire or schema change.

**Test that proves it:** a crypto test that round-trips the slot codec
(retired keys in slot 0, previous sessions in slots 1-5) and asserts slot 0
carries both; the existing engine CAS test keeps pinning the store.

**Overlap:** AUD-9-1 (same decoder surface), S9-1.

## Structural proposals

### S9-1 Give corrupt local crypto state its own failure type

**Current shape:** one `CryptoV2Exception` tree. `MalformedCryptoInputException`
is raised for untrusted wire input (sealed blobs, provisioning content, group
distributions, attachment headers), for local state (`readState`,
`decodeStateJson`) and for local key material (`X25519KeyPair.restore`). The
only signal the engine uses to decide "ask for a fresh session" is
`requestsSessionReset`
([errors.dart:11-14](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/errors.dart#L11)).

**Hazard:** a corrupt local record and a malformed peer payload are
indistinguishable by type, so the engine can only get one of them right. Today
neither is a reset (AUD-9-1), and every future local-only decode failure lands
in the same dead end: quarantine forever, or fail the send forever.

**Proposed shape:** a `CorruptStateException` (subclass,
`requestsSessionReset = true`) thrown only from the local decode boundary
(`readState`, `decodeStateJson`, the `fromJson` factories' restore helpers).
The engine maps it to "delete this record and start over" instead of
quarantine; `MalformedCryptoInputException` stays for wire input.

**Migration path:** additive type, change the throw sites in `codec.dart` and
the state factories, add the engine branch, ship both in one change. No stored
format, wire or schema change.

**Risk:** misclassifying a peer-triggered failure as local would discard good
state; mitigated by raising it only at the local decode boundary, never in a
wire-decoding path. **Size:** S.

## Coverage gaps / not read

- Every `lib/src/v2/` file was read line-by-line (~4,100 lines); the test
  files were read by name and partly by body — `support.dart` and the
  remaining halves of `misc_test.dart`/`session_test.dart` were not.
- No fuzzing or property test of the JSON state decoders exists (the reason
  AUD-9-1 survived review); no test covers `BackupCrypto.open` being handed a
  wrong platform key while a correct recovery secret is available, and no test
  loads a state record written by an older app version.
- The platform-credential wrap has no product caller: the app's create and
  restore paths pass no `platformKey`
  ([backup_gateway.dart:213-241](file:///J:/Projects/helix/helix_remote/app/lib/features/backup/application/backup_gateway.dart#L213)),
  so every shipped backup is protected by the recovery secret alone. The code
  path is tested ([misc_test.dart:209](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/test/v2/misc_test.dart#L209))
  but not used — noted, not a finding.
- ADR-028 stands: none of this has had an external cryptographic review. This
  sweep is code-vs-spec, not cryptanalysis; `package:cryptography`'s X25519,
  Ed25519 and AES-GCM are pinned by RFC vectors but not audited here.
- Sender-key and ratchet *integration* (roster construction, distribution
  delivery, inbound ordering) was audited in sweeps 2-4 and is not repeated.
- Limits were checked against `CRYPTO_V2.md` and match: MAX_SKIP 1,000,
  2,000 stored, 30-day skipped keys, 20 ratchet keys, SPK 7-day rotation and
  30-day retention, sender-key 7 days/10,000 messages, 5,200 safety
  iterations, backup KDF 8,192..262,144 KiB × 2..10.

## Cross-references

- **AUD-2-2** (session reset) is the engine half of AUD-9-1; **AUD-5-1**
  (backup restore) is the caller of the KDF floors checked above.
- **AUD-8-2 / AUD-8-3** (unknown enum -> destructive default) share the
  "decode picked a lossy default" shape with AUD-9-1's silent key path.
- **S5 / S7** (engine and protocol splits) do not touch this package; crypto
  has no layering violation (architecture test, pure Dart, single public
  library).
