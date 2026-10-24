# Helix Remote / Orbit audit — index

Read-only audit. Findings live in `NN_<area>.md`; nothing outside `orbit/audit/`
is ever modified. Root `AGENTS.md` governs; accepted decisions (ADRs, the two
open DEVIATIONS rulings, the pending-redeploy list, the uncommitted
`orbit/prototype/css/tokens.css`, known-flaky tests) are not relitigated.

## Status

| # | Sweep | File | Status |
|---|---|---|---|
| 0 | Orientation: AGENTS, HANDOFF, GAPS, architecture §3-6 | - | done |
| 1a | Platform: HTTP pipeline, routes, request, idempotency, rate limits, redacting log, metrics, WS cap | `01a_platform_http.md` | done |
| 1b | Platform: Db/Tx, migrations, jobs/outbox, periodic scheduler, ephemeral store, start-up | `01b_platform_core.md` | done |
| 1c | Platform: blobs, push, bus, storage budget, config, module base | `01c_platform_io.md` | done |
| 2 | Identity + keys | `02_identity_keys.md` | done |
| 3 | Messaging + realtime | `03_messaging_realtime.md` | done |
| 4a | People (profiles, privacy, blocks, contacts, discovery, presence, reports) | `04a_people.md` | done |
| 4b | Groups: roster, roles, invites, sends | `04b_groups.md` | done |
| 4c | Groups: `group_store.dart` + `federation.dart` | `04c_groups_data.md` | done |
| 5 | Backup + media | `05_backup_media.md` | done |
| 6 | Calls + federation | `06_calls_federation.md` | done |
| 7 | Ops + admin + compliance (packs, `HELIX_PACKS_DIR`, admin authz) | `07_ops_admin_compliance.md` | done |
| 8 | `helix_remote_protocol` + fixtures | `08_protocol.md` | done |
| 9 | `helix_remote_crypto` | `09_crypto.md` | done |
| 10 | `helix_remote_db` | `10_db.md` | done |
| 11a | `helix_remote_api`: transport, auth, errors, retry | `11a_api_transport.md` | done |
| 11b | `helix_remote_api`: realtime WebSocket client | `11b_api_realtime.md` | done |
| 11c | `helix_remote_api`: typed REST clients | `11c_api_clients.md` | done |
| 12a | `helix_remote_engine`: `Engine`, events, errors, maintenance | `12a_engine_core.md` | done |
| 12b | `helix_remote_engine`: outbox, sender, inbound runner (+ rekey path) | `12b_engine_send.md` | done |
| 12c | `helix_remote_engine`: apply, inbound, content codec, kinds | `12c_engine_apply.md` | done |
| 12d | `helix_remote_engine`: pairwise crypto, peer directory, session/prekey stores | `12d_engine_crypto.md` | done |
| 12e | `helix_remote_engine`: groups service + roster sync | `12e_engine_groups.md` | done |
| 12f | `helix_remote_engine`: group crypto (inbound, sender, sender-key store) | `12f_engine_group_crypto.md` | done |
| 12g | `helix_remote_engine`: account, devices, prekeys, session store | `12g_engine_account.md` | done |
| 12h | `helix_remote_engine`: people, settings, phone book | `12h_engine_people.md` | done |
| 12i | `helix_remote_engine`: `chats_service` | `12i_engine_chats.md` | done |
| 12j | `helix_remote_engine`: presence, push, push wiring | `12j_engine_presence_push.md` | done |
| 12k | `helix_remote_engine`: calls — state machine, signalling, config | `12k_engine_calls.md` | done |
| 12l | `helix_remote_engine` calls: log mirror, media seam; `helix_remote_calls` | `12l_engine_calls_media.md` | done |
| 12m | `helix_remote_engine`: transfers part one — `media_service`, `transfers_service`, config, views, media settings, storage | `12m_transfers_media.md` | done |
| 12n | `helix_remote_engine`: transfer queue and runners | `12n_engine_transfers_queue.md` | done |
| 12o | `helix_remote_engine`: download runner, blob stores, janitor, failure mapping | `12o_download_blobs_janitor.md` | done |
| 12p | `helix_remote_engine`: backup service, ledger, models, options | `12p_backup_service.md` | done |
| 12q | `helix_remote_engine`: backup archive — export, restore, full backup | `12q_backup_archive.md` | done |
| 12r | `helix_remote_engine`: transfer receiver, `inbox`, `errors` | `12r_transfer_receiver.md` | done |
| 13 | CLI + server `test/client` harness | `13_cli_harness.md` | done |
| 14a | App `core/engine/`: runtime, providers, settings seam, failure copy | `14a_core_engine.md` | done |
| 14b | App `core/`: the lock, the network, the resume; tls pinning | `14b_core_security.md` | done |
| 14c | App `core/platform`: media metadata — sanitizer, thumbnails, blurhash, pixel, profile image | `14c_core_media.md` | done |
| 14d | App `core/platform`: media I/O — pickers, blob store, processor, temp, storage usage | `14d_core_media_io.md` | done |
| 14e | App `core/platform`: audio, voice, video players; chat platform seam | `14e_core_audio_voice.md` | done |
| 14f | App `core/`: links, router | `14f_core_links_router.md` | done |
| 14g | App `core/`: push, notifications | `14g_push_notifications.md` | done |
| 14h | App `core/`: sounds, diagnostics | `14h_sounds_diagnostics.md` | done |
| 14i | App `core/`: chat, people, format, calls, util | `14i_core_chat_people_format.md` | done |
| 14j | App `core/`: theme | `14j_core_theme.md` | done |
| 15 | App `lib/features/`: `sign_in`, `backup` | `15a_features_sign_in.md`, `15b_features_backup.md` | done (9 features left) |
| 16 | `orbit_ui` (tokens, pack stores, a11y) | `16a_orbit_ui_theme.md`, `16b_orbit_ui_packs_a11y.md` | done |
| 17 | `admin/` console | `17a_admin_session.md`, `17b_admin_console.md` | done |
| 18 | CI, scripts, tool, dependency policy, docs drift | `18_ci_scripts_docs.md` | done |
| 19 | Synthesis: remediation plan (rebuilt 2026-10-24) | `90_REMEDIATION_PLAN.md` | done |

