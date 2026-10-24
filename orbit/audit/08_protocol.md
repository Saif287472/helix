# Sweep 8 — `helix_remote_protocol` + golden fixtures

Read (2026-10-23, ~4,000 lines core, plus targeted scans): `packages/
helix_remote_protocol/lib/helix_remote_protocol.dart`, `src/json.dart` (242),
`ids.dart` (64), `paging.dart` (48), `headers.dart` (34), `errors.dart` (172),
`envelope.dart` (332), `sealed.dart` (182), `realtime.dart` (234), `routes.dart`
(987), `content/content_message.dart` (170), `content/bodies.dart` (1,132),
`content/media_pointer.dart` (148), `modules/messaging.dart` (235); `contracts/
v2/fixtures/` (all 9 files) and `test/fixtures_test.dart`; then `src/modules/`
(4,557 lines of DTOs) scanned by pattern (`orElse:`, `strings(`, `objects(`,
`bytes(`) rather than line-by-line. Cross-checks in consumers: the three
`ContentMessage.decode` call sites and the apply path in the engine
(`messaging/inbound.dart`, `messaging/apply.dart`, `groups/group_inbound.dart`,
`backup/inbox.dart`), the api transport's error mapping, and the server's
payload cap (`messaging/module.dart:270`, `groups/module.dart:1081`).

## What is sound

