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

To do:
1. **Connectors** in `features/settings/presentation/`, each replacing the
   old page of the same file name, over the existing providers:
   - `privacy_page.dart`: `PrivacyController`, `SettingsActions`, app lock
     and blocked. The keys `onChanged` sends: lastSeen, online, groups,
     receipts, typing, timer ('Off', '24 h', '7 d', '90 d'), byNumber,
     byName, lock, lockAfter ('Now', '1 min', '5 min', '30 min').
     `askNumber` comes from `PrivacyState.needsNumber`. The viewer's name is
     the most recent chat's name, or "Someone". Read the chats through
     `core/chat/chat_gateway.dart`, because a feature may not import another.
   - `notifications_page.dart`: alerts, sound, vibrate and previews, the OS
     permission, and muted chats ("Muted" or "Muted until …").
     `showRingtone: false` until an Orbit ringtone sound is bundled (it needs
     a sound from the owner; log it in DEVIATIONS).
   - `chats_page.dart`: text size 90/100/115/130, Enter sends, and the four
     media policies (`DownloadWhen` ↔ `MediaDownloadPolicy`).
   - `storage_page.dart`: `storageSummaryProvider`. The chat list stays empty
     until E2 is built.
   - `account_page.dart`: the overview, `AccountActions` (export, sign out),
     and delete. "Export first" only exports. For "Since Sep 2026", add
     `createdAt` in `EngineSettingsGateway.account()`.
2. **Tests.** `test/settings/settings_pages_test.dart` and
   `a3b_rules_test.dart` still use the deleted `SettingsTab`, and
   `test/profile/profile_page_test.dart` tests the old page. Port them to the
   Orbit screens and keep what each one proves. Add tests for the checkup
   rules, the theme choice and Appearance.
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
