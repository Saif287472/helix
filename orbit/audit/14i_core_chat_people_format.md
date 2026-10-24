# Sweep 14i — app `core/`: chat, people, labels, calls and util

**Where:** `helix_remote/app/lib/core/` — `chat/chat_gateway.dart` (250),
`chat/message_semantics.dart` (220), `chat/chat_naming.dart` (48),
`chat/search_snippet.dart` (38), `people/people_names.dart` (361),
`format/labels.dart` (200), `calls/call_host.dart` (91),
`calls/call_launcher.dart` (43), `calls/place_call.dart` (20),
`util/streams.dart` (67) — 1,338 lines.

Cross-reads: `orbit_ui`'s renderer
(`chat_screen.dart:2095-2118`, the range clamp), the protocol's preview bodies
(`bodies.dart:146, 299, 406, 453, 506` — the `question`/`title`/`label`/`name`
keys the previews read) and `CallLogBody` (the `media`/`outcome`/`duration_s`
keys), the engine's `group_notices.dart` (sender = actor, `outgoing: false`),
`chats_service.dart:517-532` (a `timer_changed` is a real outgoing message),
`peer_directory._localNotice` (the safety-number row), the app's
`message_actions.dart:104-105, 202-224` (`canForward` and the per-send catch
around `forward`), `features/chats/application/chat_search.dart:98` and
`features/conversation/application/conversation_search.dart:62` (the two
snippet callers), `helix_remote_db`'s `values.dart:118`
(`directConversationId`), and the tests `chat_logic_test.dart`,
`people_names_test.dart`, `calls/call_log_test.dart`,
`test/people_performance_test.dart`.

The helpers themselves are honest: names come from one order, the chat facade
caches nothing and re-checks what it forwards, notice wording matches the
protocol's keys, the call seam answers with a sentence instead of a missing
button, and the renderer clamps whatever ranges the snippet computes. The two
findings are both about a *boundary* that is counted wrongly: a day measured in
elapsed hours, and a cut measured in code units.

## Findings

### AUD-14i-1 A chat day is counted in elapsed hours, so the day after a clock change shows yesterday as today

