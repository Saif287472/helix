# Sweep 12h — engine: people, phone book, settings

Read line-by-line: `features/people_service.dart` (699), `features/phone_book.dart`
(37), `features/settings_service.dart` (106, moved up from 12i because it shares
the discovery/privacy surface). Cross-reads: `messaging/apply.dart:65-100, 715-745`
(control bodies, `ProfileKeyUpdateBody`), `features/chats_service.dart:245-262`
(every outgoing message carries the profile key), `crypto/peer_directory.dart:120-195`
(key change resets verification), `account/account_service.dart` from 12g
(`profileKey: null` on password sign-in), the crypto `password.dart` /
`provisioning.dart` (what each wrap carries), `people_dao.dart:51-105`
(search, `setBlocked`), the server's `people/module.dart:558-590`,
`identity/application/context.dart:131-157` (`setPhoneDiscoverable`) and
`people/module.dart:263-264` (salt version), and the app's
`core/platform/device_phone_book.dart:49-75`. ~1,500 lines. Two structural
proposals.

Verdict: discovery, block sync, safety numbers and the photo fetch are careful
(hashing on device, digest-checked downloads, verification reset on a key
change). The weak spot is the **own profile key**: it is minted locally per
device, handed over only by a link, and replaced by the password wrap — so a
device that arrives by password without a restore has no key, and publishing a
profile from it forks the account's profile key for good.

---

### AUD-12h-1 A device that signs in with the password and did not restore a backup has no profile key; publishing from it forks the account's profile key

**Severity** P2  **Confidence** likely (every step is code-confirmed; the trigger is the ordinary "new phone, password, skip restore" path)