- **`JsonReader` fails as a protocol error, not a `TypeError`**, with the
  field path: integral doubles accepted, non-finite/fractional/wider-than-2^53
  refused, times bounded to 1970..9999, enums with explicit `orElse` semantics
  ([json.dart:40-223](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/json.dart#L40)).
  Unknown fields are ignored and `compact` omits nulls, so both ends agree by
  construction.
- **Unknown *bodies* degrade instead of failing**: an unknown `type`, or any
  `v` above `currentVersion`, becomes `UnknownBody` and is shown as "needs a
  newer version", never raw JSON
  ([content_message.dart:116-122](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/content_message.dart#L116),
  [bodies.dart:1118-1132](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L1118)).
- **Every decode failure at the engine's inbound path is contained**: all three
  `ContentMessage.decode` sites catch (two `on Object`, one
  `on FormatException`, and `ProtocolFormatException extends FormatException`)
  and quarantine the envelope after committing the ratchet, so a crafted body
  cannot stall the stream
  ([inbound.dart:251-260](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/inbound.dart#L251),
  [group_inbound.dart:135-149](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_inbound.dart#L135),
  [json.dart:20](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/json.dart#L20)).
- **Attachment metadata is bounded at decode**: 32-byte key and digest, one
  thumbnail level, 4 GiB size, waveform sample cap
  ([media_pointer.dart:58-72](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/media_pointer.dart#L58)).
  Receipts are the one list with a count cap, 1..500
  ([bodies.dart:810-819](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L810)).
- **The route catalog is a real single truth**: templates parse `{param}`,
  `expand` percent-encodes each value (so an id with `/` cannot change the
  path), and the server's parity test pins registration
  ([routes.dart:41-58](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/routes.dart#L41)).
- **The sealed payload is capped where it counts**: the server enforces the
  256 KiB `maxPayloadBytes` on pairwise and group-device payloads before
  storage ([messaging/module.dart:270](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/messaging/module.dart#L270),
  [groups/module.dart:1081](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/groups/module.dart#L1081)),
  so unreadable content is bounded per message even where the limits below are
  missing.
- The fixtures are regenerated only on purpose (`HELIX_UPDATE_FIXTURES=1`) and
  each stored file is also decoded and re-encoded to prove losslessness
  ([fixtures_test.dart:155-184](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/test/fixtures_test.dart#L155)).

## Findings

### AUD-8-1 `ContentLimits` covers five fields; every other string and list decodes unbounded

**Severity:** P2
**Confidence:** confirmed
**Where:** [bodies.dart:6-33](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L6) (the limits class, whose own comment says "Limits receivers enforce"), the only five uses at [bodies.dart:190](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L190), [:228](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L228), [:266](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L266), [:649](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L649), [:680-681](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L680); unchecked examples: location label/address [bodies.dart:315-316](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L315), contact name/numbers [bodies.dart:411-414](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L411), poll question [bodies.dart:469](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L469), event title/zone [bodies.dart:514-521](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L514), system fields [bodies.dart:546-551](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L546), poll-vote ids [bodies.dart:732-735](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L732), resend ids [bodies.dart:998-999](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L998), contact-sync entries [bodies.dart:1035-1037](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L1035), key bytes [bodies.dart:888-895](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L888), [bodies.dart:924-928](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L924), [content_message.dart:134](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/content_message.dart#L134), per-item caption [media_pointer.dart:130](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/media_pointer.dart#L130), link preview [bodies.dart:151-157](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L151), mentions [bodies.dart:191](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L191).

**What:** `_limited` is applied to `text`, message `caption`, item `caption`
and `emoji` only. Everything else is plain `json.string`/`json.strings`/
`json.bytes`: a poll question, contact card name, event title, location label,
system field map, mention list, poll-vote option list, contact-sync list, and
the sender-key/group-key/profile-key byte arrays have no length or count bound.
`ReceiptBody` is the only list with a count check
([bodies.dart:812](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L812)); `ResendRequestBody` is the same shape and has none.

**Trigger:** any peer (anyone may message anyone) seals a content message with
a 60 KiB poll question, 5,000 mentions, or an `option_ids` list of ten
thousand copies of one valid id — all comfortably inside the 256 KiB payload
cap, and the server cannot inspect it (end-to-end encrypted).

**Evidence:** `PollVoteBody.fromJson` takes `option_ids` with no count check
([bodies.dart:732-735](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L732));
the engine validates membership only, `every(options.contains)`, so duplicates
pass, then stores the whole list under the voter in the target poll's payload
([apply.dart:558-572](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/apply.dart#L558)).
The resend list is *not* a sink because the engine caps it at 500
([apply.dart:781](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/apply.dart#L781)).
`ContactSyncBody` issues one upsert per entry, uncapped
([apply.dart:735-745](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/apply.dart#L735)),
but it is own-account-only ([apply.dart:81-86](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/apply.dart#L81)).

**Impact:** the poll vote is the sharp one: one 256 KiB vote grows that message
row on every member's device by ~256 KiB per voter, repeatedly, for a poll
whose own options the sender already paid for; with a group of N members that
is N×256 KiB of local database for one poll. The long strings are UI and
storage hygiene (a 60 KiB contact name or location label renders in lists and
chat rows). The missing 32-byte key checks turn a wrong-length profile or
group key into a crypto failure later instead of a protocol error now.

**Fix sketch:** apply `_limited` to every user-visible string (caption-sized
for names/labels/titles, text-sized for free text), add `maxMentions`,
`maxContactEntries`, `maxSystemFields`, cap `option_ids` at
`maxPollOptions` (and dedupe in `_pollVote`), and check the 32-byte keys at
decode as `MediaPointer` already does. Wire: unchanged (limits are
receive-side; our own clients never send more). Schema/server: unchanged.
A shared "read a bounded field" table would prevent the next gap (see S7).

**Test that proves it:** protocol test decoding `option_ids` with
`maxPollOptions + 1` entries throws; engine apply test that two copies of one
valid option id are stored once; a content test for an over-long contact name.

**Overlap:** none of the earlier sweeps covered receive-side content decode;
AUD-8-5 is the verification half of the same surface.

### AUD-8-2 An unknown conversation kind is a hard decode failure, unlike an unknown body

**Severity:** P3
**Confidence:** confirmed
**Where:** [content_message.dart:13-21](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/content_message.dart#L13), [:128](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/content_message.dart#L128) vs [bodies.dart:94](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L94).

**What:** `ConversationRef.fromJson` throws on any `conv.kind` other than
`direct`/`group`, while `ContentBody.decode` degrades an unknown `type` to
`UnknownBody`. `ContentMessage.fromJson` knows `version` before it parses
`conv` but does not use it, so the version gate does not protect a message
from a newer client whose conversation kind is new.

**Trigger:** a client adds `conv.kind = "channel"` (or a peer sends
`{"kind":"x"}`). Every older client's decode fails.

**Evidence:** the throw is at
[content_message.dart:13-21](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/content_message.dart#L13);
the body path's `_ =>
UnknownBody(...)` is at
[bodies.dart:94](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L94);
`conv` is parsed unconditionally at
[content_message.dart:128](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/content_message.dart#L128).

**Impact:** the message is quarantined as `bad_content` (a placeholder row)
rather than shown as "needs a newer version"
([inbound.dart:251-260](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/messaging/inbound.dart#L251),
[group_inbound.dart:135-149](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/groups/group_inbound.dart#L135)).
It also makes a new conversation kind a breaking change in practice, though
CONTENT_V2.md §1 promises only additive evolution.

**Fix sketch:** return an `UnknownConversation(kind, raw)` for an unknown kind
(pass `version` in from `ContentMessage.fromJson`), let the app render the
needs-newer-version row. Wire: unchanged. Schema/server: unchanged.

**Test that proves it:** protocol test that `{"kind":"channel"}` decodes to
`UnknownConversation` and re-encodes unchanged; app mapper test that it maps
to the needs-newer-version row.

**Overlap:** AUD-8-3 is the same "unknown enum value picked a destructive
default" shape.

### AUD-8-3 An unknown device-transfer state decodes as `cancelled`

**Severity:** P3
**Confidence:** confirmed
**Where:** [bodies.dart:1107-1113](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L1107), enum [bodies.dart:1041-1059](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L1041), consumer [inbox.dart:30-55](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/inbox.dart#L30).

**What:** `json.optEnum('state', …, orElse: DeviceTransferState.cancelled)`.
Every other forward-compatible enum in the package maps unknown values to an
`unknown` member or a display fallback; this one maps them to the state that
discards the transfer.

**Trigger:** a newer own device sends a state this client does not know
(e.g. a future `verified`/`importing` step) during a history transfer.

**Evidence:** the decode at
[bodies.dart:1107-1113](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L1107);
`cancelled` marks any unfinished incoming transfer `HistoryTransferPhase.cancelled`
([inbox.dart:46-54](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/backup/inbox.dart#L46)).

**Impact:** a mixed-version pair aborts an in-flight transfer and the user
must restart it, with no error explaining why. Only own devices can reach the
path, so it is availability, not security.

**Fix sketch:** add `unknown` to `DeviceTransferState` and treat it as a
no-op in `TransferInbox.apply` (like `EnvelopeKind.unknown`); encode it as
absent. Wire: additive enum member. Schema/server: unchanged.

**Test that proves it:** protocol decode of `state:"verified"` yields
`unknown`; engine test that an unknown state leaves the ledger unchanged.

**Overlap:** AUD-8-2.

### AUD-8-4 An unknown error code is never retryable, against the catalog's own rule

**Severity:** P3
**Confidence:** confirmed
**Where:** [errors.dart:3-5](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/errors.dart#L3), [:56-84](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/errors.dart#L56); api mapping [errors.dart:31-33](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/errors.dart#L31), [:78-105](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/errors.dart#L78).

**What:** `ErrorCode`'s header promises "old clients treat unknown codes by
HTTP status class", but that only happens when the body is *unparseable*
(`codeForStatus`). A parsable `{"error":{"code":"new_code"}}` becomes
`ErrorCode.unknown`, whose `status` is 500 and whose `isRetryable` is false —
even when the real response status was 503 or 429. `ApiException.status`
keeps the real status, but `isRetryable` uses the code alone
([transport/errors.dart:105](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/errors.dart#L105)).

**Trigger:** the server adds a code (an additive change REST_V2.md allows) on
a 503/429 path; an older client sees it.

**Impact:** the older client treats a transient condition as permanent: no
retry, and the user sees a failure that would have succeeded.

**Fix sketch:** `isRetryable => code == ErrorCode.unknown ? (status == 429 ||
status >= 500) : code.isRetryable`, and consider `ApiError.status` carrying
the response status so protocol-only callers get it too. Wire: unchanged.

**Test that proves it:** api test: body `{"error":{"code":"later_code"}}` with
status 503 → `isRetryable` true; status 400 → false.

**Overlap:** AUD-11a-1 reviewed the transport's deadlines, not this mapping.

### AUD-8-5 The golden fixtures pin 9 shapes; the rest of the wire has only round-trip tests

**Severity:** P3
**Confidence:** confirmed
**Where:** [fixtures_test.dart:13-145](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/test/fixtures_test.dart#L13); `contracts/v2/fixtures/` holds
`content_text`, `content_group_media_view_once`, `content_reaction`,
`envelope_message`, `envelope_roster_change`, `sealed_prekey_message`,
`send_message_request`, `error_device_list_stale`, `realtime_hello`.

**What:** no fixture exists for `GroupMessageRequest`, the mailbox page/ack,
`realtime` envelope/wake frames or close codes, any module DTO (identity,
groups, people, keys, calls, backup, ops, admin, federation, media), the
prekey bundle, or 22 of the 25 content types. `dto_round_trip_test.dart`
(641 lines) covers every DTO, but a round-trip passes when encode and decode
change together.

**Trigger:** a deliberate-looking rename of a wire field, updated in both
codec and round-trip test, that the server also updates — every test stays
green and older clients break.

**Evidence:** the fixture table is the nine entries at
[fixtures_test.dart:13-145](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/test/fixtures_test.dart#L13),
and the generator only writes files that are in that map
([fixtures_test.dart:155-166](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/test/fixtures_test.dart#L155)).

**Impact:** the artifact that is supposed to catch wire drift covers ~2% of
the wire; everything else relies on symmetric tests. Not a live bug, a
verification hole, and it is what made AUD-8-2/AUD-8-4 invisible.

**Fix sketch:** one fixture per top-level request/response, per content type
and per realtime frame, generated from a table of constructors; keep the nine.
Wire: the fixtures then *are* the wire. Size: ~1 day of fixture writing.

**Test that proves it:** the fixture test itself would fail on a changed
field.

**Overlap:** AUD-1b-3 (missing EXPLAIN tests) is the same class of verification
hole.

## Structural proposals

### S7 Split `content/bodies.dart`, and make the body registry explicit

**Current shape:** 1,132 lines hold `ContentLimits`, `MessageRef`, `Mention`,
`LinkPreview`, 25 content types and their decode helpers; the only registry is
the string `switch` in `ContentBody.decode`
([bodies.dart:67-95](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/content/bodies.dart#L67)).

**Hazard:** that switch has a `_ =>` default, so a new body type whose case
is forgotten compiles and silently decodes as `UnknownBody`, i.e. every user
sees "needs a newer version" for a message the same build can send. That is
not hypothetical: it is the same default that made AUD-8-1's limits easy to
skip — the private helpers live in this one file and nothing forces a new
body to use them. The file is also a permanent merge point for parallel
feature work.

**Proposed shape:** `content/bodies/` split by family (`visible.dart`,
`actions.dart`, `control.dart`, `transfer.dart`), a `const Map<String,
ContentBody Function(JsonReader)>` registry instead of a switch, and a
small `Bounded` reading helper used by every string/list field. No behaviour
change.

**Migration path:** expand — add the map alongside the switch; migrate —
move classes into the new files and fill the map; contract — delete the
switch and the `_ = >` default, so an unregistered type name can only come
from the wire. No wire, schema or server change; `helix_remote_protocol.dart`
re-exports, so engine/app imports are untouched.

**Risk:** low (move-only, covered by the 377-line content test). **Size:**
S-M (~1 day including the fixture rows it enables).

## Coverage gaps / not read

- `lib/src/modules/*.dart` (4,557 lines) was scanned by pattern and exercised
  through `dto_round_trip_test.dart`, not read line-by-line; the same
  `orElse:` grep found only display fallbacks there (`DevicePlatform.other`,
  `ReportCategory.other`, `ReportStatus.unknown`) and `resumable` defaulting
  to true. `legal.dart` (126) was read only through its callers.
- Not verified here: that every route's `access` matches the server's
  registration (sweep 7 read the parity test; it is not re-checked).
- The app's rendering of over-long names is only reasoned about, not run.
- Content limits cannot be enforced server-side (the payload is encrypted),
  so the fix for AUD-8-1 is client-side by construction.

## Cross-references

- The 409 `device_list_stale` fixture (`error_device_list_stale.json`) is the
  shape AUD-3 covered in messaging; unchanged.
- `CallSignal` DTOs (`modules/calls.dart`) feed AUD-6-1's metrics record.
- The api transport's error mapping is sweep 11a's area; AUD-8-4 is the
  protocol half.
