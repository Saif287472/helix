# helix_admin (operator console)

Helix Admin: the Flutter operator console for a Helix Remote **v2 server**
(`../server`), including Helix Global. It runs on the v2 admin API only
(`helix_remote_api/v2.dart`: `HelixAdminApi`, `AdminClient`); there is no v1
admin client and it cannot talk to a v1 server. Light theme only, English
only.

It is one package of the `helix_remote/` pub workspace. Start with
[`../../AGENTS.md`](../../AGENTS.md), the plan
([`../docs/architecture/ARCHITECTURE_V2_PLAN.md`](../docs/architecture/ARCHITECTURE_V2_PLAN.md))
and the server side of this API
([`../server/lib/src/modules/admin/MODULE.md`](../server/lib/src/modules/admin/MODULE.md),
[`../docs/protocol/v2/REST_V2.md`](../docs/protocol/v2/REST_V2.md), "admin").

## Using it against a v2 server

[`../docs/operations/V2_SERVER_HANDOFF.md`](../docs/operations/V2_SERVER_HANDOFF.md),
"Operator console", is the operator guide: server address (https only, plain
http for this machine), first-run setup or `HELIX_ADMIN_PASSWORD`, sign-in and
lockout, the 7-day session, what each screen does.

For development, from `helix_remote/admin`: `flutter run -d windows` (or on a
connected phone). **Agents do not build APKs (`flutter build apk`) unless the
user asks;** say whether a new APK is needed instead (see `AGENTS.md`).

## Screens