**Severity:** P3  **Confidence:** confirmed
**Where:**
[labels.dart:167-171](file:///J:/Projects/helix/helix_remote/app/lib/core/format/labels.dart#L167-L171)
(`_daysBetween`: local midnights, `difference(...).inDays`), and its five
callers —
[labels.dart:11-19](file:///J:/Projects/helix/helix_remote/app/lib/core/format/labels.dart#L11-L19)
(`formatChatTime`),
[labels.dart:29-36](file:///J:/Projects/helix/helix_remote/app/lib/core/format/labels.dart#L29-L36)
(`formatDateSeparator`),
[labels.dart:46-53](file:///J:/Projects/helix/helix_remote/app/lib/core/format/labels.dart#L46-L53)
(`formatLastSeen`),
[labels.dart:114-121](file:///J:/Projects/helix/helix_remote/app/lib/core/format/labels.dart#L114-L121)
(`formatDateTime`) and
[labels.dart:126-137](file:///J:/Projects/helix/helix_remote/app/lib/core/format/labels.dart#L126-L137)
(`formatWhen`).
**What:** `_daysBetween` builds two *local* midnights and asks how many whole
24-hour periods fit between them. Consecutive local midnights are not 24 hours
apart across a daylight-saving transition: they are 23 hours apart in a
spring-forward and 25 in a fall-back. `.inDays` truncates, so after a
spring-forward the day before "today" measures 23 h and counts as 0, and two
calendar days measure 47 h and count as 1. Every date label in the chat UI is
derived from that number: the chat list's time ("14:05" instead of
"Yesterday"), the day separator ("Today" over yesterday's messages, so two
days' messages sit under one heading), the header's last-seen line ("last seen
today at …"), message info, and the call log / join-request rows. A seven-day
boundary also shifts: a date exactly a week old measures 167 h → 6 and shows a
weekday where the code means to show the date.
**Trigger:** a phone whose zone observes daylight saving, viewed on the day
after a spring-forward (and, for the 7-day boundary, for the following week).
The message need not be from the transition day — any message from the day
before, read after the clocks move, is mislabelled. Zones without DST (the
current dev host is one) never show it, which is why no test catches it.
**Evidence:** `DateTime(now.year, now.month, now.day)` and the same for `day`
construct local midnight in the system zone (`labels.dart:168-169`);
`today.difference(that)` is absolute elapsed time; `inDays` truncates
(`:170`). In a 23-hour gap the result is 0, and in a 47-hour gap it is 1. All
five callers read `days == 0` as "today" and `days == 1` as "yesterday"
(`:15-17`, `:32-34`, `:50-51`, `:118-119`, `:130-131`). Fall-back (25 h) still
truncates to the right number, so the visible defect is the spring direction.
**Impact:** wrong day labels and a merged day separator for about a day after
each spring transition, in every chat and in the call log; no data is lost and
no behaviour depends on the label, but a messenger showing a message from
yesterday under "Today" is showing the wrong day.
**Fix sketch:** count calendar days, not elapsed time: compare date components,
e.g. `DateTime.utc(now.year, now.month, now.day).difference(DateTime.utc(day.year,
day.month, day.day)).inDays`. UTC has no transitions, so the difference is an
exact multiple of 24 h, and the one helper already serves all five callers.
**Test that proves it:** in a zone with DST, `formatDateSeparator(
DateTime(2026, 3, 8, 14), DateTime(2026, 3, 9, 10))` must be "Yesterday" (and
`formatChatTime` "Yesterday"); today the first returns "Today" and the second
"14:05". The assertion needs the process zone to observe DST — on a Linux CI
job with `TZ=America/New_York` — because a zone without DST passes on today's
code too. Add the southern-hemisphere spring case too (`TZ=Australia/Sydney`,
messages from 2026-10-04 read on 2026-10-05) so the fix is pinned in both
directions of the calendar.
**Overlap:** none in the plan; B25. No existing batch owns `core/format`.

### AUD-14i-2 A search snippet can begin inside an emoji

**Severity:** P3  **Confidence:** confirmed
**Where:**
[search_snippet.dart:20-22](file:///J:/Projects/helix/helix_remote/app/lib/core/chat/search_snippet.dart#L20-L22)
(`start = first - 20`, `flat.substring(start)`, `shift`), called with a
message's body from
[chat_search.dart:98](file:///J:/Projects/helix/helix_remote/app/lib/features/chats/application/chat_search.dart#L98)
and
[conversation_search.dart:62](file:///J:/Projects/helix/helix_remote/app/lib/features/conversation/application/conversation_search.dart#L62).
**What:** the twenty characters of context before the first match are cut with
`String.substring`, which cuts between UTF-16 code units, not characters. A
non-BMP character (an emoji, some CJK extensions) is a surrogate pair; when
`start` lands between its two halves, `shown` begins with a lone low surrogate
and the other half is dropped, so the snippet row starts with a replacement
glyph. The highlight ranges are shifted by a constant and stay correct, and the
renderer clamps them, so this is the only visible effect.
**Trigger:** a message body whose first match sits an odd number of code units
past a surrogate pair that straddles index `first - 20` — e.g. ten emoji, a
period, then the searched word. Only the two search screens produce snippets;
both pass `row.body`. Proportional to how often a person's messages contain
emoji before the matched word, and only when the match is more than twenty
units in.
**Evidence:** `flat` is a Dart `String` (UTF-16); `start` is computed by
arithmetic on code-unit indices (`:20`); `substring(start)` (`:21`) has no
surrogate check; the leading `...` and `shift = 3 - start` (`:22`) assume a
character cut. No `runes`/`characters` boundary handling exists in the file.
**Impact:** one broken character at the start of a search result line; the found
word is still highlighted and nothing crashes. Cosmetic, but it is the kind of
artifact a person reads as corruption.
**Fix sketch:** after computing `start`, if it is inside a pair move it back one
unit (`final unit = flat.codeUnitAt(start); if (unit >= 0xDC00 && unit <=
0xDFFF) start--;`), then recompute `shift`; or take the prefix by
`Characters`/`runes` instead of code units. The range arithmetic stays as it is.
**Test that proves it:** `snippetFor('😀😀😀😀😀😀😀😀😀😀.needle', 'needle')` —
the first rune of `shown` is `...` followed by a *complete* emoji, and the
highlighted range covers exactly `needle`. Today index 1 is a low surrogate and
the first code point of the remainder is invalid.
**Overlap:** none in the plan; B25, the batch for the app's own label and
snippet helpers (14i-1 is the same sweep, a different file and a different
fix site).

## Verified safe

- **Names have one order.** `PersonName.fromRow` keeps the phone-book name
  first, then nickname, then number, then `~Helix name`, with the profile name
  last, and `PeopleDirectory.nameOf` answers `PersonName.unknown` (with a
  roster or call-row hint) for anyone the phone does not know; `display`,
  `firstName` and `avatar` all derive from that one row
  (people_names.dart:1-230). `personNameProvider` subscribes to only that
  person's entry, and the directory maps from the previous one so unchanged
  avatar bytes are not decoded again (246-255, 333-361).
- **The chat facade caches nothing.** `ChatGateway` is reads and writes
  straight through the engine; `forward` re-reads the row, refuses a deleted
  one, reuses the uploaded object for media, and the UI offers Forward only for
  text/media that is neither deleted nor view-once
  (message_actions.dart:104-105); each destination's failure is counted, not
  thrown at the screen (202-224). `sendMedia` clears the picker's plaintext
  copies in a `finally` (chat_gateway.dart:154-174).
- **Notice wording matches the writers.** Preview text reads `question`,
  `title`, `label`, `name` — the keys the protocol's bodies carry — and the
  call log reads `media`/`outcome`/`duration_s` from `CallLogBody`.
  `group_notices.dart` writes sender = actor with `outgoing: false`, which is
  exactly what `systemNoticeText`'s `name(selfId)` (You) and `actor` expect;
  the one exception, `timer_changed`, is a real outgoing message
  (chats_service.dart:517-532), so `row.outgoing` is the right test there. An
  unknown kind returns null and is left out rather than shown as raw text.
- **The renderer cannot be made to throw by ranges.** `HelixHighlightedText`
  clamps each range to the text length and to the previous end before styling
  (chat_screen.dart:2095-2118), so overlapping, duplicate or over-long ranges
  from a multi-word query are harmless.
- **The call seam answers, and the host pushes once.** `CallLauncher` is
  available wherever the app runs and turns any refusal into one sentence
  (call_launcher.dart:23-32); `PlaceCall` resolves to the calls feature's
  `startCallProvider`, the single place every call button goes through.
  `CallHost` opens the call screen in a post-frame callback for a call id it
  has not opened yet, guards `mounted` and `callScreenOpenProvider`, re-rings
  pending offers on resume, and swallows offline/no-runtime (call_host.dart:53-88).
- **`combineLatest2` does what its doc says.** Both subscriptions start in
  `onListen`, the latest of each is kept, an emission waits for both, errors are
  forwarded, and the result closes when both inputs close; its only user is the
  attachment/transfer join (media_content.dart:50). A synchronous source that
  emits while `onListen` is still assigning subscriptions is held by the
  `hasA`/`hasB` flags, not lost.

## Coverage notes

- Read in full: the ten files in **Where** (1,338 lines) plus the cross-reads
  named above.
- Not filed, weighed:
  - **The lowercase-offset hypothesis was rejected.** `snippetFor` lowercases
    text and query and uses indices from the lowercased copy on the original.
    That is only wrong if lowercasing changes length. On the Dart VM — every
    target this app has (Android, Windows) and `flutter test` — `toLowerCase`
    uses the Unicode *simple* mapping, one code point to one code point
    (dart-lang/sdk#6706 is the still-open request for full mapping; the VM's
    `_StringBase.toLowerCase` is native and the Latin-1 fast path is table
    based). Offsets therefore line up, and the finding above is the only
    consequence of the cut, not of the case mapping. A web target (dart2js uses
    full mapping) would reopen this; the app has none.
  - `PeopleDirectory` rebuilds its whole map on every people-row emission, and
    `collides` is O(n) (`labelOf` is O(n²) if a list ever calls it). That is the
    documented "lists are eager" deviation pinned by
    `test/people_performance_test.dart`, and `collides`/`labelOf` are used only
    by tests and `features/people/FEATURE.md` today, so no finding.
  - `ChatGateway.sendMedia` clears *all* picker temporaries in its `finally`.
    Two overlapping `sendMedia` calls could therefore have the first delete the
    second's picked copy (the plugin clears its whole temp directory), and a
    sign-out during an in-flight send does the same. No live trigger found: the
    composer sends one selection at a time, and the engine copies its own files
    before `sendMedia` returns. Noted, not filed.
  - `typingLabelFor` builds "A and B are typing" from a `Set` whose iteration
    order is the presence stream's arrival order, so the two names can swap
    between renders. Cosmetic; no finding.
  - `formatAgo`/`formatAgoShort` measure elapsed time, not calendar days, so
    "Yesterday" starts at 24 h rather than at midnight — that is what their doc
    says (labels.dart:139-165), and the day-based labels above are the ones that
    mean a calendar day.
  - `PeopleDirectory.collides` compares displays with `toLowerCase()`; on the VM
    that is the same simple mapping, and it is only used for a suffix, so no
    mislabelling.
  - `peopleDirectoryProvider` uses a manual single-subscription controller fed
    by `ref.listen(fireImmediately: true)`; the provider itself is the only
    listener and the controller is closed on dispose (333-351). The shape is
    sound, if unusual.
  - The `direct:` prefix is written in two app places and five engine places;
    that is a duplication, not a defect (S14i-1).
- Not read here: `core/theme/` (sweep 14j), the feature screens that consume
  these helpers beyond the cross-reads (sweeps 15+), and how each platform's
  `Text` lays out an unpaired surrogate (the string arithmetic above is the
  evidence; the rendering is left to the engine).

## Structural proposals

**S14i-1 — one owner of the direct-conversation id.** `directConversationId`
exists once (`helix_remote_db/lib/src/values.dart:118`), but its inverse does
not, and the literal `'direct:'` is parsed or matched in seven places: the app's
`chat_naming.dart:7` and `people_names.dart:294` (two different local
consts), and the engine's `chats_service.dart:569`, `presence_service.dart:86`,
`outbound_media.dart:756`, `apply.dart:809`, `snapshot.dart:644, 649`
(`group_ids.dart:2` documents `g:` as its twin). Put `peerOfConversationId` next
to `directConversationId` in the same package, and let both the app and the
engine call the pair; `chat_naming.peerOfConversation` and
`PeopleDirectory.nameOfConversation` then collapse into one call. The id format
is a local-database convention that three layers depend on — the place that
mints it should also be the only place that takes it apart.
