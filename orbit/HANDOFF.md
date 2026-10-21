# Orbit Part B: where it stands (handoff, 2026-10-20)

For picking the port up on another machine or in a cloud session. The plan
of record is `PORT_PLAN.md` (Part B); what each screen needs is in
`contracts/`; every difference from the prototype is in `DEVIATIONS.md`;
the approved backend items are in `GAPS.md`. Read `../AGENTS.md` first.

## The branch

- Work happens on `orbit-ui`, never on `main`. On the main PC it is the
  worktree `J:/wt/orbit`; elsewhere, check the branch out. It was pushed to
  `origin` on 2026-10-20 so it can be continued away from that PC. Push it
  again only when the owner asks. Never merge it into `main`: the owner
  merges after review.
- One commit per batch, marked "(pending review)" in the message and in
  `PORT_PLAN.md`'s progress notes.

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
| (next) | Batch 9 connectors (the shorter plan) |

## The shorter plan (owner, 2026-10-21)

Get the app standing on Orbit first; polish later.

Done (commit after 77ee515, "batch 9 connectors"): Orbit connectors for
password, delete account, blocked, about, legal, advanced, devices,
security activity and backup, with their tests ported (and the journey
test). Fixes found on the way: the password page's "set" and "change"
were the wrong way round in the first draft (fixed before commit); the
delete page can now ask for the number before texting a code (orbit_ui,
behaviour only: `onSendCode` takes the phone).

Still on the old pages, on purpose:
- Approve a new device: the Orbit screen has no place for the account key
  code the old page shows to compare, which is part of the trust check.
  Add it to `ApproveDeviceModel` before porting.
- Transfer and Recovery backup: incoming offers and the recovery secret
  need careful mapping; the old pages work.
- Link this device and Restore history: no Orbit screens yet.

Next: the owner tries a debug APK.

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
- (next commit): item 6's docs. THREAT_MODEL T-11, `app/MODULE.md`,
  `contracts/you.md`. No ADR: one foreground runtime still runs at a time.
No server change or migration. A new APK is needed to try it. Known gap: a
rotated FCM token reaches only the account on screen; the others get it
when they are next opened.

Deferred until the owner asks: every backend item (S1, E1 to E6), the
pixel checks, DEVIATIONS and FEATURE.md updates, batch 10 (the wide
Windows layout), and Part B steps 3 to 5 (the rename, deleting
`helix_remote_ui`, the full verify). The lists below keep their detail.

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
- Not run: the pixel check (`compare.sh`) on the batch 8 keys.

To do:
1. Run the pixel check on the batch 8 keys (the segment change moves no
   pixels, but check).
2. Log in DEVIATIONS "Part B batch 8": no ringtone row (needs a sound
   from the owner); the storage bar is messages against all media and the
   chat list is empty until E2; the notifications preview text is a fixed
   sample; "Export first" only exports.
3. **The approved backend items**, each as its own commit (helix-feature
   skill):
   - S1: the share link `/u/<~name>`, app links and scan-to-chat.
   - E1: share the profile photo with people you message.
   - E2: storage size by kind and by chat.
   - E3: free one chat's media and keep its messages.
4. **Docs.** `DEVIATIONS.md` gets a "Part B batch 8" section, `PORT_PLAN.md`
   a progress note, and the settings and profile `FEATURE.md` files need
   updating.

After batch 8 comes batch 9: settings pages, devices and backup
(`contracts/devices_backup.md`, with E4, E5 and E6). Then batch 10, the
wide Windows layout (`contracts/frame.md`). Then Part B steps 3 to 5: the
Orbit rename, deleting `helix_remote_ui`, and the full verify.

## How every batch is checked

From `helix_remote/`:
- `flutter analyze`
- `dart analyze server tool`
- `dart format --output=none --set-exit-if-changed app admin server packages tool`
- `dart run tool/check_governance_controls.dart`
- `flutter test` in `app`, `packages/orbit_ui`, `packages/helix_remote_ui`
  and `packages/helix_remote_architecture_rules`, plus any package you
  changed.
- Also `flutter analyze` in `orbit/flutter/apps/orbit_preview`.

Server tests need PostgreSQL 17 and `HELIX_TEST_DATABASE_URL`: run
`HELIX_REQUIRE_TEST_DATABASE=1 dart test --concurrency=3` in `server/`,
never at the same time as the Flutter tests.

`flutter pub get` dirties the plugin registrants. `git checkout --` them
unless their content changed.

**Pixel check (Windows only).** Run
`orbit/flutter/tools/compare/partb/compare.sh <keys>`. Every key a batch
touches must keep its Review 4 score (`partb/review4_scores.txt`) unless
the change is deliberate and logged in DEVIATIONS. The prototype shots are
not committed; make them with `tools/compare/shoot_html.py` (see the
compare README). A cloud or Linux session cannot run this check, so it
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
- Presentation imports only its own `application/`, `shared/`, `orbit_ui`,
  `helix_remote_ui` and `helix_remote_domain`. Something that reads several
  features goes in `shared/` (see `orbit_home_connector.dart` and
  `orbit_you_connector.dart`). orbit_ui changes are behaviour only.

## Waiting on the owner

- Review of every "(pending review)" commit and the DEVIATIONS entries.
- The admin test "only the last four phone digits are ever handled" has
  failed since ADR-030 (AGENTS.md). Should the rule change?
- A sound for the Orbit ringtone.
- The privacy policy text after ADR-030 (GAPS.md W2).

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