Sweeps 1c and 2 were done by the other agent in this worktree (2026-10-23);
this agent now works 11 → 19 (the owner's order) and never touches 3-10.

## Counts

P0: 0  P1: 7  P2: 39  P3: 158  Idea: 6  (all 53 findings files; counted from the files themselves, not from the per-sweep lines below)

Sweep 3 added: P2 3, P3 9, Idea 1, no P0/P1. Sweep 1c added: P1 1, P2 2, P3 2.
Sweep 4a added: P1 1, P2 1, P3 6. Sweep 2 added: P2 2, P3 6, no P0/P1.
Sweep 4b added: P1 1, P2 1, P3 4. Sweep 4c added: P2 1, P3 5.
Sweep 5 added: P2 1, P3 5. Sweep 11a added: P2 1, P3 3, no P0/P1.
Sweep 11b added: P3 4. Sweep 11c added: P3 2, no P0/P1/P2.
Sweep 6 added: P2 2, P3 4, no P0/P1. Sweep 7 added: P3 4, no P0/P1/P2.
Sweep 8 added: P2 1, P3 4, no P0/P1. Sweep 9 added: P3 2, no P0/P1/P2.
Sweep 10 added: P3 4, no P0/P1/P2.
Sweep 12a added: P1 1, P2 2, P3 3 (the P1 is AUD-12a-1, below).
Sweep 12b added: P2 1, P3 1, no P0/P1 (the P2 is AUD-12b-1).
Sweep 12c added: P2 1, P3 1, no P0/P1 (the P2 is AUD-12c-1).
Sweep 15 added: P3 8, no P0/P1/P2 (5 in `sign_in`, 3 in `backup`).
Sweep 12d added: P2 1, no P0/P1/P3 (the P2 is AUD-12d-1, a lock-order inversion).
Sweep 12e added: P2 2, P3 1, no P0/P1 (the P2s are AUD-12e-1, a lost create
response destroying the only group key, and AUD-12e-2, read-modify-write trust
JSON releasing an unconfirmed member).
Sweep 16 added: P2 1, P3 5, no P0/P1 (the P2 is AUD-16-1: a signed theme pack
that parses but cannot be drawn is accepted, and once chosen it throws in
`MaterialApp` on every launch).
Sweep 12f added: P2 1, P3 2, no P0/P1 (the P2 is AUD-12f-1: a delete, edit,
reaction, poll vote or RSVP that fails to decrypt is dropped silently, because
the quarantine rule repairs only `urgent` envelopes).
Sweep 12g added: P2 2, P3 2, no P0/P1 (the P2s are AUD-12g-1, the identity and
the session written in two commits so a crash between them strands a
"running" engine with no session, and AUD-12g-2, every new-device flow keeping
its generated keys in memory until the server call returns).
Sweep 12h added: P2 1, P3 1, Idea 1, no P0/P1 (the P2 is AUD-12h-1: a device
signed in with the password keeps no profile key, mints a second one on the
first own-profile save, and from then on cannot read its own photo, so a
name-only save drops it for everyone).
Sweep 17 added: P3 7, no P0/P1/P2 (3 in `17a`: an unguarded start-up storage
fault leaves the launch screen forever, a transient launch failure strands a
still-valid saved session until restart, and the console's segmented control is
44 px high; 4 in `17b`: a `StateError` when a report is resolved under the
"All" filter after a refresh, a one-time code destroyed by the system back
button, an audit kind filter that hides later pages behind an "empty" state,
and a dashboard refresh racing a toggle back to its old value).
Sweep 12i added: P2 1, P3 1, no P0/P1 (the P2 is AUD-12i-1: a failed edit,
reaction, vote, RSVP or "delete for everyone" op is dropped silently after the
local row already changed, and a second delete is refused because the local row
is already marked deleted).
Sweep 18 added: P2 1, P3 4, no P0/P1 (the P2 is AUD-18-1: every step of
`remote_release_gate.ps1` that matters tests `$?` after a `Pop-Location` and so
cannot fail, including both release builds. The P3s: AUD-18-2, the weekly and
manually dispatched CI run is gated on a path filter that describes only the
tip commit, so it verifies nothing whenever the last commit touches no watched
path; the dependency register's version check silently skips nine rows while
the register says "any table"; the lockfile policy claims the governance
checker covers claims it does not check; and the performance-budget doc's
runnable commands name files and a `backend/` directory that do not exist).
Sweep 12j added: Idea 1, no P0/P1/P2/P3 (presence and push are sound; the idea
is that `PushService.unregister` promises a notifications-off path no screen
offers, so server wake-ups can only be stopped by signing out).
Sweep 12k added: P2 1, P3 1, no P0/P1 (the P2 is AUD-12k-1: offline catch-up
rings the oldest parked offer, not the newest as documented, so every newer
caller is refused "busy" and logged missed; the P3 is AUD-12k-2: `release()`
finishes a live call outside the call queue, racing an in-flight accept).
Sweep 12l added: P3 4, no P0/P1/P2 (AUD-12l-1: a failed media setup leaks the
peer connection and its ICE callback can add to a closed stream; AUD-12l-2:
the ICE config claims a server-side relay enforcement that cannot exist behind
sealed signals; AUD-12l-3: the call-metrics route has no producer, so
`call_metrics` stays empty; AUD-12l-4: the ICE-restart path is unreachable —
no caller, no wire signal, and the adapter drops the offer).
Sweep 12m added: P3 3, Idea 1, no P0/P1/P2 (AUD-12m-1: the Storage page and
"free up space" count and delete the device's copies of *sent* media, which stop
being re-fetchable 30 days after the upload; AUD-12m-2: `cancel` decides from a
pre-transaction snapshot, so a download that finishes in the gap is reset to
"not downloaded" with its file still on disk; AUD-12m-3: `retryFailed` runs
every job's retry, including the send path, inside one write transaction;
AUD-12m-4 is the Idea: three media-kind classifiers that already disagree).
Sweep 12n added: P3 4, no P0/P1/P2 (AUD-12n-1: `stop()` is not a barrier — a
job claimed across its single cancellation sweep starts after it returns;
AUD-12n-2: a lapsed lease lets the worker claim a job it is already running,
and the old heartbeat keeps renewing the new lease; AUD-12n-3: a permanent
local I/O error (disk full, permission) is classified `internal` and retried
for 30 days while its held op freezes every later message in the chat;
AUD-12n-4: a presigned (S3) upload reads the whole ciphertext into memory,
with no size cap, and an OOM becomes the same 30-day retry).
Sweep 12o added: P3 2, no P0/P1/P2 (AUD-12o-1: the cap for a whole-object
download is computed with the largest legal chunk size, but ciphertext grows
with more chunks, so a thumbnail sealed at the default 64 KiB and larger than
64 KiB exceeds the cap and fails permanently as `size_mismatch`; AUD-12o-2: a
failed upload keeps its whole ciphertext in `up-<jobId>` for ever, because the
janitor keeps any job not `done` and nothing else deletes it).
Sweep 12p added: P3 4, no P0/P1/P2 (AUD-12p-1: an offer stays on the
receiving device five days after the sender's 48 h `relayTtl` deleted its
relay objects, so accepting on days 3-7 always ends `expired` and the sender
no longer knows the transfer existed; AUD-12p-2: the auto-offer cursor is
written before `send` and every failure is swallowed, so a device that joins
while the designated sender is offline is never offered history by anyone;
AUD-12p-3: a pause turns the offer into `waiting` with no error — exactly the
shape `_resumeOffers` calls "fresh" — and the pause's own write is what wakes
that hook, so with auto-accept on the transfer restarts at once; AUD-12p-4:
`watchOffers` reports 0 segments fetched during a download, and the app's
receiving rows read only that stream, so the bar never moves until import).
Sweep 12q added: P2 1, P3 2, no P0/P1 (the P2 is AUD-12q-1: deleting a
message for yourself, clearing a chat or deleting a chat removes the rows and
writes no tombstone, so the next restore or version-conflict catch-up puts them
back with unread +1 — and the catch-up runs automatically; AUD-12q-2: the
archive never records that the export was truncated, so a capped restore looks
complete on both ends; AUD-12q-3: a full backup made under another identity is
merged into the phone and only then refused, and the server test pins the
merge).
Sweep 12r added: P1 1, P3 3, no P0/P2 (AUD-12r-1 is the P1: the receive cap
for a relay object is computed with the 1 MiB max chunk size while the segment
is sealed at the 64 KiB default, so every transfer segment over 64 KiB
exceeds its own cap and the API's capped reader throws — with the default
4 MiB segments, every history transfer over 64 KiB fails on segment 0, and
every test pins 3 000 or 20 000-byte segments and a fake relay that ignores
`maxBytes`. AUD-12r-2: a kill during download or import leaves the offer in a
phase nothing resumes and whose only button (Pause) is a no-op. AUD-12r-3:
the sending side lives only in a non-replaying event stream, so the sender
never learns done or declined and cannot cancel after a restart. AUD-12r-4:
the twenty-first unanswered offer is refused silently.)
Sweep 13 added: P2 2, P3 5, no P0/P1/Idea (the P2s are AUD-13-1: the CLI
accepts any `http://` server, so the password-derived auth key and the bearer
tokens cross the network in cleartext — the app refuses the same address
through `ServerPolicy` and the crypto doc records HTTPS enforcement as closed
on that basis — and AUD-13-2: `helix_v2 send` prints "sent" for a message the
outbox has already marked `failed`, which is exactly what a blocked recipient
produces. The P3s: AUD-13-3, `devices revoke` matches a prefix against a list
that a fire-and-forget refresh may not have filled; AUD-13-4, the first Ctrl-C
is swallowed and interactive `chat` never observes it; AUD-13-5, `react` only
reaches the newest 200 messages while the `all` flag that would help is unused;
AUD-13-6, `db.key` is created with the process umask, i.e. 0644 on POSIX; and
AUD-13-7, the end-to-end CLI test's "no unread" assertion can never fail.)
Sweep 14a added: P2 2, P3 2, no P0/P1/Idea (the P2s are AUD-14a-1: a setting
stream resolves the runtime once and never again, so a provider first read on
the sign-in page stays in `NoServerChosen` for the whole run and an account
switch leaves Settings on the previous account's closed database; and
AUD-14a-2: an account list that is empty *or undecodable* is read as "no
accounts", after which every folder under `accounts/` is deleted with its
database and key at start. The P3s: AUD-14a-3, `HelixRuntime.close` skips the
rest of its teardown when one step throws but releases the lease regardless;
AUD-14a-4, the app sends its phone model in `x-helix-client`, which the wire
documents as `<platform>/<app version>`.)
Sweep 14b added: P3 4, no P0/P1/P2/Idea (AUD-14b-1: a VPN on mobile data is
classified as unmetered, so "Wi-Fi only" downloads and the backup upload gate
run over mobile data; AUD-14b-2: a call longer than the relock time suppresses
the relock and nothing re-applies it when the call ends; AUD-14b-3: after the
phone's screen lock is removed the app lock cannot be passed and the screen does
not say why; AUD-14b-4: every resume on the sign-in screen throws
`NoServerChosen` into the crash log. The certificate pin, the clipboard
handoff, the share seam, the picker cleanup and the cold-start decision were
read and are sound.)
Sweep 14c added: P3 3, Idea 1, no P0/P1/P2 (the JPEG/PNG/WebP stripper, the MP4
box cleaner and the BlurHash encoder were read byte by byte and are careful.
The findings are outside them: AUD-14c-1, a file is a photo because of its
extension, so a `.heif`/`.avif`/extension-less photo is sent with its EXIF
intact; AUD-14c-2, the profile crop decodes the full-size picture and leaks its
codec and image on any failure; AUD-14c-3, one unreadable file in a multi-pick
discards the whole selection; AUD-14c-4 (Idea), GIFs are passed through
although Comments and XMP can carry text.)
Sweep 14d added: P3 2, no P0/P1/P2/Idea (AUD-14d-1: the media processor reads
and copies the whole picture before applying its 96 MiB cap, so the cap costs
the memory it was meant to save; AUD-14d-2: renaming a person in Helix writes a
fresh `Name(first:)` into the phone's contact, dropping its middle, family and
prefix. The blob store's resume write, storage accounting, camera, video
frame, phone-number normaliser, file actions and key store were read and are
sound.)
Sweep 14e added: P3 2, no P0/P1/P2/Idea (AUD-14e-1: a refused playback
speed is caught as a load failure, so a playable voice note reports "audio not
available"; AUD-14e-2: a microphone capture failure is swallowed by the
recorder, so the clock keeps running and the note is sent with a longer duration
than its audio. The recorder's pause/resume clock, the waveform merge, the
video player's completion and disposal, and the seam's lifetimes were read and
are sound.)
Sweep 14g added: P3 7, no P0/P1/P2/Idea (AUD-14g-1: a later background wake
replaces the message notification with only that pass's count, so the shade
under-reports; AUD-14g-2: `onlyAlertOnce` makes every message after the first
silent; AUD-14g-3: removing an account leaves its notifications, with preview
text, in the shade; AUD-14g-4: a press on a message notification of the account
already open navigates nowhere; AUD-14g-5: a missed call in a muted chat is
posted although the engine computes `muted` for exactly that decision;
AUD-14g-6: the missed-call path treats `inactive` as away while every message
alert treats it as on screen; AUD-14g-7: one failed Firebase start is cached,
so push stays off for the rest of the process. The wake isolate, the payloads,
the ringtone channels, the call actions and the previews gate were read and are
sound.)
Sweep 14f added: Idea 1, no P0/P1/P2/P3 (AUD-14f-1: a `helix://contact/add`
link is parsed with a signed payload — id, account, nonce, expiry, signature —
that no code reads; it opens the people search instead, a leftover of the
dropped contact-request design. The link parser, the code codecs, the link
channel and parking, the listener and the router's redirect were read and are
sound.)
Sweep 14h added: P3 3, no P0/P1/P2/Idea (AUD-14h-1: every `crash` record
cancels and restarts the 2 s send timer, so a crash that repeats faster than
that — a widget throwing every frame — postpones its own report until it stops
and overflows the 200-entry queue in the meantime; AUD-14h-2: ringtone copy and
channel cleanup match pack ids by the prefix `<id>.`, so deleting `a.b` also
deletes the chosen `a.b.c`'s copy and channel and calls silently fall back to
the phone's tone while Settings still names `a.b.c`; AUD-14h-3 (likely): two
publishes of the same ringtone share one `.part` file and are not serialised,
so a double tap can expose a half-written copy or revert a valid choice. The
pack gate's one-audio-file guarantee, the exported single-folder provider,
write-then-rename in the single-writer case, the built-in shadowing, the
masking and queue caps, and FrameWatch's thresholds were read and are sound.)
Sweep 14i added: P3 2, no P0/P1/P2/Idea (AUD-14i-1: `_daysBetween` measures
local midnights by elapsed time and truncates, so after a spring-forward the
previous calendar day is 23 h away and reads as "Today" — chat list times, the
day separator, last-seen, message info and the call log all shift by a day;
AUD-14i-2: a search snippet cuts its twenty characters of context with
`substring`, which can split an emoji's surrogate pair, so the row starts with a
replacement glyph. The naming order, the chat facade and its forward gate, the
notice/preview keys against the protocol bodies, the group notices' sender =
actor rule, the renderer's range clamp, the call seam and `combineLatest2` were
read and are sound. A suspected lowercase-offset bug in `snippetFor` was traced
and rejected: the Dart VM's `toLowerCase` is simple case mapping and preserves
length on every target this app has.)
Sweep 14j added: P3 2, no P0/P1/P2/Idea (AUD-14j-1: `ThemePackStore._pack`
catches only `FormatException` and `PackFolder._read` only
`FileSystemException`, while `OrbitTokens.fromThemeJson` also raises
`_TypeError` and `ArgumentError` — so one signed theme whose gradient refers to
a missing token, whose `transform` this build does not ship, or whose `name` is
not a string makes every read of the pack folder throw: start-up silently falls
back to Orbit with all downloaded themes gone, the gallery's installed rows
vanish, and `ThemePackActions.remove` reads the pack before deleting it, so the
bad pack cannot be removed in-app. AUD-14j-2: `hostedPacks` probes up to 64
manifests one after another inside an `autoDispose` provider, so More themes
re-pays up to 64 sequential round trips on every visit and sits on "loading"
for their sum. The built-in shadowing rule, the chosen-theme validation and
fallback, the two pack-trust read modes, the install order (caps → download →
gate → rename → prune), the slug and content-addressed paths, and the device
settings' tolerant read were read and are sound.)
Sweep 19 (synthesis) added no findings. Rebuilt on 2026-10-24 from every
findings file, it merges the 210 into `90_REMEDIATION_PLAN.md`: 25 batches and
T4, ordered first by the instrument (B1 repairs the release gate that reports
success for failed steps), then by reach (who can trigger × who is hurt ×
whether it is silent), then by fix coupling (one batch per code seam and test).
Every finding appears exactly once in the appendix, and the rebuild
machine-checked each id, its severity and its one batch against the files (210
of 210). Ten owner decisions (Q1–Q10) block eight of the batches (B2, B5, B8,
B14, B15, B17, B24 and T4). The plan states, per batch, the rollout class
(server migration, wire-adjacent, app-only, config, or decide-first), the test
that proves it, and the order in which the halves must land. The appended
batches B19–B25 now sit under their own Tier 3 heading, before the
decisions-and-ideas tier, rather than after the cross-cutting notes.

## Highest-risk so far

1. AUD-4b-1 (P1) — any account can add people to a group (default privacy)
   and loop add/remove; each change stores a `roster_change` per member
   device, and the 10,000-row quota then trims victims' oldest undelivered
   messages. Wider reach than AUD-4a-1.
2. AUD-4a-1 (P1) — block/unblock stores a `block_change` envelope for every
   target device on each flap, with no per-account limit. Filling an offline
   mailbox makes the 10,000-row quota trim the victim's own oldest undelivered
   messages: silent remote data loss, no prior relationship needed.
3. AUD-1b-1 (P1) — a dead outbox job keeps its dedupe key forever; every
   later push (`push:<reason>:<device>`) or group relay (`gdev:…`) with that
   key is silently dropped. No automatic purge/requeue.
4. AUD-1c-1 (P1) — every S3 request has no timeout; a stalled store hangs
   media requests, and readiness probes accumulate in-flight HEADs (the 3 s
   health timeout does not cancel the request).
5. AUD-1a-1 (P1) — unauthenticated slow client holds the node body budget
   forever; no body-read deadline. One IP can 503 all buffered-body routes.
6. AUD-3-3 (P2) — a presence route outlives its node by up to 75 s;
   `deliverEphemeral` reports those devices as reached, so call offers are
   neither delivered nor parked and the caller sees a normal ring.
7. AUD-3-1 (P2) — ephemeral and urgent fan-out cost O(devices) DB round trips
   (~2,200 at the 1,100-device cap) and ephemeral sends are uncharged; one
   authenticated request amplifies into thousands of statements.
8. AUD-3-2 (P2) — a crash between the expiry sweep's DELETE and its pending
   updates inflates `pending`, so later sends trim undelivered envelopes early
   (silent message loss).
9. AUD-2-2 (P2) — no per-account cap on devices; one account can make key
   bundles, fan-out and prekey storage grow without bound.
10. AUD-2-1 (P2) — a failed SMS send still spends the number's hourly
    allowance and the server's daily text budget; an outage outlives itself.
11. AUD-1a-3 (P2) — idempotency `find`→run→`save`: concurrent duplicates both
    execute; impact depends on which routes mint one-time secrets.
12. AUD-1b-2 (P2) — periodic lease `max(60 s, interval)` is shorter than the
    5-minute job timeout, so a slow periodic job can run twice at once.
13. AUD-1a-2 (P2) — path params percent-decoded twice (latent `/`, `..` in a
    param; no live sink found yet). **Closed as not a bug in B4 S6**: Dart
    hands `Uri.path` over still percent-encoded, so the registry's decode is
    the only one; the tests added there pin it.
14. AUD-1b-3 (P2) — the plan's claimed EXPLAIN hot-path tests do not exist
    (mailbox fetch/ack are on the list).
15. AUD-4c-1 (P2) — a member server checks the cached roster version outside
    any row lock, so an older snapshot can overwrite a newer one and re-add a
    removed member to its local cache; guarded by timing, not by SQL.
16. AUD-11a-1 (P2) — the API's one 30 s deadline covers the whole body;
    full/history backup (32 MiB), export and presigned uploads cannot finish
    on mobile links, and PUT/GET retries restart from byte 0.
17. AUD-5-1 (P2) — deleting an account frees its media only through one
    8-attempt, 5-minute outbox job that loads the whole row set first;
    `persistent` media have no expiry and objects have no account FK, so a
    dead-lettered purge keeps avatar/group blobs forever.
18. AUD-6-1 (P2) — call metrics keep a free-text `outcome` per record with
    1 MiB bodies allowed and 100 writes/account/day: ~9 GB per account over
    the 90-day window, with no account column and an unindexed cleanup scan.
19. AUD-6-2 (P2) — federation reads peer responses with no size cap, and the
    inbound path fetches the peer's identity document *before* checking a
    signature, so a hostile peer streams until the node's memory is gone.
20. AUD-12a-1 (P1) — when a session ends (refresh and device-key sign-in both
    refused), the account row stays and `_requireEmpty` refuses every
    sign-in, register and link: the app shows "Could not sign in" on the
    sign-in page and the only exit deletes the local history. A server
    restored from a backup turns this into a fleet-wide lockout.
21. AUD-12b-1 (P2) — every `GroupException` from an outbox op is a permanent
    give-up, so one `version_conflict` (already retried 4×) or a `noGroupKey`
    race silently kills the post-removal key rotation: no epoch key is made,
    group renames/avatars fail for every member, and the removed member keeps
    the old epoch key. A rekey op has no message row, so the retry button
    cannot reach it.
22. AUD-12c-1 (P2) — `_insertMessage` awaits `_delivered` twice, so every
    arriving message queues two delivered receipts (distinct ids, so the
    outbox dedupe does not merge them): double pairwise sends, ratchet steps
    and receipt rows for every message in every chat.
23. AUD-12d-1 (P2) — lock-order inversion: `PeerDirectory` opens a transaction
    and then waits for a device session lock (`_applyKeyChange`/`dropDevice`
    → `_clearSessions`), while senders and the inbound applier take that lock
    and then wait for the transaction. Drift serializes transactions, so an
    engine can hang forever on a key change that overlaps a send or apply.
24. AUD-12e-1 (P2) — a group create whose response is lost (timeout after the
    server committed) forgets the only copy of the master key; the group is
    left nameless for every member, cannot be renamed (`_updateState` needs the
    key) and cannot be re-keyed (`rekey` refuses an empty title), and a retry
    creates a duplicate.
25. AUD-12e-2 (P2) — group trust state is one JSON document mutated
    read-modify-write with no CAS: a user confirm racing a roster apply can
    erase a pending entry, and the member is then handed this device's sender
    key and the group key permanently (the "keys are what is withheld" gate).
26. AUD-16-1 (P2) — a signed theme pack whose document parses but is missing a
    token (or carries a pattern param the painter needs) is accepted by the
    store and offered on More themes; choosing it makes `HelixRemoteApp.build`
    throw above the router, and the persisted choice repeats it on every
    launch until the app's data is cleared.
27. AUD-12f-1 (P2) — message actions are sent non-urgent, and quarantine
    decides "worth repairing" from `urgent`, so a `DeleteBody` (or edit,
    reaction, poll vote, RSVP) that arrives while the sender key is out of
    step is dropped with no placeholder and no reset request: "delete for
    everyone" silently fails on that device and the author is never told.
28. AUD-12g-1 (P2) — the identity block and the session are two commits; a
    crash between them leaves an identity with no session, which `start()`
    reports as running, which neither `accessToken` nor `refresh` repairs, and
    whose only exit is `signOut()` — a full local wipe.
29. AUD-12g-2 (P2) — register, recovery, password sign-in and link accept all
    store the generated AIK/device keys only after the server call; a lost
    response leaves the account on a server with no local key (for recovery:
    the code is spent, every other device is signed out and the backup is
    already deleted).
30. AUD-12h-1 (P2) — `signInWithPassword` arrives with no profile key and no
    wrap carries one, so the first own-profile save mints a second key; the
    device can no longer decrypt its own photo, `_ownPhoto` swallows the error,
    and the next name-only save writes `photo: null` over everyone's avatar.
31. AUD-12i-1 (P2) — action ops carry no message row, so a terminal send
    failure (a group key race, a crypto error, a permission flip) drops an
    edit, reaction or "delete for everyone" with no error, no retry, and — for
    a delete — no way to express it again: the local row is already deleted.
32. AUD-18-1 (P2) — `remote_release_gate.ps1` asks `$?` after a scriptblock
    that ends in `Pop-Location`, so its client, server (with a real database),
    API and both release-build steps report success when they fail; the
    checklist tells the operator to run this script as the release gate.
33. AUD-18-2 (P3) — the weekly and manual CI runs are gated on a path filter
    that describes only the tip commit's diff, so a cron run after an unrelated
    commit passes having run nothing — including the only unattended
    vulnerability scan.
34. AUD-12k-1 (P2) — a device returning with two parked offers rings the
    oldest (server order) while its doc and the app assume newest, busy-ends
    the newer caller and writes a missed row for them; the notification stack
    shows a full-screen ring per offer whose Answer press is then ignored.
35. AUD-12r-1 (P1) — the device-to-device history transfer fails for every
    segment over 64 KiB: the receiver caps the download with the 1 MiB max
    chunk size while the segment was sealed at the 64 KiB default, so the
    API's capped reader throws on the first segment of any history over
    64 KiB (the app ships 4 MiB segments). Every test uses 3 000 or
    20 000-byte segments and a fake relay that ignores the cap.
36. AUD-13-1 (P2) — the CLI accepts any `http://` server, so the
    password-derived auth key and the bearer tokens cross the network in
    cleartext; the app refuses the same address through `ServerPolicy` and
    `CRYPTO_V2.md` records HTTPS enforcement as closed on the strength of that
    app-side rule, which the CLI never applies.
37. AUD-14a-2 (P2) — a keystore account list that is empty *or undecodable*
    is taken as "no accounts", and every folder under `accounts/` is then
    deleted with its database, WAL files and key at the next start: a second
    account's local history goes with no prompt, on a restore onto new hardware
    or a truncated keystore write. The first account is exempt only because its
    files are not under `accounts/`.
38. AUD-14a-1 (P2) — `settingProvider` resolves the runtime once at first read.
    Read on the sign-in page (the app does this at start for the media policy),
    it stays in `NoServerChosen` for the run, so "Wi-Fi only" is never enforced
    that session; read before an account switch, it follows the closed old
    database while writes land on the new account.

## Open questions for the owner

Ten: Q1–Q5 are unchanged — (1) should ephemeral sends draw a small per-account
unit budget (they store nothing today, so only the send-rate limits bound
fan-out)? (2) should `block_change` remain a stored envelope, or become an
online-only signal now that a stored one can trim a victim's mailbox? (3) when
an export is huge, should it be capped with a `truncated` flag, streamed, or
refused? (4) should the platform-credential backup wrap ship, with the recovery
secret as fallback? (5) should opening a backup cap the Argon2id work its
header can demand? The synthesis added four more, all found while deciding how
to batch a finding: (6) how is a "session ended" device recovered — re-enrol the
same account in place, or a distinct state with its own screen? (7) how many
devices may one account hold? (8) should there be an in-app way to stop server
wake-ups, or is the OS setting the whole answer? (9) do call-quality telemetry
and ICE restart ship — wire them, or delete both dead paths? The rebuild added
one: (10) should the anomaly queue be per server, or is a device-global crash
log the stated contract? See `99_OPEN_QUESTIONS.md` for options and
consequences.

The batch order is not this list's order: `90_REMEDIATION_PLAN.md` ranks by
reach and fix coupling (a P2 any stranger can aim at any stranger before a P1
one account aims at itself), and it names the one batch that must land first —
the release gate, because it currently reports success for failed steps.

## Notes on method

- Budget: ~8-10 files / ~1,500 lines per sweep; splits get `a`/`b` files.
- Sweep 3 read ~1,930 lines (messaging 1,367 + realtime 533 + presence 28 +
  cost checks in platform and four call sites). Slightly over budget; the
  message module is one unit and splitting it would repeat the api surface.
- Sweep 4a read ~1,350 lines (people 886 + cross-checks: messaging deliver/
  mailbox, pipeline/routes, admin, protocol, groups call sites).
- Sweep 4b read ~1,600 lines (groups module 1,273 + docs/api/frame + protocol
  and messaging call sites).
- Sweep 4c read ~1,300 lines (`group_store.dart` 640, `federation.dart` 607,
  ~40 cross-check lines).
- A finding is only written with lines to point at; guesses stay in the
  coverage-gap/open-question sections.
- Sweep 11a read ~1,250 lines (transport/auth/errors/retry/facades) plus
  targeted cross-checks in backup, compliance, media, identity clients, the
  protocol catalog and the server's idempotency gate.
- Sweep 5 read ~1,420 lines (backup 268, media 481 + api, object storage 340,
  docs/routes/identity/jobs cross-checks).
- Sweep 11b read ~790 lines (realtime client 597 + socket adapters) and the
  realtime tests' names; 11c read ~950 lines (all twelve clients + engine
  sender/outbox and the pipeline's error mapping).
- Sweep 6 read ~2,165 lines (calls 633, federation 592 + peers 392 + config 72
  + store 97, protocol call DTOs, messaging `checkDevices` and block wiring,
  the calls tests). Over budget; the two modules are one wire contract.
- Sweep 7 read ~2,266 lines (ops 935 incl. two static pages, admin 1,223,
  compliance 108) plus the catalog, the maintenance gate, the JWT kernel, the
  export/paging queries the two modules call, and the pack tool's publish path.
- Sweep 8 read ~4,000 lines of protocol core (bodies 1,132, routes 987,
  envelope 332, json 242, messaging 235, realtime 234, sealed 182, errors 172,
  content 318, plus small files) and all 9 fixtures; the 4,557 lines of
  `modules/` DTOs were pattern-scanned and covered by the round-trip test, not
  read line-by-line. Over budget by design (one package, one wire contract).
- Sweep 9 read ~4,100 lines: every file in `crypto/lib/src/v2/` line-by-line,
  plus ~1,600 lines of tests targeted (layout, misc, session, sender keys,
  vectors) and cross-checks in the engine's session store, `PairwiseCrypto`,
  backup restore, the app's backup gateway and the provisioning size cap.
  One package, one crypto core; over budget by design.
- Sweep 12a read ~2,200 lines: `engine.dart` 663, `events.dart` 194,
  `errors.dart` 182, `context.dart` 64, `maintenance.dart` 119, `config.dart`
  141, `util/` 133, plus cross-reads in `account_service.dart` (sign-in,
  linking, `_requireEmpty`, `deviceKeySignIn`), `key_maintenance.dart`,
  `inbound_runner.dart`, `crypto_dao.dart`, the api's `auth.dart`, the app's
  session/runtime providers, sign-in controller and copy, `helix_runtime.dart`
  and the account/security tests. Over the 1,500-line guide: the lifecycle
  findings only exist across those seams (engine + api + app), so cutting the
  cross-reads would have left them as guesses.
- Sweep 12d read ~800 lines (`pairwise_crypto` 195, `peer_directory` 295,
  `db_stores` 147, `local_identity` 76, `keyed_lock` 37, the session CAS in
  `crypto_dao` and the two crypto-package methods it drives).
- Sweep 12e read ~2,100 lines (`groups_service` 696, `group_roster` 601, and
  the cross-reads that settle it: `group_rekey` 167, `group_keyring` 196,
  `group_trust` 152, the roster DAO's `replaceRoster`, the server's create/add/
  join-request/device-stale handlers and the `StaleDevices` DTO). Over the
  1,500 guide: the two service files alone are 1,297, and both P2s only exist
  where they meet the keyring/trust writers.
- Sweep 12f read ~1,750 lines (`group_inbound` 598, `group_sender` 287,
  `sender_key_store` 147, `group_pipeline` 77, `group_ops` 76, `group_notices`
  64, `group_rekey` 167 re-read for its crash windows, the roster's state
  handling, and the cross-reads that settle the three findings: the direct
  inbound's quarantine/typing twins, `chats_service._sendAction` and its
  callers, `presence_service`'s typing path, and the outbox's urgent
  passthrough). The "a message that cannot be read" policy turned out to be
  the sweep's real subject: the crypto and the commit ordering are sound.
- Sweep 12g read ~1,400 lines (`account_service` 756 with the link half,
  `device_service` 158, `key_maintenance` 165, `session_token_store` 38, the
  engine's start/sign-out/delete slices, the API's `DeviceSessionAuth`, the
  server's takeover gate, and drift 2.34's `insertOnConflictUpdate` to rule
  out a lost-column upsert). Both P2s are ordering bugs in the same method
  pair, which is why they were kept separate: the fix sites do not overlap.
- Sweep 12j read ~700 lines (`presence_service` 164, `push_service` 24, the
  app's `push_registration` 157 / `push_background` 189 / `push_token_source`
  102, and the cross-reads that settle them: the direct and group typing
  branches, the server's `_accept` block and ephemeral paths, the push-token
  routes and the clearing on device removal, and `signOut`). A small sweep by
  design: both services are thin and the weight is in their callers.
- Sweep 12i read ~1,500 lines (`chats_service` 714 plus the outbox's
  classify/fail/give-up half (174-477), the read/remove/clear DAO queries, the
  message table's cascades and `foreign_keys = ON`, the app's message menu and
  its delete dispatch, the group info row and the server's disappearing test
  that pins the peer-side role rule, `apply`'s receipt and timer handlers, and
  drift 2.34's nested-transaction support).
- Sweep 12l read ~2,300 lines (`call_log_mirror` 54, `call_media` 106,
  `fake_call_media` 185, `call_models` 153, and the whole
  `helix_remote_calls` package: `web_rtc_call_engine` 660, `call_engine` 132,
  `call_devices` 124, `ice_config` 152, quality/setup/video 143; the app's
  seam `webrtc_call_media` 217, `call_media_hub` 112, providers and ringer 90;
  plus `apply`'s call-log branch, the calls DAO, the metrics client and its
  only test caller, the protocol's signal kinds and the release-readiness
  runbook). Over the guide because `helix_remote_calls` is one unit; the four
  P3s sit exactly at its seams with the engine and the server.
- Sweep 12m read ~1,750 lines (`media_service` 510, `transfers_service` 67,
  `transfer_config` 105, `transfer_views` 167, `media_settings` 54,
  `media_storage` 39, and the cross-reads that settle them: the transfer and
  message DAO queries the service layer calls (`_enqueue`/`claim`/`fail`/
  `remove`, `storedMediaByKind`, `detachLocalMedia`), the arrival path
  `inbound_media` 84, the runner slices that decide what a job resumes
  (`download_runner` 43-140 and 240-336), `outbound_media`'s send-completion
  and cancel halves, and `MessageStatus.advance`). The service layer is thin
  and honest; the defects are in what it counts, how it orders a cancel, and
  how much one transaction wraps.
- Sweep 12n read ~1,900 lines (`outbound_media` 779, `transfer_worker` 415,
  `upload_runner` 283, and the cross-reads that settle the four findings: the
  claim/due/renew/lease queries in `transfers_dao`, the held-op ordering in
  `outbox_dao.claimDueOrdered`, `MessageStatus.advance`, the download half the
  queue shares, `transfer_failure`'s classifier, and `transfer_files`' staging
  names). The upload path itself is disciplined (encrypt once, digest of the
  ciphertext, bounded resume, cancellation at every await); the defects are all
  in the queue's lifecycle — when a claim may start, whether a lease can hold
  two owners, what an unclassified error means, and what a presigned target
  costs in memory.
- Sweep 12o read ~1,600 lines (`download_runner` 336, `blob_store` 165,
  `memory_blob_store` 196, `media_janitor` 103, `transfer_failure` 139, and the
  cross-reads that settle the two findings: `media_service`'s retry/cancel/
  download entry points, `outbound_media`'s failure half, the DAO's `_enqueue`/
  `enqueueThumbnail`/`live`, `inbound_media`, `media_settings`, the API's
  `MediaClient.download`, and the crypto's size arithmetic). The download path
  is the strongest code in the transfer area; both findings are about bounds,
  one computed with the wrong chunk size and one absent for failed uploads.
- Sweep 12p read ~1,900 lines (`backup_service` 409, `state` 422, `models`
  286, `options` 196, and the cross-reads that settle the four findings:
  `device_transfer`'s send/receiver/pause/cleanUp/senderOrder slices, the
  `OwnDevicesChanged` emit in `device_service` and its refresh in `engine`,
  the app's `backup_gateway`/`backup_providers`/`transfer_rows` and the
  runtime that pins both auto options off, and the engine tests that pin the
  pause). The ledger itself is disciplined — every change is a transaction,
  every pointer is bounded before it is fetched — and the defects are all in
  the automation around it: when the cursor moves, what "fresh" means, how
  long an offer claims to live, and what the offers list can honestly say.
  Two findings are latent only because the app sets the two auto options off;
  that is stated in each, not used to downgrade it.
- Sweep 12q read ~1,900 lines (`snapshot` 894, `full_backup` 344,
  `history_backup` 333, `archive` 247) and the cross-reads that settle the
  three findings: the three delete paths in `chats_service` and the DAO
  `removeMessages` they end in, the expiry skip in the importer, the export
  filter and `admit`, `RestoreResult`/`RestoreProgress` and the app's
  `backup_gateway`/recovery page that read `added` alone, the version-conflict
  path in `history_backup`, and the server's takeover test that pins the
  post-merge identity refusal. The recorder, the frame codec and the AEAD
  binding are sound; the three defects are all in what the archive does *not*
  carry — a local deletion, a truncation, an identity verdict before the
  merge.
- Sweep 12r read ~1,250 lines (`device_transfer`'s receiver half 240-667,
  `inbox` 57, `errors` 109, `state`'s ledger entry points 300-422 and the
  phase model, `transfers_dao`'s chunk half 375-453, the app's
  `transfer_rows`/`TransfersController`, the crypto's chunk constants and
  size formula, the api's `_readCapped`, and the three tests that should have
  caught the sizing bug). The P1 was found by following the *numbers*: the
  receiver's cap, the writer's chunk size, and the fake relay that ignores
  the cap. The state machine is disciplined; its problem is that two of its
  phases are persisted without any owner, and the sending side has no durable
  view at all.
- Sweep 12k read ~1,650 lines (`calls_service` 1,061, `call_signaling` 61,
  `engine_call_signaling` 192, `call_config` 49, `engine.dart:311-460` for
  start/reconnect/stop, the app's `call_host` 91 and the notification handler
  in `call_effects.dart`, the headless call notifications in
  `push_background.dart:142-178`, the server's calls-module pending/end/push
  paths, and the engine's pending-call test group). The state machine is sound;
  the one P2 is an ordering mismatch between the client's doc and the server's
  `ORDER BY created_at` that no test pins.
- Sweep 12h read ~1,500 lines (`people_service` 699, `phone_book` 37,
  `settings_service` 106, and the cross-reads that settle the profile-key
  fork: `apply.dart`'s control switch and `_profileKeyUpdate`, the outgoing
  message's profile key in `chats_service`, crypto's password wrap and link
  provisioning, `account_service`'s four sign-in paths, the people/account
  DAOs, the server's `setPhoneDiscoverable` and discovery-salt route, the app's
  phone-book writer and its same-day sync guard, and drift's upsert to rule
  out a lost-column write). `settings_service` moved here from 12i because its
  one real hazard is the own-name save.
- Sweep 12c read ~1,600 lines (`apply` 852, `inbound` 528, `content_codec`
  113, `kinds` 42, the deferred-action DAO queries and the maintenance purge),
  with no structural proposal: the applier is one cohesive unit.
- Sweep 12b read ~2,000 lines (`outbox` 482, `sender` 268, `inbound_runner`
  292, `outbox_dao` 313, group ops/pipeline/keyring/sender/rekey 803) plus
  cross-reads in `groups_service`, `group_inbound`, `engine.dart`, the app's
  sign-out action, `push_background` and call signaling. Over the 1,500 guide:
  the rekey finding only exists where the outbox classifier meets the group
  rotation path.
- Sweep 10 read ~3,900 lines of `lib/` (all eleven DAOs, opening, migrations,
  `HistoryStore`, tables, FTS) and ~1,900 of tests, plus cross-checks in the
  engine's maintenance, transfer and backup paths and drift 2.34's sqlite3
  delegate (which begins transactions `IMMEDIATE`, closing the CAS question).
- Sweep 15 read two features end to end (sign_in 1,540 + backup 1,809 lines,
  17 files) and cross-read the server's `requireE164`, `requestPhoneChallenge`,
  `register`/`_replaceIdentity`, the API's `ApiException.lockedUntil`, the
  engine's `device_service`, `backup_service`/`TransferLedger`, the app's
  `phone_numbers.dart`, `failure_copy.dart`, `post_sign_in.dart`, and the Orbit
  screens only where a model's consumer settles the finding (the take-over
  warning, the recovery page's delete confirmation). Two files rather than one
  because the two features share no code; 9 of `lib/features/`'s 11 remain.
- Sweep 16 read the whole `theme/` folder (2,009 lines: tokens + generated
  getters, theme, metrics, text, motion, effects, the painters), the pack pages
  and managers (theme 261 + 289, ringtone 269 + 332), the pack store's read/
  install/decode path in `core/theme/orbit_packs.dart` (~330 of its 777), the
  domain gate's theme checks, `main.dart`'s start-up, the a11y primitives
  (button 158, icon button 97, fields 475, `OrbitTapArea`), and the tests that
  are supposed to hold these (tokens, theme packs, accessibility, primitives).
  Plus the Flutter SDK's `ThemeData.lerp`/`AnimatedTheme` to settle the
  cross-fade direction. Two files because tokens/packs-data and pack-pages/a11y
  fail differently and deserve separate fixes.
- Sweep 17 read the console end to end (~3,900 lines of `lib/`): the shell and
  session machine (`app.dart` 147, `admin_session_controller.dart` 486,
  `admin_session_scope.dart` 27, `token_vault.dart` 83, `device_lock.dart` 44,
  `admin_settings.dart` 57, `admin_services.dart` 31), the shared paging
  controller and list (`feature_controller.dart` 138, `paged_list.dart` 139,
  `dialogs.dart` 333, `console_kit.dart:240-419`), the pages (accounts 348 +
  detail 566, settings 598, reports 301, invites 189, audit 196, logs 303 +
  controller 190, dashboard 438 + `server_controller.dart` 221 + the metrics
  parser 109, shell 438, sign-in 212, lock 107, format 63, error text 87,
  `server_address.dart` 91). Cross-reads: the v2 admin client's `logStream`/
  `logs`/`purge`/`metrics`, the protocol's paging limits, the transport's
  redirect and timeout handling, the raw socket adapters, and the Dart SDK's
  `shouldCopyHeaderOnRedirect` and redirected-body behaviour (to rule out a
  bearer leak). Plus the console's five test files and its harness. Two files
  because the session/start-up defects and the page-level ones share no fix
  site. Soundness findings were dropped only after reading their wiring: the
  `checkServer` late-response race (`addressEdited` cannot run while `_busy`),
  the log stream's web fallback (the client reports the platform error through
  the stream), and the invites flicker.
- Sweep 18 read the CI workflow (238), both verify shells (128 + 179),
  `coverage.sh` (89), the release gate (126), the three `tool/` scripts (381 +
  30 + 48), the two dependency documents (66 + 161), `PERFORMANCE_BUDGETS.md`
  (150), the regression matrix (90) and the checklist lines that name the gate
  (~1,250 lines total), plus targeted cross-checks: every `HELIX_*` name in
  `server/lib/src` and `server/bin` against the handoff's env table (52 names,
  no drift), the two lockfiles' tracked state with `git ls-files`, the resolved
  package count against `generate_sbom.dart`'s output (239 of 239), the
  `dorny/paths-filter` README for the schedule/base semantics, and — for the
  release gate — an actual PowerShell run of the script's exact step shape
  (the `$?`-after-`Pop-Location` result was measured, not assumed). The sweep
  stayed inside its line budget by sampling rather than reading the 250 KB of
  remediation-plan history.
- Sweep 19 read no product code by design; it re-read the 36 findings files,
  the index, the open questions and the structural proposals (the headings and
  hazards only), then built a machine inventory of every finding (id, severity,
  confidence, title) to make the assignment auditable rather than counted by
  hand. The appendix in the plan is generated from that inventory, and the
  build asserts every finding id exists in exactly one batch (151 of 151, no
  phantom ids) before the table is written. Two findings (12k-2, 12l-2) were
  re-read in full to place them by fix site rather than by their file's subject.
- Sweep 13 read the whole CLI (~1,415 lines of `lib/`, `bin/` and `test/v2/`)
  and the harness that wraps every client test (`test/client/engine/support`
  170, `cli_test` 278, `test/support/{harness,flows,test_client,test_platform,
  test_database}` 590), plus cross-reads in `engine.dart:323-370` (what start
  and `_activate` run unawaited), `device_service.dart:22-58`,
  `outbox.dart:336-395,426-477`, `values.dart:23-50`,
  `app/lib/core/engine/server_policy.dart`, `docs/protocol/v2/CRYPTO_V2.md:
  572-583`, and a survey of the other eleven client test files by file size
  and test names rather than reading them. The two P2s came from following one
  question each across the seam: which client applies the address rule (only
  the app), and what "sent" means to the outbox (six statuses, one of them
  terminal failure).
- Sweep 14a read `app/lib/core/engine/` in full (10 files, 1,420 lines) with
  cross-reads of `core/platform/{engine_lease,account_slots,app_storage,
  contacts_access,device_phone_book}.dart`, the two settings files that consume
  the seam (`settings_providers`, `media_policy_sync`), `main.dart:160-200`,
  the engine's `close`/`stop`/`signOut`, the header contract in
  `helix_remote_protocol`/`helix_remote_api`, and the four tests that cover the
  area. The two P2s both came from following the runtime's lifetime outwards:
  who still holds it after it is replaced (every setting stream, made at first
  read and never rebuilt), and what the app concludes when the list of
  databases to keep cannot be read (that there are none, and they can go).
- Sweep 14b read the app's security and process glue in full (11 files, 1,218
  lines) with cross-reads of the call effects that hold the lock bypass, the
  settings page's enable-time check, the runtime's pinning and backup gate, and
  `main.dart`'s two error handlers. The four P3s each came from asking what the
  app remembers after the thing it answered about has changed: which interface
  a VPN rides (14b-1), a relock decided once and vetoed by a live call (14b-2),
  a credential checked only at enable time (14b-3), and a runtime asked for on a
  page that has no server (14b-4).
- Sweep 14c read the whole attachment-preparation path (nine files, 1,608
  lines) and traced one file from the picker to the composer. The byte-level
  cleaners survived line-by-line reading; every finding is at a seam: the name
  decides the kind (14c-1), the profile crop decodes unbounded (14c-2), and
  `_pick`'s single try loses the batch (14c-3). The GIF pass-through became an
  Idea rather than a finding because the text it can carry is not coordinates.
- Sweep 14d read the folder's phone-facing layer (twelve files, 1,285 lines)
  and checked each write and each read against the platform it calls. Two
  defects at the boundary: the size cap checked after the read it was meant to
  avoid (14d-1), and a rename that rewrites the contact's structured name as a
  single first name (14d-2). The rest — resume writes, storage walks, camera
  lifecycle, number normalisation, keystore refusal — held when read line by
  line.
- Sweep 14e read the three adapters and their backends (seven files, 1,043
  lines) with the plugin source underneath and the two consumer notifiers
  above. The state machines (pause clock, completion, seek clamp, idempotent
  dispose) held; the findings are both "a failure read as something else": a
  refused speed read as an unplayable file (14e-1), and a capture failure read
  as recording (14e-2).
- Sweep 14f read the links and the router (five files, 651 lines) and followed
  every kind to its consumer. One dead path — the contact-add payload nothing
  reads (14f-1) — and no exploitable parsing: the fragment, the `/u` name, the
  opaque codes and the platform default location are all handled deliberately,
  and a cleartext invite link dies at `ServerPolicy`.
- Sweep 14g read push and notifications (eight files, 1,233 lines) with the
  call effects, both sign-out paths, `switchTo`, the engine's missed-notice
  emission and the manifest's permissions. The privacy design (ids-only
  payloads, database-built text, previews gate, private visibility) and the
  wake discipline (own isolate, engine lease, one pass at a time, closed in
  `finally`) held; all seven findings are about what the notification says and
  cleans up after: a count that restarts, an update that never alerts again, a
  removed account's leftover, a press with no destination, and two
  missed-call rules that disagree with the message path.
- Sweep 14h read sounds and diagnostics (four files, 809 lines) with the
  ringtone store's deletion path, the call-notification channels, and
  `main.dart`'s three handlers. The masking, queue cap, repeat window and frame
  thresholds held; the findings are a flush timer a repeating crash keeps
  pushing back, a prefix match that deletes a longer id's ringtone, and two
  publishes sharing one temp file.
- Sweep 14i read the chat, people, format, calls and stream helpers (ten files,
  1,338 lines) and cross-read the protocol's preview keys and the renderer's
  range clamp. Two boundary counts were wrong — a day measured in elapsed hours
  and a snippet cut in UTF-16 units — while the naming order, the chat facade's
  gate, the notice keys and the call seam held. A suspected case-mapping offset
  bug was traced to the Dart VM's simple mapping and rejected.
- Sweep 14j read the theme library and the whole pack folder (two files, 977
  lines) with `fromThemeJson`'s throw sites, the format gate, `main.dart`'s
  start-up read and the More themes providers. The store's install order and
  path handling held; the findings are a decode that converts only
  `FormatException` while the parser raises two more kinds (so one bad pack
  takes the folder and cannot be deleted), and a 64-manifest probe repeated on
  every visit of an auto-disposed page.

## Next sweep

None. The audit is complete: every sweep 11 through 19 is read, and sweep 19
has been rebuilt from all 53 findings files against the files themselves (210
ids, each once, 210 appendix rows, severities matched, one batch per finding).
`90_REMEDIATION_PLAN.md` holds every finding in one batch plus the
decided-not-scheduled items, with the rollout class and the proving test for
each; `99_OPEN_QUESTIONS.md` holds the ten decision gaps that block eight
batches. The plan is no longer provisional.

If a later finding is filed, append it to the plan's appendix and assign it to
the batch that owns the same code path — do not start a new batch for a single
finding without checking whether an existing seam already covers it.

Sweep-12 agent (11 → 19): 12m, 12n, 12o, 12p, 12q and 12r are done (21
findings — 12m's four, 12n's four, 12o's two, 12p's four, 12q's three and
12r's four; all are in the plan's appendix, three in B9 (12n's presigned
upload, 12o's download cap and 12r's transfer cap) and the rest in B13).
Sweep 13 is done: seven findings (AUD-13-1..7) in the plan's appendix, all in
a new batch B19 ("The CLI must obey the client rules") because no existing
batch owns the CLI package — B6 is the engine's op surface, B9 the API
transport, B17 the app's sign-in flows. B19 also carries sweep 13's three
structural proposals: one shared server-address policy (S13-1), one device-list
freshness entry point (S13-2) and a harness that reopens a file database
(S13-3).
Sweep 14a is done: four findings (AUD-14a-1..4), appended to the plan's
appendix — AUD-14a-1 and AUD-14a-2 in B5 (the app half of the runtime that B5
already owns; AUD-14a-2 is exactly "without deleting history"), AUD-14a-3 in
B5 (the teardown contract), and AUD-14a-4 in B9 (the `x-helix-client` header
is a transport contract).
Sweep 14b is done: four P3s (AUD-14b-1..4). AUD-14b-1 joins B5 (the media
policy and backup gate it disables are the same policy AUD-14a-1 leaves
unapplied); 14b-2, 14b-3 and 14b-4 start a new batch B20 ("The app's own gate
and lifecycle answer again"), because no existing batch owns the lock, the
network reading or the resume path, and the three share one property: an answer
decided once and never revisited. Next is 14d — the media I/O half of
`core/platform`.
Sweep 14c is done: four findings (AUD-14c-1..3 and the Idea 14c-4). They start
B21 ("An attachment is what it is, cleaned, or it does not go"), because no
existing batch owns app-side attachment preparation — B7 is the server's media
lifecycle and B13 the engine's local one. Its structure is S14c-1 (one
classifier by content) and S14c-2 (one bounded decode).
Sweep 14d is done: two P3s (AUD-14d-1, AUD-14d-2). AUD-14d-1 joins B21 (the
same picture the attachment path prepares, and S14c-2's bounded read is the
same fix); AUD-14d-2 joins B5, where the naming policy including write-back
(S2) already lives. Next is 14e — the audio, voice and video players and the
chat platform seam.
Sweep 14e is done: two P3s (AUD-14e-1, AUD-14e-2). They start B22 ("A player
and a recorder tell the truth about a failure"), because no batch owns app-side
playback or recording — B21 ends at handing the engine a file, B13 is the
engine's local maintenance and B20 the app lock. Structure: S14e-1 (a refused
preference is not a file failure) and S14e-2 (one end for a recording). Next is
14f — links and router.
Sweep 14f is done: one Idea (AUD-14f-1), which joins T4 (ideas and dead paths;
it is a link kind whose payload nothing reads, to be deleted or wired).
Sweep 14g is done: seven P3s (AUD-14g-1..7). They start B23 ("The notification
tells the truth about what arrived, and cleans up after an account"), because
no existing batch owns app-side notifications — B20 is the lock and lifecycle,
B8 the calls themselves, T4 the ideas. Structure: S14g-1 (one owner of an
account's notification ids and their cancellation), S14g-2 (one foreground
predicate) and S14g-3 (the notification owns its count and its alert policy).
Next is 14h — sounds and diagnostics.
Sweep 14h is done: three P3s (AUD-14h-1..3). AUD-14h-2 and AUD-14h-3 join B23
(the ringtone copy and channel it already deletes, and the copy's one writer;
S14h-1 gives that one owner). AUD-14h-1 starts B24 ("The anomaly log sends what
it recorded"), because no batch owns `core/diagnostics` — B20 is the lock and
lifecycle, B5 the runtime's repair. Structure: S14h-1 (one owner of a
ringtone's installation) and S14h-2 (a flush schedule repeats cannot postpone).
Sweep 14i is done: two P3s (AUD-14i-1, AUD-14i-2). They start B25 ("A chat day
is a calendar day, and a snippet cuts a character") because no earlier batch
owns `core/format` or the snippet helper — B23 is notifications, B20 the lock
and lifecycle, B6 the engine's action surface. Structure: S14i-1 (one owner of
the `direct:` conversation-id pair). Next is 14j — `core/theme`.
Sweep 14j is done: two P3s (AUD-14j-1, AUD-14j-2), both in B10 — the same
decode contract and the same pack store that AUD-16-1/16-3/16-6 and AUD-7-4
already own, so no new batch. AUD-14j-1 widens B10's read half (a folder read
must never throw for a bad pack, and a bad pack must be removable), AUD-14j-2
adds the probe half (bounded concurrency and a per-`id@revision` memory). That
closes the sweep list; the next action is rebuilding sweep 19.
