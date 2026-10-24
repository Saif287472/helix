# Sweep 14h — app `core/`: sounds and diagnostics

**Where:** `helix_remote/app/lib/core/sounds/` — `orbit_ringtones.dart` (312),
`orbit_sounds.dart` (109) — and `core/diagnostics/` — `anomaly_log.dart`
(315), `frame_watch.dart` (73) — 809 lines. Cross-reads:
`features/settings/application/sound_packs.dart` (the four page verbs and the
choice store, 1-330), `core/notifications/call_notifications.dart:52-68,
126-270` (`_forRingtone`, `forgetRingtone`, `showIncoming`),
`core/theme/orbit_packs.dart:360-439` (`PackFolder._read` — gate then decode),
`packages/helix_remote_domain/lib/domain/theme_packs.dart:400-628`
(`_checkShape`: one body file, one file for a sound, audio suffixes) and
`:850` (the id pattern), `core/theme/orbit_app_theme.dart:134-204`
(`FileDeviceSettingsStore`), `core/platform/app_blob_store.dart:30-100`,
`core/engine/failure_copy.dart:52-56`, `core/engine/helix_runtime.dart:150-156`,
`main.dart:1-130, 140-175` (the three error handlers and the install point),
`android/app/src/main/kotlin/com/helix/remote/RingtoneProvider.kt` (the
exported read-only provider), and the tests `test/diagnostics/*`,
`test/settings/ringtone_channel_test.dart`.

The sound path's core is careful: the pack gate still guarantees exactly one
audio file, `chosen()` re-gate-checks the pack on every call and falls back to
the phone's sound on any error, the copy is published by write-then-rename,
the provider opens one file name in one folder and nothing else, built-ins
shadow pack ids everywhere they are listed, and the choice is read back after
every write. The three findings are in the edges of that path: which files and
channels a deletion may touch, what two publishes of the same ringtone do to
one temporary file, and a log whose crash report can be postponed by the very
crash it reports.

## Findings

### AUD-14h-1 A repeating crash keeps postponing the batch that would carry it

