# Orbit: where it stands (handoff, 2026-10-23)

For picking the port up on another machine or in a cloud session. The plan
of record is `PORT_PLAN.md` (Part B is done bar the owner's step 6; Part C,
downloadable theme packs, has started); what each screen needs is in
`contracts/`; every difference from the prototype is in `DEVIATIONS.md`;
the approved backend items are in `GAPS.md`. Read `../AGENTS.md` first.

## The branch

- The port ran on `orbit-ui` (worktree `J:/wt/orbit`, pushed to `origin` on
  2026-10-20) until the owner took it into `main`. Part B's steps 3 to 5 and
  the phone-number decision went straight to `main` as "(pending review)"
  commits, reviewed after the fact. Nobody but the owner pushes.
- One commit per batch, marked "(pending review)" in the message and in
  `PORT_PLAN.md`'s progress notes.
- Part C step 1 (the pack format, the gate and the signing tool), step 2 (the
  server endpoint that serves a pack folder) and step 3 (the download manager)
  are the same way. Step 2 changes the server, so it went through a plan the
  owner approved first ("after this, also start part C step 2. i will approve
  the plan", 2026-10-23). Step 4 (the themes page) was built on the owner's two
  answers of 2026-10-23: a new page behind Appearance, and the publisher anchor
  staying a build-time define. Step 7 (three new themes) needed nothing from
  anyone and is built the same way, and so is step 8 (the theme table becomes
  packs): built and tested, with only the `keygen` between it and an offer.
  Steps 5 and 6 are now ruled by the owner (2026-10-23): a ringtone arrives as a
  signed pack and Android rings with a channel per ringtone, and the animation
  runtime is Lottie. Step 5 is built end to end on the device - the pack format
  that carries a sound, the device that holds one, the Ringtones page that
  chooses one, and the copy Android's system rings with on a channel of its own.
  What is still owed is the sound itself, the one moment step 6 is for, and
  step 9 (premium themes), which waits for the `keygen` and a Play Billing
  decision.

## Done (pending the owner's review)

| Commit | What |
|---|---|
| f900131 | Step 1: `orbit_ui` moved into the workspace |
| 6f0ae55 | Batch 1: sign-in and the entry screens |
| 4d44ff1 | Batch 2: Home |
| 03c6e4c | Batch 3: the conversation |
| db2e996 | Batch 4: the conversation's pages |
| e6ab767 | Batch 5: calls |
| c69ae8e | Batch 6: people |
| 2cccf91 | Batch 7: groups |
| 6e4b53a | S3: the server lists a group's live invite links (groups migration 4) |
| 49a75a4 | **WIP** batch 8: You, profile, Appearance (unfinished) |
| 77ee515 | Batch 8: the settings connectors and the tests (WIP: items below) |
| 90447a7 | Part B step 3: the app is called Orbit, on the Orbit mark |
| a1c5792 | Part B step 4: the app draws only Orbit; `helix_remote_ui` is the console's kit (ADR-031) |
| 5452757 | The operator's whole number, and the privacy text that says why |
| c1a24bf | Part B step 5: the full gate, format fixes and the matrix path |
| 66ad91b | Part C step 1: the pack format, the one gate and the signing tool (ADR-033) |
| fc0536e | Part C step 2: the server serves a pack folder, and `publish` fills it |
| d8fc536 | Part C step 3: the pack store, the trust anchor and the theme library |
| 560c4b2 | Part C step 4: the themes page behind Appearance, in `orbit_ui` and the app |
| f33b2e2 | Part C step 7: Jungle, Ocean and Metal, from the one theme table |
| 672c387 | Part C step 8: the theme table becomes packs, and the pipeline proves it |
| 3db988c | The owner's rulings on Part C steps 5 and 6, recorded in the plan |
| e43d865 | Part C step 5's format half: a pack may be a sound |
| be5f6b0 | Part C step 5's device half: one pack folder, and a store for sounds |
| a1316cf | Part C step 5's picker: the Ringtones page, its route and the choice |
| (this) | Part C step 5's second half: the copy Android rings with, a channel per ringtone |

## The shorter plan (owner, 2026-10-21)

Get the app standing on Orbit first; polish later.

Done (commit after 77ee515, "batch 9 connectors"): Orbit connectors for
password, delete account, blocked, about, legal, advanced, devices,
security activity and backup, with their tests ported (and the journey
test). Fixes found on the way: the password page's "set" and "change"
were the wrong way round in the first draft (fixed before commit); the
delete page can now ask for the number before texting a code (orbit_ui,
behaviour only: `onSendCode` takes the phone).

Then on the old pages, now ported (2026-10-22):
- Approve a new device: `ApproveDeviceModel` carries the account key code,
  shown on the review; approval keeps its confirmation dialog and the
  phone's unlock, and history is sent only on "Send".
- Transfer and Recovery backup: the connectors map the engine's transfer
  rows and offers, the recovery secret's create, copy/share and restore
  tabs, the error and busy states, and the danger zone's delete.
- Link this device and Restore history were already Orbit connectors;
  Restore history's "I have a recovery secret" now opens Recovery's
  Restore tab (`?tab=restore`).

Next: the owner builds and installs a debug APK to try it.

Done after that (2026-10-21, the owner's urgent list):
- 610c519: the anomaly log. Every build sends problem reports to its own
  server (`client_anomaly` lines; `server/tool/anomalies.dart` shows them).
  Live only after production runs this branch and restarts.
- bdfaa2c: screens stay above the keyboard; sign-out leaves at once;
  sign-in is number then password, no code for an account with one.
- (next commit): "Use a code instead" first shows the number and asks the
  person to confirm, saying the operator may charge for the text.

### Next: saved accounts and switching (a long session)

The owner wants "Remember me" at sign-in, saved accounts on the sign-in
page, and switching from an Accounts page in You, in Orbit's style
(prototype first, then the port, as for every screen).

Why it is long: today one database, one key and one session belong to the
signed-in account, and signing out wipes them (`SignOutAction`,
`HelixRuntime.hardWipe`). Several accounts on one device need:
1. A device-level account list (`DeviceSettingsStore` or a new file): id,
   server, number (masked), name, avatar, last used. No passwords.
2. One database, keystore key and session per account (paths and key
   names keyed by account id), and `runtimeProvider` opening the chosen
   one; switching closes one engine and opens another.
3. Sign-out split in two: "Sign out and remove from this device" (today's
   wipe, for that account only) and "Switch account" (keeps it).
4. Push and notifications for accounts not on screen (one FCM token per
   device; the server maps it to several devices, one per account), and
   calls ringing for any account.
5. UI: sign-in shows saved accounts (tap, then the password; "Remember me"
   on by default), You gets an Accounts page (current, others, Add
   account, Remove). Prototype screens, then orbit_ui, then connectors.
6. Tests across engine, app and journeys; the security docs (THREAT_MODEL:
   several accounts' keys on one device; the app lock covers all).
   Needs an ADR if it changes plan sections 3 to 6.

A cheaper first step if tokens are short: remember numbers and names only
on the sign-in page (tap one, type its password). Switching is then sign
out and sign in, with the data of the old account wiped as today.

Done on `main`, not pushed, 2026-10-21 (every commit "pending review"; the
owner skipped the prototype, so Accounts has no prototype or preview screen):
- 0af3bf2: the cheap step. Saved numbers on the sign-in page, Remember me.
- a1c49e6: items 1 and 2. The account list (`AccountSlotStore`, a keystore
  entry), a database, SQLCipher key and folder per account, and
  `runtimeProvider` opening the active one.
- 3c09375: item 3. Switching; "Sign out and remove" wipes that account only
  and opens the next one signed in.
- 558e8a3: item 4. A wake-up reads every account not on screen
  (`wakeSignedInAccounts`), notifications and calls open their account, and
  the push isolate now starts the notification plugin before the call
  channel (it did not before).
- 725c7bb: item 5. The Accounts page (`contracts/you.md`, "Accounts") and
  "Switch account" in the sign-out dialog.
- fc62339: the app lock is now the device's (`DeviceLock`), one for every
  account; an old per-account lock is moved over once.
- 69b346f: item 6's docs. THREAT_MODEL T-11, `app/MODULE.md`,
  `contracts/you.md`. No ADR: one foreground runtime still runs at a time.
- Final push batch: the current and every rotated FCM token go to all accounts
  signed in here. Inactive accounts are opened in turn by the same serialized
  pass as foreground push wakes, so the two cannot race one database.
No server change or migration. A new APK is needed to try it.

Part B steps 3 to 5 are built (the Orbit name, the old kit out of the app,
the full gate). Only step 6 is left, and that is the owner's: the APK, the
Windows run and the merge.
The lists below keep their detail. (The pixel checks, S1, E1, E4, E5, E6 and
batch 10 are built — see "Deferred work, in order", items 4 to 10. S1 and E6
both change the server, so neither is live until production runs this branch.)

## Deferred work, in order (owner, 2026-10-22)

1. DEVIATIONS and FEATURE.md updates - **done** (2026-10-22): batch 8,
   batch 9 and saved accounts are in `DEVIATIONS.md`; `PORT_PLAN.md` has
   their progress notes; the settings, profile and sign-in `FEATURE.md`
   files describe the Orbit connectors, the Accounts page and the
   device-wide lock.
2. The old pages to Orbit - **done** (2026-10-22): Approve a new device,
   transfer, recovery and restore history draw the Orbit screens through
   their connectors (link this device was already wired). The account key
   code is on the approval review, and Restore history opens Recovery on
   its Restore tab. Deviations are in `DEVIATIONS.md` ("The last old
   pages").
3. E3 and E2 - **done** (2026-10-22): storage by kind and by chat, and
   freeing a chat's photos/videos or documents, are in the engine
   (`media.storageUsage/biggestChats/freeChatSpace`) and the local DAO;
   the Storage page draws the split and the biggest chats. Engine-only,
   despite the earlier "needs the server" note: no server route, protocol
   change or migration, so no production restart.
4. S1 - **done** (2026-10-22): the share link `helix.agiletechbd.com/u/<~name>`
   (You > the QR button: link, a real scannable code, Copy link, Share, and
   "Scan someone's code" on `/scan-chat`, which resolves the name and opens
   the chat). `helix://u/<name>` and the https form both parse, and Android's
   existing verified filter took a `/u/` prefix. **This is the one item in
   the list that changes the server**: a new public route, `GET /u/{name}`,
   serving one static page. No migration and no new `.env` line, but the
   route only answers once production runs this branch, so the owner has to
   rebuild and switch to it (never done by an agent). Deviations are in
   `DEVIATIONS.md` ("Part B S1"). It also repairs the boundary cf3fcb8 broke:
   the Storage page read a failure sentence from `core/` inside
   `presentation/`, which `app/test/architecture_test.dart` forbids. Freeing
   a chat's files is `StorageFreeActions` in `application/` now, and the rule
   is green again.
5. E1 - **done** (2026-10-22): the profile photo publishes. The engine
   encrypts the picked picture into a `persistent` media object, puts its
   pointer inside the sealed profile, and at a peer stores it in
   `people.avatarBlob` - which is what the chat list and contact info already
   drew. It reads a peer's profile once, when a message first carries that
   person's profile key, and retries at most one profile and one picture per
   person per day. Choosing or removing a photo in Edit profile now publishes
   it. **No server change, no migration, no new `.env` line.** Deviations are
   in `DEVIATIONS.md` ("Part B E1"). E4 and E5 are done too (below).
6. E4 - **done** (2026-10-22): the Backup page's running ring shows a real
   percentage. The engine counts the messages a backup will write before it
   starts (`SnapshotExporter.countToExport` → `HistoryStore.backupableCount`,
   given the exporter's own filter) and carries it on every
   `BackupProgress`; a test runs both filters over one mixed history so they
   cannot drift. `BackupModel.progress` is nullable now, so an uncounted run
   shows an empty ring rather than "0%". No server change.
7. E5 - **done** (2026-10-22): a metered network now has its own failure.
   `BackupFailure.waitingForWifi` is thrown by `PolicyBackupRemote` (the one
   place that knows the network), and the Backup page says "Waiting for
   Wi-Fi" and which switch to turn; `notAllowed` means only a refused
   account. No server change, no migration - the value is stored by name and
   decodes tolerantly both ways. Deviations in `DEVIATIONS.md` ("Part B E5").
8. E6 - **done** (2026-10-22): every device knows the account's recovery
   backup. The owner chose the metadata-only route: `GET /v1/backups/full/meta`
   answers `exists` plus the row's `updated_at`, and "none" is a 200 with
   `exists: false` so a server that lacks the route (which answers 404) can
   never be read as "your backup is gone". The Backup row and the checkup ask
   it, and fall back to this device's own record when it cannot be asked.
   **This changes the server**: no migration and no new `.env` line, but the
   route only answers once production runs this branch, so the owner has to
   rebuild and switch to it (never done by an agent); the app works against an
   older server with its local record. Deviations in `DEVIATIONS.md`
   ("Part B E6").
9. The pixel checks - **done** (2026-10-22): both sides re-shot (the
   prototype with `shoot_html.py`, the app with the preview build's `--shoot`)
   and all 241 phone keys scored with `partb/prof.py`'s `total >16`. 236 are
   exactly where Review 4 left them. Five are higher - `signin-password` 6.02
   (was 2.14), `signin-password-error` 7.22 (2.86), `signin-takeover` 6.35
   (2.76), `account` 4.10 (2.52), `account-nopass` 4.13 (2.54) - and every one
   is a change already in `DEVIATIONS.md` ("Saved accounts and switching"):
   the saved-account rows, "Remember me", "Use a code instead" and the
   sign-out dialog's second line. Their numbers in `review4_scores.txt` are
   now these, so the gate stops crying. Two real faults turned up and are
   fixed: `TransferScreen` counted a stopped offer in its "N waiting here"
   pill (the prototype counts only an unanswered one; the enum-to-buttons
   rewrite widened it), and `shoot_html.py`'s 0.12 s final settle photographed
   every scrolled page before its late re-scroll, which had moved the four
   chat keys and `group-pending-member` by ~14 px; its default is now 0.5 s.
   Nothing here needs a new APK: the pill fix is one line of orbit_ui.
10. Batch 10 (the wide Windows layout) - **checked** (2026-10-22): the layout
    itself is in `ccf534c`. Both sides re-shot at `window-l` (27 keys) and
    `window-m` (15) and scored with `partb/score_all.py`; every one of the 42
    is at or better than its batch 10 number, so nothing in the wide layout
    moved while Part B and E1-E6 were going in. `partb/window_scores.txt` is
    the reference now, so the next wide change has a number to keep. The only
    three keys that differ from batch 10 did so on the prototype side, under
    the owner's uncommitted `orbit/prototype/css/tokens.css` (chat-actions
    0.87 -> 0.81, chat-attach 4.63 -> 4.02, message-info 4.59 -> 5.07); with
    that file pinned at `ccf534c` the same Flutter shots score 0.81, 4.63 and
    4.54. Nothing to fix, and no new APK: this batch is preview-side only.
    The `orbit_ui` window tests pass (5).
11. Part B steps 3 to 5. **Step 3, the Orbit name — done** (2026-10-23): the
    Android label, the Windows window title, `MaterialApp.title`,
    `AppInfo.name` (and its rule test), the startup page's title and the call
    channel's description all say Orbit, and the launcher icon is
    `orbit/prototype/assets/orbit-mark.svg` rasterized to `assets/logo.png`
    (1024 px, headless Chrome) through `flutter_launcher_icons` — so the five
    Android `ic_launcher.png` and `windows/runner/resources/app_icon.ico`
    changed with it. Left alone on purpose: the Windows URI-handler key still
    reads "Helix Remote Protocol" (the protocol is Helix's, not the app's), and
    so does `applicationId` / the Kotlin package, or an install would not
    upgrade. Step 3's theme bullets were already met by batch 8: the chosen
    theme is a device setting that drives `MaterialApp`, and there is no
    high-contrast theme to remove. **Step 4, the old kit out of the app -
    done** (2026-10-23): `app/` imports nothing from `helix_remote_ui`, and
    the package holds only what the operator console uses - the tokens,
    `HelixThemes.console()`, `HelixSkeleton` and
    `showHelixDestructiveDialog` - with a Flutter-only pubspec and 7 rules
    tests. The gallery page, its golden test, the old widget harness and the
    unused `light()`, `highContrastLight()` and `signIn()` builders are gone.
    Because plan section 6.1 named the package as a client package, the
    change is recorded as ADR-031 with its section 12 row; AGENTS.md,
    `app/MODULE.md`, `app/README.md`, `docs/ui/COMPONENT_GALLERY.md` and
    `REGRESSION_TEST_MATRIX.md` say the same now, and the two deviations the
    owner still has to rule on (eager lists against the section 6.4 budgets,
    the 46 px search bar against the 48 px rule) are written up in
    `DEVIATIONS.md` ("Part B step 4"). App 909, orbit_ui 215 and ui 7 all
    pass. **Step 5, the full gate - done** (2026-10-23): everything
    `scripts/verify.ps1` runs, run step by step. app 909 (the journeys are in
    it), engine 313, orbit_ui 215, api 201, admin 191, db 140, protocol 84,
    crypto 74, rules 20, `helix_remote_ui` 7, cli 13, calls 5, domain 4, the
    server on Postgres 404; `flutter analyze`, `dart analyze server tool`,
    `dart format` and the governance check (27 controls) are clean, and the
    drift code is up to date. The two server failures under load were each
    green alone (now listed in AGENTS.md as timing flakes). Nine files were a
    six app files were a line off `dart format` and are formatted. What is left
    of Part B is yours:
    the APK on the phone, the Windows run, and the merge.

## Part C, downloadable theme packs (owner: "you continue to part C", 2026-10-23)

`PORT_PLAN.md` Part C is the plan. Steps 1, 2, 3, 4, 7 and 8 are built, and so
is step 5 in full: a pack may be a sound, this device can hold one, the
Ringtones page chooses one, and a call rings it on a channel of the chosen
pack's own. What is left of step 5 is the sound file itself (a signed pack, a
design decision); step 6 is ruled (Lottie) and waits on the moment it animates.
Step 9 waits for the `keygen` and a Play Billing decision.

12. Part C step 1, the pack format and the signing tool - **done**
    (2026-10-23, ADR-033). A pack is a folder: `manifest.json` plus the files
    it lists, and the manifest's theme is the same JSON the built-in themes
    are, so `OrbitTokens.fromThemeJson` did not change. One gate,
    `checkOrbitPack` in `packages/helix_remote_domain/lib/domain/theme_packs.dart`,
    holds the whole format: size and count limits, path rules, per-file
    sha256, the Ed25519 signature, and the theme document. **The order of the
    checks is the security property** - nothing of an unverified pack is
    parsed or opened, so a hostile server can reach no parser. The gate takes
    the effect and pattern registries and the trusted publisher keys as
    arguments: `orbit_ui` stays the one registry of what can be drawn, and the
    release build stays the one trust anchor. The gate refuses a pack naming
    an effect this build does not ship, which is what keeps a pack from
    bringing code. `tool/theme_pack_tool.dart` does `keygen`, `pack`, `sign`
    and `verify` against the same gate. Tests: domain 44, including pinned
    signing vectors (a canonical-bytes golden, a public key and a signature)
    so the signing form cannot drift. No server change, no migration, no
    route, no new `.env` line. Docs: `docs/product/THEME_PACK_FORMAT.md`,
    ADR-033, its section 12 row, and the dependency register entry for the
    domain package's first hosted dependency (`cryptography`, the version the
    lockfile already had - it did not move).
13. Part C step 2, the server endpoint - **done** (2026-10-23, on the plan the
    owner approved: publish by folder plus tool, the `ops` module owns the
    routes, and a file is picked by its sha256). Three public routes -
    `GET /v1/packs`, `…/revisions/{revision}/manifest`, `…/files/{digest}` -
    read the folder `HELIX_PACKS_DIR` names
    (`server/lib/src/modules/ops/pack_host.dart`), and the server holds **no**
    part of the pack format: it lists the folder's own names and file stats,
    streams the manifest byte for byte, and takes a digest rather than the
    manifest's path, so the route has no path to sanitise, a file in two
    revisions is stored once, and a client can only ask for bytes a manifest
    named. The list carries no display name - the one a device shows comes from
    the signed theme document, and an unsigned name here would be forgeable.
    Caps the format refuses at (64 KiB, 8 MiB) are the only numbers the server
    knows, and past them it answers 413 instead of streaming; anything a pack
    could not be named by is a 404, checked before the folder is touched.
    `publish` (the tool's fifth command) writes the layout, re-checks every
    file against the signed manifest, refuses an unsigned manifest, and will not
    rewrite a revision that is already published. No table, no migration, no
    admin upload. Tests: server 16 (host without a database, routes on
    Postgres), protocol 84, api 205 with the route-parity table. Docs:
    `REST_V2.md`, `ops/MODULE.md`, the env table, `THEME_PACK_FORMAT.md` and
    ADR-033's consequences. The pipeline's `no-store` covers these routes like
    every other response, so the device's own cache (step 3) is what avoids a
    repeat download.
14. Part C step 3, the download manager - **done** (2026-10-23). App-side
    only, deliberately: no `orbit_ui`, protocol, api or server file moved, so
    the pixel gate's 241 keys still score the same. `core/theme/orbit_packs.dart`
    is `ThemePackStore` (the device's `packs` folder in the server's own layout,
    files written and read by sha256 so nothing opens a path a pack named,
    download staged and renamed only after `checkOrbitPack` passes, **every**
    pack re-checked on **every** read, highest revision kept with a downgrade
    refused and the older one deleted, and the revision already on the device
    never refetched) and `PackTrust` (the anchor:
    `--dart-define=HELIX_PACK_PUBLISHERS=slug:hex`, empty by default exactly as
    `HELIX_GLOBAL_PINS` is, so every pack is refused as `unknownPublisher` until
    you run `keygen`). The theme library is now packs merged **under** the
    built-ins, so no pack can take Orbit's or Night's name; the saved choice
    must be a theme id on read and must exist to be chosen; and when a chosen
    pack is deleted or stops passing, the app draws Orbit and keeps the choice
    for a re-download. `features/settings/application/theme_packs.dart` is the
    manager the pages will call: `ApiPackSource` over the signed-in account's
    server, install/update/delete each answering one plain sentence, the library
    re-read afterwards. Accounting: `StorageUsage.packBytes`, its own segment on
    the Storage page only when there are any, not freeable there (Appearance
    deletes). Tests: 29 new (`app/test/settings/theme_packs_test.dart`, real
    temp folders, real Ed25519 keys, unsigned/untrusted/swapped/over-cap/
    unknown-effect packs each writing nothing) plus the Storage label; app suite
    and analyze clean.
15. Part C step 4, the themes page behind Appearance - **done** (2026-10-23),
    on your call: Appearance keeps its two cards and gains one "More themes"
    row that opens `/settings/appearance/themes`. `ThemeGalleryScreen` in
    `packages/orbit_ui/lib/src/screens/you/theme_packs_screen.dart` draws two
    groups - "On this phone" (the built-ins, then every pack that passed its
    checks when it was read), then "On <host>" - one trailing control per row
    (Get / Update / a delete icon / a spinner while that row works) and the row
    tap as "Use". The app side is `themeGalleryProvider` and `ThemePackPage` in
    `features/settings/application/theme_packs.dart` over step 3's manager: an
    offer is named by its slug alone, because the list route carries no display
    name and a name there would be unsigned; the row marked "In use" is Orbit
    when the saved choice names a pack this device no longer holds. Tests: 7
    (`packages/orbit_ui/test/theme_packs_test.dart`), 6 in the app's page group,
    the navigation in `settings_pages_test.dart`, and the page in the 1x/2x rules
    sweep. No server, protocol, api or engine file changed, and no pixel key: see
    `DEVIATIONS.md`, "Part C step 4".
16. **Ruled (2026-10-23, you): the publisher anchor stays a build-time define.**
    Step 1's note had said the key would go in "the app's trust anchor, which
    step 3 adds with the download page"; step 3 made it
    `--dart-define=HELIX_PACK_PUBLISHERS=slug:hex,…` with no page where anyone
    types a key, because a release app must not take its own trust decision from
    its UI - that turns a theme download into a self-granted permission. You
    chose to keep it. Consequence, unchanged: a pack becomes downloadable only
    in a build made with the define, so it is an APK rebuild you control, after
    `keygen`.
17. Part C step 5, the ringtone picker - **done** (2026-10-23): its **format**
    is item 20, the device's **sound store** is item 21, the **picker** is
    item 22, and the **copy Android rings with** is item 23. **Both halves were
    ruled (2026-10-23, you):** the sound arrives **as a signed pack** - which
    means the pack format has to carry a file that is not a theme, and no server
    file changes, because the three pack routes serve a file by its digest and
    never look at what it is - and Android rings with **a channel per
    ringtone**, not with the app playing it, because a call must ring when the
    app is not alive. What is still owed on step 5 is the sound itself: a
    ringtone is a design decision, not a generated tone. Step 6 is ruled
    **Lottie**; its dependency and its `DEPENDENCY_RISK_REGISTER.md` entry come
    with the first animation that ships, and which moment animates is still
    yours to name.
18. Part C step 7, Jungle, Ocean and Metal - **done** (2026-10-23). Three records
    in `THEMES` in `prototype/tools/themes.py`, and the generator's own outputs:
    `css/themes.css`, `js/themes.js` and `assets/themes/{jungle,ocean,metal}.json`
    all come from that table, so nothing was retyped and the eight themes that
    were there are unchanged to the byte. The contrast report is 11 themes, 0
    failures. Each stays inside what the port already draws: families the
    prototype loads and the preview bundles, existing pattern kinds (Jungle's
    green grain, Ocean's contours as waves, Metal's scanlines as brushed steel)
    and existing effect kinds (Ocean's wordmark glow, Metal's notched corners and
    chrome eyebrows). No new font, no new asset, no dependency.
    - **On you:** the app still draws only Orbit and Orbit Night, so these three
      are seen in the prototype and the preview until packs ship. Step 8's list
      names six themes - say whether Jungle, Ocean and Metal join it or become
      built-in. Their palettes are the port's first draft: `DEVIATIONS.md`
      records that, and a change to one is a change to the specification.
    - The pixel gate moved where the plan expected it to: Appearance draws one
      card per theme, so `appearance` was re-shot on all three devices and each
      pair got closer (phone 5.57 to 4.22, window-l 3.85 to 3.40, window-m 4.56
      to 4.42). The reference files carry the new numbers with a note; the other
      240 phone keys and the other window keys re-scored within the margin.
19. Part C step 8, the theme table becomes packs - **done** (2026-10-23). The
    pipeline was finished at step 2; what was missing was a way to run it for a
    table of themes, and proof that the real documents survive it.
    - `dart run tool/theme_pack_tool.dart build --themes
      packages/orbit_ui/assets/themes --ids bloom,mochi,papyrus --out
      build/packs --publisher … --revision 1 --seed-file …` stages each slug
      into `<out>/<slug>/themes/<slug>.json` and writes that folder's signed
      manifest, so `verify` and `publish` continue exactly as before. The slug
      is checked by the format's own rule before it becomes a path - the domain
      now exports `isOrbitPackName` rather than the tool keeping a second copy -
      a document naming itself another theme is still refused, and a staged
      file of a different generation is refused instead of mixed. `build`
      writes staging; `publish` is still the step that makes an offer.
    - The proof is a test, not a run: "the theme table as packs" in
      `app/test/settings/theme_packs_test.dart` signs **every** document in
      `assets/themes` except Orbit and Night with a key that exists only for
      the run and installs each through the real `ThemePackStore` - the app's
      own gate, this build's own effect and pattern registries, the real pack
      folder - then checks that each came back with its own signed name and
      that no two are the same theme. It lists the folder, so a theme added to
      the table is packed and checked without anything being widened again (the
      mistake step 7 had to fix by hand in four places).
    - Nothing but `tool/`, the domain's one exported predicate and the two test
      files changed: no server, api, engine, `orbit_ui` or app-source file, so
      no redeploy joins the list and the pixel gate has nothing new to score.
      Ran by hand for all nine with a throwaway key in a temp folder - nine
      `usable:` verifications, nine published revisions, nothing left in the
      repo. Domain 2 new, app 1 new, both suites green, analyze clean.
    - **On you:** the `keygen`, then `publish` into `HELIX_PACKS_DIR` and a
      build with `HELIX_PACK_PUBLISHERS`. Step 7's question is now an argument:
      `--ids` takes any of the nine, so offering six or nine is your call at
      publish time, not a code change.
20. Part C step 5's format half, a pack may be a sound - **done** (2026-10-23).
    Your ruling needed one thing from the format before any of the picker could
    be built: a pack that carries a file which is not a theme.
    - The manifest gained an optional `contents` word, `theme` or `sound`, and
      **absent means `theme`**. That is the whole trick: `toJson` writes the
      field only when it is not the default, so a theme pack's signed bytes - the
      pinned 253-byte vector and every pack built with it - are unchanged to the
      byte, and the format did not need a version bump to grow a second kind.
      `audio` is a fourth file kind (`.m4a`, `.aac`, `.mp3`, `.ogg`, `.wav`),
      `theme` is a field a pack may omit, and the gate's fifteenth refusal,
      `unknownContent`, runs in the same first pass as the sizes and the path
      shape - before the signature, and before a byte of the pack is opened.
      A sound pack is **exactly one audio file** with nothing beside it, and
      `contents` is inside the signed message, so a host cannot re-word a theme
      into a sound or a sound into a theme.
    - `tool/theme_pack_tool.dart pack --in DIR --id chime --contents sound`
      writes one, and `build` refuses that flag: a ringtone is not in the theme
      table, and its folder is one a person made. `sign` keeps the word (a
      manifest re-signed after dropping it would be a theme pack again), and
      `verify` and `publish` needed nothing.
    - The app still draws themes and nothing else. `ThemePackStore.install`
      refuses a pack that is not one **before** fetching its files, and `_read`
      skips one it finds in its own folder, so a sound published beside the themes
      cannot reach the More themes list, the theme library or the start-up scan -
      and the page says "That pack cannot be used: a kind of pack this app does
      not know." The sound step's own store is what plays it, and is item 21.
    - No server, protocol, api or engine file changed, so the pending-redeploy
      list is still exactly the three pack routes, `/u/{name}`,
      `GET /v1/backups/full/meta` and the `HELIX_PACKS_DIR` line, and the pixel
      gate has nothing new to score (no screen moved). Tests: 9 new in the
      domain's "what a pack is" group (53 in that file, pinned vectors included
      and still green), 3 new in the app's pack file (39). The chain was run by
      hand with a throwaway key in a temp folder - a sound packed, verified
      ("usable: chime r1 (sound)"), published by digest, then refused for two
      files, for a png, and for a theme folder; a real theme document still
      builds and verifies - and nothing was left in the repo. Docs:
      `THEME_PACK_FORMAT.md` (the field, the kind, the example, the order),
      ADR-033's amendment, `helix_remote_domain/MODULE.md`.
    - **On you, before the picker:** one folder holds both kinds and the list
      route cannot tell them apart, because `contents` is inside the manifest the
      endpoint never opens. Either the app fetches a manifest to know (no server
      change; an offer it will refuse may show for a moment), or the list says
      what kind each row is (a protocol and server change, so your approval), or
      sounds get a second `HELIX_PACKS_DIR`. Then the sound itself.
21. Part C step 5's device half, a store for sounds - **done** (2026-10-23).
    The app can now hold a ringtone, and one folder holds both kinds.
    - `ThemePackStore`'s mechanics - the staging folder, the size caps, the one
      call to `checkOrbitPack`, the re-check on every read, the downgrade
      refusal, the older revisions deleted after a new one lands - were lifted
      into a single `PackFolder<T>` in `core/theme/orbit_packs.dart`,
      parameterised by the two things that actually differ between a theme and a
      sound: the `contents` word a pack must carry, and how its bytes become
      something the app can use. `ThemePackStore` asks for `theme` and decodes a
      document into `OrbitTokens`; the new `SoundPackStore`
      (`core/sounds/orbit_sounds.dart`) asks for `sound` and decodes one into the
      `InstalledSound` a page can play - the file it is kept as, by digest, plus
      its suffix.
    - **Moved, not copied.** This is the security-critical path, so there is
      deliberately one implementation of it: a second pack kind cannot drift
      from the first, and a rule fixed in the folder is fixed for both. The 39
      theme tests pass unchanged against the refactor, which is the check that
      the rules did not move.
    - Each store refuses the other's kind from the manifest, before a file is
      fetched (the fake host asserts it recorded nothing it was asked for), and
      skips it on every read of the folder - so a ringtone never reaches the
      More themes list or the start-up scan, and a theme never reaches the
      picker, with neither store knowing the other exists. A theme's document
      must parse as this build's 111 tokens to be offered at all; a sound's bytes
      are hashed, size-capped and never opened, and a ringtone is named on screen
      by its signed pack id, because a sound pack carries no display-name
      document.
    - No server, protocol, api, engine or domain file changed, so nothing joined
      the pending-redeploy list and no pixel key moved (no screen exists yet).
      Tests: 12 new in `app/test/settings/orbit_sounds_test.dart`; the theme
      pack file's fixtures moved to `test/support/pack_fixtures.dart` so both
      kinds are built by the same helpers. App suite 969 green, `flutter
      analyze` clean. Docs: `THEME_PACK_FORMAT.md` "What the phone does", the
      app's `MODULE.md` (`sounds/`).
    - **Still owed on step 5 when this was written:** the picker (item 22) and
      the copy plus the per-ringtone channel (item 23), both done directly
      after. The sound itself and the offer-kind decision in item 20 remain.

22. Part C step 5's picker, the Ringtones page - **done** (2026-10-23). The
    Notifications page's ringtone row now opens a page that lists what this
    phone can ring with and what its server offers.
    - `RingtoneGalleryScreen`
      (`packages/orbit_ui/lib/src/screens/you/ringtone_packs_screen.dart`) is
      built from the parts the port already draws, because the prototype has no
      such screen: "On this phone" puts the phone's own ringtone first (never
      Get, Update or Delete, marked "In use" while nothing else is chosen), then
      the sound packs this device holds, each with Update when the server lists
      a higher revision and Delete otherwise; "On <host>" lists the offers,
      each with Get. An action in flight shows a spinner on its own row. The
      page's foot says a downloaded ringtone is a signed pack, and the empty
      state either names what to expect or, when the folder held packs this app
      could not vouch for, says so instead of "nothing is on offer".
    - On the app side (`features/settings/application/sound_packs.dart`,
      `presentation/ringtones_page.dart`), the choice is a device setting:
      `deviceSettingsStore.readRingtone/writeRingtone`, where the phone's own
      ringtone is the *absent* value (`writeRingtone(null)` removes the key), so
      it survives a sign-out and a theme write cannot clobber it (the store now
      merges). The Notifications row shows the chosen pack's signed id, or
      "Phone's ringtone" when nothing is chosen or the chosen pack was deleted -
      the choice is kept, as a deleted theme's is, and returns when the pack is
      downloaded again. The row, its route
      (`/settings/notifications/ringtones`) and the page exist only on Android,
      where a call rings through a notification channel a chosen sound can
      change.
    - **The offer's kind is now read before a row is shown.** One
      `HELIX_PACKS_DIR` holds both kinds and the list route never opens a
      manifest, so `hostedPacks` reads one manifest per offer (at most
      `hostedPackProbe = 64`), checks shape, publisher and signature with the
      new manifest-only half of the gate, and lists the row only if `contents`
      is the kind the page wants; anything it cannot vouch for is counted in
      `PackOffers.unverified` and the page says why rather than "nothing is on
      offer". This is the interim answer to item 20's open question, entirely
      app-side.
    - The domain's gate was split into `checkOrbitPackManifest` (shape, sizes,
      publisher, signature) and `checkOrbitPack` (that, then the files, then the
      theme document) so the manifest probe runs exactly the same rules - one
      implementation, four new tests.
    - No server, protocol, api or engine file changed, so the pending-redeploy
      list is unchanged, and no pixel key moved: the prototype has no Ringtones
      screen, and the preview keeps the prototype's mock "Orbit (default)" on the
      Notifications screen so that key holds. Tests: 7 in
      `packages/orbit_ui/test/ringtone_packs_test.dart`, 16 in
      `app/test/settings/sound_packs_test.dart`, 2 more in the theme page's file
      for the kind filter, the new page in the 1x/2x rules sweep, and the
      Notifications row's navigation in `settings_pages_test.dart`; app suite
      990 green, orbit_ui 229, domain 61, `flutter analyze` clean. Docs:
      `DEVIATIONS.md` "Part C step 5", the settings `FEATURE.md`, the app's
      `MODULE.md`, `THEME_PACK_FORMAT.md` and the domain's `MODULE.md`.
    - **The second half is item 23** (the copy Android's system reads and a
      channel per ringtone), built directly after this. The sound itself is
      still owed, and so is item 20's offer-kind decision if you want it settled
      at the source.

23. Part C step 5's second half, the sound a call rings with - **done**
    (2026-10-23). A chosen ringtone is now what an incoming call actually rings.
    - `core/sounds/orbit_ringtones.dart` is the one place the phone's form of a
      ringtone is built: `CallRingtone` (pack id, channel id, content URI),
      `publish` (one copy of the pack's file into the app's external files
      folder, written to a `.part` and renamed so a call never reads half a
      file; the previous choice's copy is removed), `forget` (that pack's
      copies, or all of them) and `chosen` (the choice, gate-checked again
      through `SoundPackStore`, plus the copy's existence). It is provider-free
      because the FCM isolate rings through it.
    - The copy is served by the stock `androidx.core.content.FileProvider`
      under `com.helix.remote.ringtones`, declared in `AndroidManifest.xml` and
      scoped by `res/xml/helix_remote_ringtones.xml` to `external-files-path
      path="ringtones/"` alone. It is exported because a notification channel
      stores a URI, not a per-URI grant, so Android's system reads it with no
      grant; the scoped path keeps that reach to the copies. `AppPaths` gained
      `ringtoneDirectory` over `getExternalStorageDirectory` (created only when
      a copy is written) and two test hooks so the Android path runs on Windows
      in tests.
    - Android fixes a channel's sound at creation, so `CallNotifications` makes
      `_forRingtone`'s channel (id `helix_incoming_calls_ringtone.<id><suffix>`,
      name `Incoming calls: <id>`) before the first notification that uses it,
      and `showIncoming` takes a `CallRingtone?`. `forgetRingtone` deletes the
      pack's channels when it is removed. Both ringers pass
      `Ringtones.chosen()`: the running app's `NotificationCallRinger` and the
      FCM isolate in `push_background.dart` (one read per wake-up).
    - The page's verbs keep the phone and the page in agreement: choosing
      publishes first and reverts to the phone's own sound if the copy cannot be
      written; a re-download of the chosen pack republishes it; deleting a pack
      deletes its copy and its channel but keeps the choice, so a re-download
      brings the ringtone back. The existing channel, its sound and its flags
      are untouched when no pack is chosen.
    - No server, protocol, api, engine or domain file changed, so the
      pending-redeploy list is unchanged, and no pixel key moved. Tests: 15 new
      (14 in `app/test/settings/ringtone_channel_test.dart` - the channel id
      and URI, the manifest and path rules, the copy's lifecycle, and
      `chosen`'s fallbacks; 1 in `sound_packs_test.dart` for a re-download that
      cannot be set up). App suite 1005 green, `flutter analyze` clean. Docs:
      `DEVIATIONS.md` "Part C step 5", the settings `FEATURE.md`, the app's
      `MODULE.md`, `PORT_PLAN.md`.
    - **On you:** a new APK is needed to hear any of it (the phone must build
      the manifest, the provider and the channel code), and a real sound pack
      is still the missing half of step 5: with one published and a build
      carrying the publisher anchor, a call rings with it.

## Batch 8, what is left

`contracts/you.md` is the spec. Already done in 49a75a4:
- orbit_ui behaviour for every batch 8 screen. The 17 states are identical
  to Review 4.
- The theme setting (`core/theme/orbit_app_theme.dart`: a device file,
  Orbit and Orbit Night), and the retired light-only rule.
- The checkup (`shared/you_checkup.dart`), `DeviceHealth`, the You
  connector (`shared/widgets/orbit_you_connector.dart`), Appearance
  (`features/settings/presentation/appearance_page.dart`), and Edit profile
  (`features/profile/presentation/profile_page.dart`).

Done after 49a75a4 (the commit after it):
- The five connectors (`privacy_page`, `notifications_page`, `chats_page`,
  `storage_page`, `account_page`), with `privacyViewerNameProvider`, the
  muted lines and lock-screen date, `downloadSummary`,
  `backupOverMobileSettingProvider`, `AccountOverview.createdAt` and
  `accountSinceProvider`. `choice_sheet.dart` is gone (nothing used it).
- The tests: `settings_pages_test`, `a3b_rules_test`, `privacy_number_test`,
  `delete_account_test` and `profile_page_test` ported to the Orbit
  screens; `you_checkup_test` is new (the checkup rules, the theme choice,
  Appearance). Tests get the built-in themes from `a3bOverrides`.
- orbit_ui, behaviour only: segments answer taps 4px above and below and
  report a 48px target; "See all checks" reports 48px; the lock-screen
  preview is read as one line; Privacy waits for the phone-number dialog's
  answer (it read it before the dialog's 60ms-late Turn on, so a typed
  number always counted as Cancel).
- The pixel check (`compare.sh`) on the batch 8 keys: run 2026-10-22, every
  one at its Review 4 score.

To do:
1. Run the pixel check on the batch 8 keys (the segment change moves no
   pixels, but check). - **done** (2026-10-22, with the full 241-key pass).
2. Log in DEVIATIONS "Part B batch 8": no ringtone row (needs a sound
   from the owner); the notifications preview text is a fixed sample;
   "Export first" only exports. (The storage note is resolved by E2/E3;
   see "Part B E2/E3".)
3. **The approved backend items**, each as its own commit (helix-feature
   skill):
   - S1: the share link `/u/<~name>`, app links and scan-to-chat - **done**
     (2026-10-22).
   - E1: share the profile photo with people you message - **done**
     (2026-10-22).
   - E2: storage size by kind and by chat - **done** (2026-10-22).
   - E3: free one chat's media and keep its messages - **done**
     (2026-10-22).
4. **Docs.** `DEVIATIONS.md` gets a "Part B batch 8" section, `PORT_PLAN.md`
   a progress note, and the settings and profile `FEATURE.md` files need
   updating.

After batch 8 comes batch 9: settings pages, devices and backup
(`contracts/devices_backup.md`, with E4, E5 and E6). Batch 10, the wide
Windows layout (`contracts/frame.md`), is built and its pixel check is done.
Part B steps 3 to 5 are done (2026-10-23): the Orbit rename, `helix_remote_ui`
demoted to the console, the full gate. Step 6 - build, try, merge - is the
owner's.

## How every batch is checked

From `helix_remote/`:
- `flutter analyze`
- `dart analyze server tool`
- `dart format --output=none --set-exit-if-changed app admin server packages tool`
- `dart run tool/check_governance_controls.dart`
- `flutter test` in `app`, `packages/orbit_ui`, `packages/helix_remote_ui`
  (the console kit, 7 rules tests) and
  `packages/helix_remote_architecture_rules`, plus any package you changed.
- Also `flutter analyze` in `orbit/flutter/apps/orbit_preview`.

Server tests need PostgreSQL 17 and `HELIX_TEST_DATABASE_URL`: run
`HELIX_REQUIRE_TEST_DATABASE=1 dart test --concurrency=3` in `server/`,
never at the same time as the Flutter tests.

`flutter pub get` dirties the plugin registrants. `git checkout --` them
unless their content changed.

**Pixel check (Windows only).** Run
`orbit/flutter/tools/compare/partb/compare.sh <keys>` for the keys a batch
touches, and `partb/score_all.py` for the whole device in one pass. Every key a batch
touches must keep its Review 4 score (`partb/review4_scores.txt`) unless
the change is deliberate and logged in DEVIATIONS. A wide-window batch is the
same tool with the window reference and the device's own keys:
`score_all.py --dev window-l --keys auto --ref window_scores.txt` (and
`--dev window-m`; `--keys auto` takes the 27 and 15 keys shot on both sides,
which are not the phone's 241). The prototype shots are
not committed; make them with `tools/compare/shoot_html.py` (see the
compare README). Shoot with the default settle (0.5 s since 2026-10-22): a
page that scrolls itself moves again once the fonts land, and a short settle
photographs it ~14 px early, which reads as a port regression on every
timeline key. A cloud or Linux session cannot run this check, so it
must say so.

## Lessons that cost time

- Pixel parity is mandatory. A 48px field that moved a hint by 1px was
  reverted. A fixed-height row that overflows at 2x text becomes
  `ConstrainedBox(minHeight:)`, which stays pixel-identical.
- Orbit toasts leave a timer of up to 4 s. A widget test ends by pumping a
  `SizedBox` and then 5 s (the `chatTest`, `contactTest` and `groupTest`
  wrappers do this). Orbit menus run their item 60 ms after closing:
  `pumpAndSettle` after a tap.
- Semantics labels merge with their siblings unless they are
  `container: true`. `find.bySemanticsLabel` with a String is an exact
  match.
- `OrbitTapArea` gives a 48px target without moving pixels, but only when
  its parents' bounds contain it, so put it outermost.
  `OrbitTapArea(merge: true)` merges a field's own semantics.
- Presentation imports only its own `application/`, `shared/`, `orbit_ui` and
  `helix_remote_domain` (since step 4 nothing in the app imports
  `helix_remote_ui`). Something that reads several
  features goes in `shared/` (see `orbit_home_connector.dart` and
  `orbit_you_connector.dart`). orbit_ui changes are behaviour only.

## Waiting on the owner

- **A publisher key, before any pack is usable.** The trust anchor ships
  **empty**, so `checkOrbitPack` refuses every pack as `unknownPublisher`.
  Run `dart run tool/theme_pack_tool.dart keygen --seed-file <somewhere
  private>` from `helix_remote/`, keep the seed file off ordinary backups,
  and build the app with
  `--dart-define=HELIX_PACK_PUBLISHERS=<publisher id>:<the 64-hex public key
  keygen prints>` (comma-separate more than one). Step 3 made the anchor that
  define rather than a page where a key is typed - see the deviation entry in
  the Part C section, which is yours to rule on. Nothing is downloadable, and
  no pack page can work, until a build carries the key.
- **A pack folder and a redeploy, before anything is downloadable.** Step 2's
  routes answer an empty list until the production `.env`
  (`J:\Projects\Servers\helix_server\helix\.env`) says
  `HELIX_PACKS_DIR=<absolute path>`, and they only go live when you tag, build
  and switch (`release-helix.ps1` / `deploy-helix.ps1`) - an agent never does
  that. Nothing else to do: no migration, no Caddy line, and a folder with no
  packs in it is a healthy server. Publishing is
  `dart run tool/theme_pack_tool.dart publish --in <pack> --out <that folder>`.
- Review of every "(pending review)" commit and the DEVIATIONS entries.
- **Which kind a pack offer is.** One `HELIX_PACKS_DIR` holds theme packs and
  sound packs together, and `GET /v1/packs` says nothing about which a row is,
  because `contents` lives inside the signed manifest the endpoint never opens.
  Three ways out, and the second is a server change, so it is yours: let the app
  fetch a manifest and refuse what is not its kind (what it does today: the page
  reads one manifest per offer and never lists the other kind, so the cost is a
  manifest read per offer, bounded at 64, and no server change); add a `contents`
  to the list entry (protocol, server, api and app, plus a redeploy); or publish
  sounds into a second folder and name it with a second env line.
- A real ringtone: a signed sound pack to publish, so the Ringtones page has
  something to list beyond the phone's own. Until then the page, its choice,
  the copy and the per-ringtone channel run against fakes; a new APK is needed
  to hear any of it on the phone.
- Part B step 5's second bullet: the debug APK on your phone and the Windows
  run. Nothing was built for you here (AGENTS.md: the owner builds).
- S1's `/u/<~name>` page and E6's `GET /v1/backups/full/meta` are code in this
  branch; they answer only after you tag, build and switch production.

Decided and done since the last hand-off:

- The other agent's ADR-032 work is committed (`f856177`, `ed3317d`,
  `57b4805`): the account-status route and the sign-in page that asks it. It
  is not part of any Part B or Part C batch, and `dart analyze server tool` is
  clean with it in the tree.
- The operator sees the whole phone number (ADR-030, re-confirmed by the owner
  on 2026-10-23). The admin rule "only the last four phone digits are ever
  handled" has been rewritten as "the whole number is read in one file, and its
  hash never": `admin/lib/src/features/common/format.dart` is the only place
  that reads `account.phoneNumber`, the two account screens only call
  `accountPhone()`, and the hash stays banned. `test/accounts_test.dart` shows
  both answers. AGENTS.md's known-failure entry for it is gone.
- The privacy policy text after ADR-030 (GAPS.md W2) is written up in all three
  copies, with the reason the owner gave: a report of abuse is acted on by the
  number it came from.

# From the earlier handoff (2026-10-18, Part A)

Still useful. The phase table that came with it is out of date: Part A is
finished (Phase 4 and Review 4), and Part B is above. "Never push" now has
one exception: the owner had `orbit-ui` pushed on 2026-10-20.

### Read in this order

1. `PORT_PLAN.md`, the plan of record:
   - the decisions table;
   - every phase, with its progress checkboxes;
   - "Rules for every agent". These go into `orbit/flutter/AGENTS.md` in
     Phase 2.
2. `prototype/README.md`: how to run the prototype, its tools, the design
   decisions and the file map.
3. `prototype/SCREENS.md`:
   - the app's feature checklist;
   - "Design changes you approved", items 1 to 20.
4. `contracts/README.md`, then the eight contracts. Each ends with
   "Decisions and Phase 1b".
5. `GAPS.md`: everything Review 1 decided, and what to build or not build in
   Part B.
6. `prototype/INTERACTIONS.md`: 307 behaviours. Each one becomes a widget
   test.
7. The repo's `AGENTS.md` at the root. Its rules apply in full.

### Rules that matter most

- **The prototype is the specification.** Sizes, colours and spacing come
  from its CSS and tokens, never from guesses. Anything that can't be
  matched goes in `DEVIATIONS.md`, and you ask the owner.
- **A screen never reads providers, the database, the router or the
  engine.** Model in, actions out (`contracts/`).
- **Small batches, stop at each review.**
  - After the owner approves a batch, commit all uncommitted work, with
    `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  - Never push.
- **Never touch `helix_local/`.** Production (Helix Global) runs on the
  owner's PC: never stop or restart it, and never run deploy scripts.

### Gotchas found the hard way

- **Shell.** It is Git Bash on Windows; every command prints an "ng
  completion" warning, so ignore it. Heredocs with apostrophes, `\b` or
  `\n` break or write control characters into files. Write multi-line
  patches as a Python file with the Write tool, then run it with
  `python -I`.
- **Prototype server.**
  - `python prototype/serve.py` serves on port 5317.
  - A side session may already serve it there; just use it.
  - Launch config: `helix-prototype` in `.claude/launch.json`.
- **Screen list.** `python prototype/tools/manifest.py` writes
  `screens.json` and `INTERACTIONS.md`.
  - It runs the scripts in Node (`tools/manifest_node.js`), with no
    browser.
  - It refuses to write if any screen is missing or has no `interactions`
    list.
- **Screenshots.**
  - `python prototype/tools/shoot.py --device phone|window-m|window-l --theme <id> [--query scroll=760] <keys>`.
  - Run one at a time (the default).
  - Headless Chrome sometimes captures a page before every script has
    loaded, so a shot can come out blank or unstyled. Retake it, or use
    `flutter/tools/compare/shoot_html.py`, which waits for readiness.
  - Phone shots are 640 px wide with the phone at the left.
- **Bare mode.** `?bare&device=…&theme=…&scroll=…#key` shows one screen alone.
- **Reduce motion.** The in-app browser pane has it on. Never use
  near-zero transitions on every element: colours freeze when frames don't
  run. Turn animation and transitions off instead.
- **Prototype screens.** Each screen's interactions live next to its code
  (`interactions: [[gesture, on, does, layout?]]`), and a new screen needs
  that list.
- **Themes.** `python prototype/tools/themes.py` regenerates
  `css/themes.css` and `js/themes.js`. It must report "0 contrast failures".
- **The state kit.** Lists use `Kit.skeleton`, pages `Kit.loading`, and
  failures `Kit.loadFailed`. Also `Kit.permission`, `Kit.fieldLock`, and
  `App.snack(text, action, {tone: 'error'})`. Never draw a one-off loading
  or error state.

### Owner preferences

- Plain English.
- Ask before decisions that are theirs.
- Show screenshots at reviews.
- Before large or outward-facing steps, propose and wait. Nothing goes into
  the main app before Part B.