**Where**
- [`account/account_service.dart:294-300`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/account_service.dart#L294) — password sign-in calls `_addDevice` with no profile key; [`account_service.dart:545-552`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/account_service.dart#L545) — `_persist` stores `profileKey: Value(null)`.
- [`crypto/password.dart:82-115`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/password.dart#L82) — the password wrap carries the identity seed only; the profile key is not in it.
- [`crypto/provisioning.dart:100-146`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_crypto/lib/src/v2/provisioning.dart#L100) — the *link* provision does carry `profile_key`, which is why linking works and signing in with the password does not.
- [`messaging/apply.dart:76-80`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/apply.dart#L76) — a `ProfileKeyUpdateBody` from this account is refused (`'self'`), and [`apply.dart:722-733`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/apply.dart#L722) writes a peer's key into the *people* row, never the account row. Nothing in the engine ever sends the body.
- [`features/people_service.dart:401-407`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/people_service.dart#L401) — `setOwnProfile` takes `row.profileKey ?? newSymmetricKey(...)`: a device without a key **mints a new one** and publishes the profile under it; [`people_service.dart:442-451`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/people_service.dart#L442) then stores it as the account's key.
- [`people_service.dart:465-485`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/people_service.dart#L465) — `_ownPhoto` returns null on *any* failure, including "this key cannot open the stored profile"; [`people_service.dart:405-407`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/people_service.dart#L405) then publishes no avatar at all, and [`people_service.dart:441`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/people_service.dart#L441) only deletes the old object if a *previous pointer* was known.

**What** The profile key is per account in intent, but the engine only ever
learns it from a link provision (`provisioning.dart`) or a backup restore
(`snapshot.dart:496`). A password sign-in creates none. The first profile edit
on that device goes through `setOwnProfile`, which silently makes a second key
(K2), publishes `version + 1` under it, and records K2 locally. From then on
the account has two profile keys:

- **The account's other devices** hold K1. They cannot open the server profile
  any more, and unlike peers they never receive a key update: outgoing
  messages carry the sender's key (`chats_service.dart:259`) but the applier
  ignores a self-authored `ProfileKeyUpdateBody` and writes a peer's key to
  the people row, not the account row.
- **Peers** holding K1 cannot open the new profile until the next message from
  this account, which does carry K2; they keep their cached name and photo
  until then.
- **A name-only save from a device that holds K1 and never published itself**
  (a linked device: no remembered `people.photo:<self>` pointer) reads the
  server profile with K1, fails, treats it as "no photo" and publishes the new
  name with no avatar — the published picture is silently removed for
  everyone, and because no previous pointer was known it is not even deleted
  server-side, just orphaned.

The profile page's own doc (383-387) already expects the version part
("published again just above the server's version") but not the key part.

**Trigger** A new phone signs in with the phone number and password, skips the
backup restore (the restore step is offered, not required), and the user edits
their name, about or picture. The photo loss needs one more step: any other
device of the account that has never published a profile photo then changes
the name.

**Evidence** `_persist` passes `profileKey: null` for password sign-in and a
real key for register, recovery and link; the password wrap has no key slot
while the link provision does; `setOwnProfile` has no guard against minting
over an existing profile and no way to tell "the profile uses another key"
from "there is no profile". `ProfileKeyUpdateBody` is defined and consumed but
never produced by any client — the handover mechanism exists on paper only,
and its consumer is peer-only.

**Impact** The visible picture disappears from everyone's avatar of this
account (the most user-visible part), the account's other devices show stale
profile data indefinitely, and the account carries two profile keys with no
path to converge. Nothing is leaked: a peer that cannot open the new profile
just keeps old data; the new key travels to peers with the next message as
designed.

**Fix sketch** Do not mint silently. Two changes: (1) `setOwnProfile` should
refuse (or ask) when the account row has no profile key *and* the server
already holds a profile: restore the backup, link a device, or explicitly
"replace the profile" (which is what happens today, but as a choice). (2) Give
the key a handover: `ProfileKeyUpdateBody` is already on the wire — let this
account's own devices send it to each other (audience `[self]`) on a key change
and after a password sign-in), and have the applier write the *account* row
when the sender is self (today it refuses self and targets the people row).
Optionally, and most robustly, put the profile key into the password wrap with
a wrap format version, which needs crypto vectors and the design-review note.

**Test that proves it** Sign in with the password (a fake server that returns
the wrapped identity key), then call `setOwnProfile` with a name: assert the
test can detect the fork — the server's stored profile is sealed under a key
different from the one the account's other device holds — or, after the fix,
that `setOwnProfile` refuses (or asks) instead of minting. A second test: two
devices, K1 and K2, name-only save from the K1 device keeps the stored photo
pointer.

**Overlap** AUD-12g-2 (the new-device flows and what they persist) is the same
"password sign-in arrives with less than a link" family; the backup sweep
(12n-12p) owns the restore path that supplies the key.

---

### AUD-12h-2 Clearing a nickname cannot undo the phone-book rename, so the old nickname keeps showing

**Severity** P3  **Confidence** confirmed

**Where**
- [`features/people_service.dart:562-603`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/people_service.dart#L562) — `setNickname` writes the nickname into the phone book when it is set and a number is known (588-602) and then stores the same value as `phonebookName`.
- [`people_service.dart:588-602`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/people_service.dart#L588) — the write-back runs only for a non-null nickname; a clear (`value == null`) leaves the contact renamed and `phonebookName` in place.
- [`people_service.dart:19-28`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/people_service.dart#L19) — `phonebookName` outranks `nickname`, so the stale value wins.
- [`app/lib/core/platform/device_phone_book.dart:49-75`](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/device_phone_book.dart#L49) — `saveName` writes the new name into the contact (creating one when the number is not there).

**What** Renaming someone in Helix is defined to rename them in the phone's
contacts too, and the phone-book name outranks everything else. Setting a
nickname therefore renames the contact, and the same string is copied into
`people.phonebook_name`. Clearing the nickname sets `nickname` to null but
neither restores the contact's previous name (the engine never knew it) nor
clears `phonebookName`, so the display name is unchanged. The user sees a
rename that refuses to be undone.

**Trigger** Set a nickname on a contact that has a phone number, then clear it.

**Evidence** The branch at 589 requires `value != null`; the comment there
explains the *opposite* direction (why the phone-book name must be updated when
renaming) but not the clear. Once `phonebookName` is written, the only way to
change the displayed name is to edit the phone's contacts or set a new
nickname (which renames the contact again).

**Impact** A stuck name that the user cannot fix from inside the app, and a
phone contact that was renamed and cannot be restored from Helix. Cosmetic but
confusing, and it makes "clear" look broken.

**Fix sketch** Decide the clear semantics: either (a) on clear, delete the
contact rename as well (the phone book API would need a "restore" call, which
it does not have — the engine never stored the old name), or (b) on clear,
reset `phonebookName` to null so the person falls back to their number/profile
name, documenting that the phone contact keeps the name Helix gave it; or (c)
stop writing the nickname into the phone book and keep the two names separate.
(b) is a two-line change; (c) revisits the product rule, so it is the owner's
call.

**Test that proves it** Set a nickname for a contact with a number, clear it,
and assert the display name falls back to the number (or, if (a) is chosen,
that the phone book was asked to restore).

**Overlap** None in the audit; the product rule is `AGENTS.md` "Renaming
someone writes the name to the phone's contacts too".

---

### AUD-12h-3 (Idea) Discovery ignores the salt version, so a server-side salt rotation would silently disable discovery

**Severity** Idea  **Confidence** confirmed (latent: no rotation exists today)

**Where** [`features/people_service.dart:169-175`](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/features/people_service.dart#L169) — the salt is fetched once and cached in settings forever; [`server/lib/src/modules/people/module.dart:263-264`](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/people/module.dart#L263) — the server already returns `version: 1` with the salt.

**What** Every discovery hash is `HMAC(salt, E.164)`. The client caches the
salt and never looks at `version`. If the salt is ever rotated (the version
field exists for that), every cached client keeps hashing with the old salt,
the server answers "no matches" for all of them, and no error surfaces: phone
discovery just stops finding anyone, including for numbers already in the
book, until the app's settings are cleared.

**Impact** A silent, total failure of discovery after an operator rotation,
with no way for the user to fix it except clearing app data.

**Fix sketch** Store the salt with its version and re-fetch when the version
the server reports is newer (a cheap `HEAD`-like check on the next sync), or
fetch the salt on every sync (one request per sync, negligible) and let the
cached one be a fallback.

**Test** A fake server that bumps its salt version: after a sync the client
hashes with the new salt.

**Overlap** None.

---

## Structural proposals

**S1 — one owner for the account's profile key.**
*Current shape:* the key lives in the account row per device; it is minted by
`setOwnProfile` when missing, learned from a link provision, or restored from a
backup; the protocol's `ProfileKeyUpdateBody` is defined but never sent and
refuses self.
*Hazard:* AUD-12h-1 — three producers and no handover means "which key is the
account's" is decided by whichever device publishes first.
*Proposed shape:* a small `OwnProfileKey` in `account/` (or `features/`) that
owns `get()`, `learnFromLink/Backup()`, `publishToOwnDevices()` (a real
`ProfileKeyUpdateBody` in both directions, written to the account row when the
sender is self) and `mintOrRefuse(profileExists)`. `setOwnProfile` and
`approveLink` call it; the raw column is no longer read or written elsewhere.
*Migration:* expand (add the type over the current column, no behaviour change)
→ migrate (`setOwnProfile`, `approveLink`, the applier's self branch) →
contract (nothing reads `accountDao.profileKey` directly).
*Risk:* medium — the applier change touches the inbound transaction and must
keep the peer path (people row) intact.
*Size:* ~120 lines, four call sites, three tests (link handover, backup
restore, refuse-to-fork).

**S2 — one naming policy, including write-back.**
*Current shape:* `PersonNaming.displayName` decides the order; `setNickname`
decides when to write to the phone book; the app owns the phone book; the
"clear" case is nobody's.
*Hazard:* AUD-12h-2 — the rule "phone-book name outranks nickname" and the rule
"renaming writes the phone book" interact, and the interaction is resolved ad
hoc inside one method.
*Proposed shape:* `PersonNames` in `features/` owning `display(person)` and
`rename(account, name)` (which decides the phone-book write-back and the
nickname/phonebook-name columns together), with the phone book injected as it
already is. The app keeps only the platform implementation.
*Migration:* move `displayName` and `setNickname` behind the type; no schema
change; ship the clear-case test with the move.
*Risk:* low.
*Size:* ~80 lines moved, one call site layer (the gateway), two tests.

## Verified safe

- **A peer's key change resets trust.** `_applyKeyChange`
  (peer_directory.dart:156-174) clears the account's sessions, marks devices
  stale, sets `identityVerified = false`, records the change time and writes a
  safety-number notice in every chat with that account — a verified flag can
  never survive an identity rotation.
- **Safety numbers** are computed from the *pinned* key, so a displayed number
  always matches what was pinned (people_service.dart:672-682).
- **Photo downloads are bounded and checked** — size checked against
  `maxPhotoBytes` before the request, the download capped to the pointer's
  ciphertext length, the digest verified, and the plaintext length compared
  (320-336). A bad photo never fails a profile read.
- **A photo that cannot be fetched is retried**, not lost, when the profile
  version is unchanged and a pointer is remembered (228-235).
- **Discovery never uploads numbers**: only HMAC hashes leave the device
  (`_hash`, 179-189), matching the module's contract.
- **Block sync is server-first** (`block`/`unblock` call the API then write the
  flag) and `syncBlocks` replaces the local flags from the server in one
  transaction; `setBlocked` upserts, so a server-side block on an account this
  device has no row for still lands.
- **`setPrivacy`'s "turning phone discovery back on needs the number"** rule is
  enforced by the server (`identity/application/context.dart:146-155` throws
  `invalid_field`), so a client that omits the number gets an error rather
  than a silently undiscoverable account.
- **Helix-name changes are server-first**, and the local save is a partial
  companion (drift 2.34 preserves the other account columns).
- **Search** escapes the LIKE pattern and excludes blocked people
  (people_dao.dart:51-77).

## Coverage notes

- `reportForConsole` marks `consoleDetailsReported` on `invalid_field` even
  when it was the *phone* call that failed, so a name that would have been
  accepted is never reported. Deliberate per its comment ("a number the server
  will not take is not [retried]") but the name is collateral; not worth a
  finding on its own.
- `syncPhoneBook` re-queries every number on every sync; the app guards this
  with a same-day log (`app/lib/features/people/application/phone_book_sync.dart:147`),
  so the discovery budget is bounded at the app layer, not here.
- A nickname save that succeeds locally but throws from the phone book
  (`saveName` can throw, not only return false) reports failure although the
  nickname was stored and synced — the same "second call decides the outcome"
  shape as AUD-12g-4, one layer down.
- `presence(account)` is a bare API call with no block check and no cache;
  the app owns polling. Sweep 4a covered the server side.
- The own-profile publish path also writes the operator console's copy
  (`setOwnName`, best effort); ADR-030 accepted that copy. Not re-litigated.