**Severity:** P3  **Confidence:** confirmed
**Where:**
[anomaly_log.dart:61-67](file:///J:/Projects/helix/helix_remote/app/lib/core/diagnostics/anomaly_log.dart#L61-L67)
(`crash` records with `soon: true`),
[anomaly_log.dart:117-122](file:///J:/Projects/helix/helix_remote/app/lib/core/diagnostics/anomaly_log.dart#L117-L122)
(the repeat branch re-arms the timer),
[anomaly_log.dart:191-199](file:///J:/Projects/helix/helix_remote/app/lib/core/diagnostics/anomaly_log.dart#L191-L199)
(`_schedule`: `soon` cancels the pending timer and starts a new 2 s one).
**What:** every uncaught error goes through `AnomalyLog.crash`, which records
with `soon: true`; `_schedule` then cancels whatever timer is pending and
starts a fresh two-second one. A crash that repeats — a widget that throws in
build/layout on every frame is reported by `FlutterError.onError`
(main.dart:44-50) each time — either adds a new entry or increments the
existing one's count (within `repeatWindow`), and *both* branches call
`_schedule(soon: soon)`. While the error keeps repeating faster than two
seconds, the send timer is cancelled before it fires every time, so `flush`
never runs. The queue is meanwhile filled to `maxQueued` (200), where the
oldest entries are dropped, and everything is in memory only: if the person
force-stops the app, the report of the incident is gone. It is the one
situation where the log is most needed — the app visibly broken — that
suppresses it.
**Trigger:** any `crash` recorded again within two seconds — a widget whose
`build` throws every frame, a layout assertion that repeats while a screen is
open, a platform-channel error delivered repeatedly. The repeat branch makes
the timer reset even though the entry is already queued.
**Evidence:** `crash` at 61-67 passes `soon: true`; the de-duplication branch
(117-121) calls `_schedule(soon: soon)` after `e.count++`; `_schedule` at
192-196 is `if (soon) { _timer?.cancel(); _timer = Timer(2 s, _tick); return;
}`; `_tick` (202-208) is the only caller of `flush`, and nothing else sends on
a crash. A non-`soon` record uses `_timer ??=` (198) and therefore does not
extend a pending timer — only crashes do.
**Impact:** an unresponsive or broken build produces no anomaly at the server,
which is exactly the signal the operator is meant to see; a persistent crash
also overflows the queue so earlier context is dropped before anything is
sent. Diagnostics only; no user data at risk.
**Fix sketch:** a repeat (or any `soon` record) may bring a flush *forward* but
never push it back: keep an earliest-due instant, use `_timer ??= Timer(2 s)`
for `soon` too, or schedule at most `soon` after the *first* crash of a run.
Optionally cap the total: a `soon` flush at least every N seconds regardless
of new crashes.
**Test that proves it:** with a fake clock, record a crash every 500 ms for
5 s against an installed fake sender; assert the sender was called by 2.5 s
(and the queue does not reach 200). Today the send happens only when the
records stop.
**Overlap:** none in the plan; S14h-2. (AUD-14b-4 also names the crash log,
but is about the error being thrown at all.)

### AUD-14h-2 Deleting one ringtone pack can delete another pack's copy and channel

**Severity:** P3  **Confidence:** confirmed
**Where:**
[orbit_ringtones.dart:298-303](file:///J:/Projects/helix/helix_remote/app/lib/core/sounds/orbit_ringtones.dart#L298-L303)
(`prefix = '$id.'`, `basename.startsWith(prefix)`),
[call_notifications.dart:133-138](file:///J:/Projects/helix/helix_remote/app/lib/core/notifications/call_notifications.dart#L133-L138)
(`'${Ringtones.channelPrefix}$id.'`, `channel.id.startsWith(prefix)`),
[sound_packs.dart:158-167](file:///J:/Projects/helix/helix_remote/app/lib/features/settings/application/sound_packs.dart#L158-L167)
(`remove` deletes the pack, forgets the copy and the channel, keeps the
choice), [theme_packs.dart:850](file:///J:/Projects/helix/helix_remote/packages/helix_remote_domain/lib/domain/theme_packs.dart#L850)
(ids may contain dots).
**What:** a pack id is matched against file names and channel ids by the
string prefix `'<id>.'`. Ids are slugs that may contain dots, so a pack called
`acme.foo` matches the copy `acme.foo.bar.mp3` and the channel
`helix_incoming_calls_ringtone.acme.foo.bar.mp3` of a *different* pack. Only
one copy exists at a time — `_publish` deletes every other copy
(orbit_ringtones.dart:221) — and the copy belongs to the ringtone currently
chosen. So if the chosen ringtone is `acme.foo.bar` and the person deletes the
unrelated pack `acme.foo`, that removal takes away the chosen ringtone's copy
and channel. `remove` deliberately keeps the choice ("the choice is kept … the
page then rings with the phone's own sound", 159-166), and the chosen pack is
still installed, so Settings > Notifications keeps naming it as on
(`ringtoneLabelProvider`, sound_packs.dart:96-108, resolves against installed
sounds) while every call rings the phone's own tone, because `chosen()`
requires the copy to exist (orbit_ringtones.dart:273-275). Deleting a pack is
the one way to leave the two disagreeing without the page saying so.
**Trigger:** two installed sound packs whose ids are prefix-related with a dot
boundary (`a` and `a.b` would not collide — the prefix includes the dot — but
`a.b` and `a.b.c` do), the longer one chosen, the shorter one deleted. Ids are
publisher-chosen, so an accidental pair is unlikely; a deliberate pair is
possible, and the cleanup rule should not depend on publishers avoiding it.
**Evidence:** the copy name is `'$id$suffix'` (209), the suffix starts with a
dot (orbit_sounds.dart:106-108), and deletion matches `'$id.'` (298-303);
`forget(id:)` is called with the removed pack's id (sound_packs.dart:166);
`forgetRingtone` uses the same prefix (133-138). `Ringtones.chosen` returns
null when `!await copy.exists()` (273-275), and `ringtoneLabelProvider` only
checks that the pack is still installed, not that the copy is.
**Impact:** a silent wrong ringtone — calls use the phone's default while the
UI says the pack is on. The copy is rebuilt by choosing the ringtone again (or
re-downloading the removed pack), so nothing is lost permanently.
**Fix sketch:** do not match by prefix. Either parse each file name against the
known audio suffixes and compare the whole id, keep a small manifest of the
copies written (id → file, and the channel id), or name copies so that the
boundary is unambiguous and delete by exact name. Channels can be tracked in
the same manifest, or re-derived from the stored channel names. Whichever, the
deletion is driven by the ids the app itself wrote, not by a substring.
**Test that proves it:** install `a.b` and `a.b.c` in a fake ringtones folder,
choose `a.b.c`, remove `a.b`; assert `a.b.c`'s copy and channel still exist
and `chosen()` still returns it. Today both are gone and `chosen()` is null.
**Overlap:** S14h-1; B23 owns `forgetRingtone` already (14g's verified-safe
lists the prefix rule as sound).

### AUD-14h-3 Two publishes of one ringtone share a temporary file

**Severity:** P3  **Confidence:** likely
**Where:**
[orbit_ringtones.dart:205-221](file:///J:/Projects/helix/helix_remote/app/lib/core/sounds/orbit_ringtones.dart#L205-L221)
(`temp = '<target>.part'`, write, rename, delete others),
[sound_packs.dart:203-228](file:///J:/Projects/helix/helix_remote/app/lib/features/settings/application/sound_packs.dart#L203-L228)
(`RingtonePage.use` is not under `_busy`; `_busy` wraps `get`/`update`/`delete`
only).
**What:** the temporary path is deterministic for a given ringtone, and
publication is not serialized. `use()` is called per tap and is not wrapped in
the page's per-id busy guard, and `install()` republishes a ringtone that is
already chosen (sound_packs.dart:132-143). Two `_publish` calls for the same
id and suffix therefore open and write the same `.part` file. Two orders
matter: (a) A renames the shared temp while B is still writing it — B's handle
follows the file to the target name, so a call that opens the provider in that
window can read a partially written ringtone, which is what write-then-rename
is there to prevent; (b) A renames first, then B's rename finds no temp and
fails, `_publish` returns false, and the page reverts the choice to the phone's
tone ("could not be set up") although a complete copy is now in place. The
first is a wrong ringtone for one call; the second is a correct ringtone
declared broken.
**Trigger:** two publishes of the same ringtone overlapping the write window:
a double tap on a ringtone tile (a built-in is 1-3 MB, written from the asset
bundle on a slow phone, so the window is tens of milliseconds), or `update`
of the chosen pack running while the page republishes it. Different ringtones
do not collide (their temp names differ).
**Evidence:** temp name is `'${target.path}.part'` (211-212) with no
uniqueness; `write(temp.path)` awaits (213); `_publish` has no lock or queued
future (205-227); `use` calls `choice.choose` then `Ringtones.publish`
directly (213-226) and is not inside `_busy` (181-195); `install` can call
`Ringtones.publish` for the same id (136-143). `RingtoneProvider.openFile`
opens whatever name is in the folder, including a `.part`-free target
mid-write.
**Impact:** one call rings a truncated sound, or a valid ringtone is silently
reverted to the phone's default. No data outside the copy; re-choosing
rebuilds it.
**Fix sketch:** serialise publication inside `Ringtones` (one future chain,
`_publishing = _publishing.then(...)`), give the temp a unique suffix (random
or a counter), and treat a missing temp after another publish has completed as
success rather than failure.
**Test that proves it:** a fake writer that delays; start two `publish` calls
for the same sound without awaiting the first; assert the final copy's bytes
are complete and both results are true. Today the second write shares the temp
and one of the renames fails.
**Overlap:** S14h-1 (same copy-ownership seam as 14h-2); B23.

## Verified safe

- **The pack is still the gate's.** A sound pack reaches `SoundPackStore` only
  through `PackFolder._read`, which runs `_check` before `decode`
  (orbit_packs.dart:388-426), and the domain's `_checkShape` refuses a sound
  pack that does not carry exactly one file and that file not audio
  (theme_packs.dart:460-520). `_sound`'s `.single` (orbit_sounds.dart:58) is
  therefore safe, and the suffix is guaranteed non-empty and a supported
  audio kind, so a copy name and a provider MIME type always exist.
- **The copy is a copy of checked bytes.** `publish` is handed the file the
  store decoded after the gate (orbit_ringtones.dart:179-181); built-ins come
  from this build's assets (185-193). `chosen()` re-loads and re-gates the
  pack on every call, requires the copy to exist, and answers null on any
  error — a call rings the phone's sound rather than nothing (247-283).
- **The provider is one folder, one file name.** `RingtoneProvider` is
  exported only because Android's notification service opens a channel sound
  without a per-URI grant; `nameOf` accepts exactly `ringtones/<name>` with
  `name == File(name).name` and no leading dot, and `openFile` requires the
  canonical parent to be the ringtones directory, read-only
  (RingtoneProvider.kt:25-50). No other app file is reachable.
- **Only one copy exists.** `_publish` writes the new copy and then deletes
  every other file (`keep: target.path`, 221); `forget()` deletes all of them
  when the phone's own sound is chosen again (sound_packs.dart:205-208), so
  the exported folder never accumulates pack data.
- **Built-ins shadow packs.** `BuiltInRingtones.byId` is consulted before any
  pack in `chosen`, `use`, `install` and the page's listing
  (orbit_ringtones.dart:261; sound_packs.dart:76, 96, 133, 210, 292, 306), so a
  pack cannot take a name this build already rings.
- **The choice is read-back and held to what a call can ring.** `choose`
  re-reads the stored value after writing; a publish that fails reverts the
  choice to the phone's sound and says so (sound_packs.dart:78-87, 213-226).
- **The anomaly log masks before anything leaves.** Bearer tokens, JWTs,
  long key/base64 runs, e-mails and phones (last two digits kept) are replaced
  in `where`, `message`, `fields` and the stack (anomaly_log.dart:232-250);
  release builds keep app frames only and 300/8,000-char bounds; the route's
  own refusals are never reported (99-101); the queue is capped at 200 with a
  dropped counter that is reported once a batch goes out (135-146, 166-184);
  a send failure keeps entries for the next try and cannot throw from
  `record` (148-165, 88-147). The tests cover the masking, both detail levels,
  the repeat window and the route exclusion (test/diagnostics/
  anomaly_log_test.dart:15-105).
- **FrameWatch is bounded in both directions.** A frame counts as slow at
  100 ms, a freeze at 1 s, three slow frames (or any freeze) are needed,
  freezes bypass the 15-minute cap, a report resets the counters, and every
  report goes through `AnomalyLog.state` with two numeric fields only
  (frame_watch.dart:26-63). A batch is about one second of frames, so the
  counters cannot grow without a report.
- **Start-up order.** The three error handlers are installed before anything
  that can throw, `FrameWatch` after the binding exists, notifications before
  the theme load, and the anomaly sender is read in `initState` of the app
  widget, so nothing recorded before that is lost (main.dart:38-100, 140-175).

## Coverage notes

- Read in full: the four files in **Where** (809 lines), plus the cross-reads
  named above.
- Not filed, weighed:
  - `AnomalyLog.crash`/`failure` interpolate `'$error'` for any error
    (anomaly_log.dart:63-64, 82-83, 112-113), and the mask covers tokens,
    addresses and numbers, not paths or quoted text. A `FileSystemException`
    would carry an absolute path (on Windows, the OS account name), and a
    `FormatException` carries an 80-char source excerpt. I could not find a
    live path: every `FileSystemException` site in `app/lib` catches locally
    (app_blob_store.dart:83, orbit_app_theme.dart:180, orbit_packs.dart:
    431, 465), `describeFailure` is only handed engine/API errors, decrypted
    content is parsed by `JsonReader` (path-only messages) and
    `ContentCodec.join` answers `UnknownBody` instead of throwing
    (content_codec.dart:27-41), and the engine's inbound path catches broadly.
    The invariant "callers pass errors, not data" is stated at
    anomaly_log.dart:26-30 but not enforced — a redaction test with known
    error shapes would keep it true; noted for the owner, not filed.
  - The anomaly queue is device-global and deliberately spans sign-in
    ("errors from before sign-in are sent after it", 29-33). On a device with
    accounts on two servers, entries recorded while one account was signed in
    can be sent through whichever runtime is current at flush time. They carry
    no content (types, routes, stacks), and the design explicitly wants the
    pre-session queue to survive, so this is a decision gap rather than a bug;
    it belongs in `99_OPEN_QUESTIONS.md` if the owner wants per-server
    isolation.
  - `flush` keeps entries on *any* failure, so a server that permanently
    refuses a batch (a future validation change, a version-skew limit) would
    wedge the log at the same batch forever. Every limit the client sends is
    at or inside the server's (`Anomaly.maxMessageLength` 2000,
    `maxStackLength` 8000, 50 entries — ops.dart:255, 290-292; the client
    trims to exactly these), so no live trigger was found; it is worth a
    permanent-refusal distinction one day, not a finding today.
  - A pack update that changes the audio format changes the channel id (it
    carries the suffix), so the previous channel lingers in Android's own
    notification settings until the pack is removed. Channels are a system
    list, not data, and `forgetRingtone` cleans them on removal; noted, not
    filed.
  - `chosen()` re-reads and hashes the whole pack on every call, including
    from the push isolate (push_background.dart:152). That is the documented
    security choice ("a manifest edited after its download is not a
    ringtone", 241-247); the audio cap keeps it to one file, so no finding.
  - `mask`'s phone rule fires on any 9+ digit run, so a timestamp or a large
    id in an error message becomes `[phone…xx]`. It loses detail, never
    privacy; no finding.
  - `FrameWatch`'s 15-minute cap means slow frames between reports are
    counted into the next one only if the app is still running; a person who
    closes the app loses the counters. The report that matters (a freeze) is
    never held back, so no finding.
- Not read here: the theme and pack stores (`core/theme/`, sweep 14j), the
  settings page widgets that call the four verbs (sweep 15's `settings`
  feature), and the native notification service behaviour once a channel
  points at a content URI.

## Structural proposals

**S14h-1 — one owner of a ringtone's installation.** Today the copy's name,
the temp file, the deletion rule, the channel id and the setting are known to
four places (`Ringtones`, `SoundPackStore`'s caller, `RingtonePage`,
`CallNotifications.forgetRingtone`). One object — "the installed ringtone" —
should write the copy (unique temp, serialised), remember the exact copy and
channel ids it created, and be the only thing that deletes them. That closes
14h-2 (deletion by exact name instead of prefix) and 14h-3 (one writer at a
time), and makes "what a call rings with" answerable from one place.

**S14h-2 — a flush schedule that cannot be postponed by the thing it
reports.** `AnomalyLog`'s due time is a single `Timer` that every `soon`
record replaces. The log should hold an earliest-due instant that repeats may
bring forward but never push back, and own the one path from "something was
recorded" to "a batch was attempted", so a crash storm flushes on schedule
instead of cancelling its own report (14h-1).