| Place | What it does | API |
|---|---|---|
| Sign-in / setup | server address, first-run admin password (12 to 256 characters, typed twice) or sign-in; lockout and `Retry-After` wording; session notices | `setupStatus`, `setup`, `signIn` |
| Lock screen | the device's own screen lock, when App lock is on | (local) |
| Overview | server facts, health, maintenance mode, federation switch, feature flags, activity numbers (open sockets, requests, 5xx share, dead jobs, undelivered messages, crash reports) | `config`, `updateConfig`, `featureFlags`, `setFeatureFlag`, `ops.ready`, `metrics` |
| Accounts | paged list, search by Helix name or last 4 digits, status filter; one account opens as a sheet with its devices; suspend or resume, ban, delete (type `DELETE`), revoke device, recovery code (shown once) | `accounts`, `account`, `suspend`, `unsuspend`, `ban`, `deleteAccount`, `revokeDevice`, `createRecoveryCode` |
| Invites | only when the server registers by invite; create (code shown once), cancel | `invites`, `createInvite`, `cancelInvite` |
| Reports | open, resolved, dismissed; the queue is a list of tiles, and one report opens as a sheet with its note and its actions — resolve or dismiss, or open the reported account in a sheet of its own. The Reports item wears how many are open (`50+` when the console has only seen a page). | `reports`, `resolveReport` |
| Configuration | one page, top down: a hero card (name, version and sign-up pills, Edit name); a health card (the server's own readiness checks as a meter, then maintenance mode and purge); four quick-access tiles - Network & Sync (federation), Logs & Activity (the live log as a sheet over this page, the audit trail as its own page), Features (flags), Security (App lock, admin password); a grouped list of the facts an operator copies (address, Node ID, attachment limit, signed-in until); a red danger zone with sign out | `updateConfig`, `changePassword`, `purge` |
| Configuration > Audit | newest first, "Load more" paging | `audit` |
| Configuration > Logs | recent lines, filter, copy, "Follow live" over the admin WebSocket (polls where a socket is impossible) | `logs`, `logStream` |

Overview, Accounts, Invites and Reports are what an operator works through;
Configuration is where the server itself is read and set, and where sign-out
lives. On a window 700 dp or wider every place is a pill in the header; on a
phone the first four are the pill dock at the bottom (the same shape the app's
Orbit tabs use) and Configuration is behind the gear in the header. An account,
a report and the live log open as sheets over the page that called them, so
nothing about them is a place of its own; a sheet is a route like a page, so
ending the session closes it with everything else above the shell. A sheet has
its own messenger (`widgets/console_sheet.dart`): it covers the bottom of the
page behind it, where that page would otherwise show what a refused action
said.

## Layout

```
lib/main.dart                       entry
lib/src/app.dart                    MaterialApp (light only), the gate by session phase
lib/src/api/
  admin_api_factory.dart            the ONE place a HelixAdminApi is built (AdminApiFactory)
  server_address.dart               address parsing; http only for this machine
  error_text.dart                   ApiException/NetworkException -> operator wording
lib/src/session/
  admin_session_controller.dart     setup, sign-in, saved session, 7 day expiry, device lock;
                                    hands feature controllers an AdminContext
  admin_session_scope.dart          InheritedNotifier for the session
lib/src/services/                   TokenVault (secure storage), AdminSettings (prefs),
                                    DeviceLock (local_auth), AdminServices (all of them)
lib/src/features/<feature>/         <feature>_controller.dart (a ChangeNotifier) + screens
  common/feature_controller.dart    FeatureController, PagedController (cursor paging)
lib/src/widgets/                    dialogs (reason, typed confirm, show-once code),
                                    console_sheet (a view over the page that called it),
                                    PasswordField, PagedListView
```

State is plain `ChangeNotifier` controllers (one per feature) and `setState`,
as in the v1 console. Riverpod belongs to the app (plan §6.4), not here. A
controller is created by its screen, takes an `AdminContext` (API, a way to
report a failed call, the clock) and never touches widgets.

## Rules this package keeps (`test/rules_test.dart`, `test/architecture_test.dart`)

- English string literals only; no localization layer. Light theme only
  (`themeMode` pinned, no `darkTheme`).
- No colour literals in `lib`: colours come from the theme or
  `helix_remote_ui` tokens (`HelixStatusColors`, ...). Sign-in uses
  `HelixThemes.signIn()`.
- Every `IconButton` has a `tooltip:`; tap targets are at least 48 px
  (`accessibility_test.dart` runs Flutter's guidelines over every screen).
- Nothing is logged or printed; no `dart:io`, no files, no direct `http` or
  WebSocket use (all network goes through `helix_remote_api`, plan §8).
- The admin token lives only in `TokenVault` (platform secure storage), is
  never read by any screen, never printed. The password exists only in a text
  field until it is sent.
- Invite and recovery codes are returned to the screen that shows them once;
  no controller keeps them and no list carries them.
- Phone numbers: an account's own app reports its number once after signing in,
  and the server keeps it sealed (`HELIX_PHONE_KEY`, ADR-030) so the operator
  can tell an abuse report came from whom and act on it. `accountPhone()` in
  `lib/src/features/common/format.dart` is the only place that reads it, the
  accounts list and account detail are the only screens that show it, and it is
  never copied, stored or logged. Without the key the server sends only the last
  four digits (`test/accounts_test.dart` covers both answers, and a
  `rules_test.dart` rule keeps the number in that one file).
- Imports: only `helix_remote_protocol`, `helix_remote_api` (`v2.dart`) and
  `helix_remote_ui`; no v1 package, no state-management package.

## Tests

From `helix_remote/`:

```powershell
flutter analyze
cd admin; flutter test
```

or the full gate: `./scripts/verify.ps1` (Windows) or `./scripts/verify.sh`.

- Widget tests drive the real app and the real `HelixAdminApi` against
  `test/support/fake_admin_server.dart`, an in-memory v2 admin API behind an
  `http.Client` (also: fake secure storage, device lock, log socket and a
  clock). `session_flow_test.dart` (setup, sign-in, lockout, expiry, App lock),
  `dashboard_test.dart`, `accounts_test.dart`, `invites_reports_audit_test.dart`,
  `logs_test.dart`, `settings_test.dart`, plus unit tests for the metrics
  parser, address parsing, error wording and storage.
- `integration_test/startup_journey_test.dart` is the device-run smoke test
  (`flutter test integration_test`).
- The same calls against a real in-process v2 server are in
  `../server/test/client/admin_console_v2_test.dart` (this package may not
  depend on the server).
