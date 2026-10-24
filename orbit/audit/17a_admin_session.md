# Sweep 17a — `admin/` console: session, auth, transport, shell

Read-only. Scope: the operator console's session and transport layer
(`session/admin_session_controller.dart` 486, `session/admin_session_scope.dart`
27, `api/server_address.dart` 91, `api/admin_api_factory.dart` 23,
`api/error_text.dart` 87, `services/token_vault.dart` 83,
`services/admin_settings.dart` 57, `services/admin_services.dart` 31,
`services/device_lock.dart` 44, `features/auth/sign_in_screen.dart` 212,
`features/auth/lock_screen.dart` 107), the shell (`app.dart` 147,
`features/shell/admin_shell.dart` 438, `features/common/feature_controller.dart`
138, `widgets/paged_list.dart` 139), and the tests that hold them
(`session_flow_test.dart` 442, `accessibility_test.dart` 182, `rules_test.dart`
362, `architecture_test.dart` 90, `support/harness.dart` 235). Accounts, ops,
logs, reports, audit, invites and the dialogs are `17b_admin_console.md`.

## What is sound

- **The token never leaves secure storage except as a whole session.** The
  vault is `flutter_secure_storage` under one key
  ([token_vault.dart:35-41](file:///J:/Projects/helix/helix_remote/admin/lib/src/services/token_vault.dart#L35-L41)),
  `StoredSession.toString()` prints the server and expiry only
  ([token_vault.dart:15-17](file:///J:/Projects/helix/helix_remote/admin/lib/src/services/token_vault.dart#L15-L17)),
  no screen reads a token and settings never hold one
  ([rules_test.dart:210-227](file:///J:/Projects/helix/helix_remote/admin/test/rules_test.dart#L210-L227)),
  and the password lives only in a controller for the duration of a call
  ([admin_session_controller.dart:254-291](file:///J:/Projects/helix/helix_remote/admin/lib/src/session/admin_session_controller.dart#L254-L291)).
- **The address is checked before anything is sent.** Cleartext is refused
  except loopback and the emulator alias, credentials in the URL are refused,
  query and fragment are dropped, trailing slashes are stripped
  ([server_address.dart:24-68](file:///J:/Projects/helix/helix_remote/admin/lib/src/api/server_address.dart#L24-L68));
  the only client is built in one file
  ([admin_api_factory.dart:21-23](file:///J:/Projects/helix/helix_remote/admin/lib/src/api/admin_api_factory.dart#L21-L23),
  [architecture_test.dart:78-89](file:///J:/Projects/helix/helix_remote/admin/test/architecture_test.dart#L78-L89)).
- **Sign-out is server-first, and honest when the server is unreachable.**
  `DELETE /v1/admin/sessions` ends every admin session; the local vault is
  cleared either way and the notice says the session stays valid on the server
  until it expires
  ([admin_session_controller.dart:359-375](file:///J:/Projects/helix/helix_remote/admin/lib/src/session/admin_session_controller.dart#L359-L375),
  [session_flow_test.dart:327-350](file:///J:/Projects/helix/helix_remote/admin/test/session_flow_test.dart#L327-L350)).
- **The saved session is re-proved with the server before it is used.** The
  expiry is checked locally, then `GET /v1/admin/config` is the cheapest
  authenticated read
  ([admin_session_controller.dart:149-184](file:///J:/Projects/helix/helix_remote/admin/lib/src/session/admin_session_controller.dart#L149-L184)).
- **Only a rejected token ends a session.** `endsAdminSession` excludes
  `invalid_credentials`, so a wrong current password in the change-password
  dialog is reported instead of signing the operator out
  ([error_text.dart:81-87](file:///J:/Projects/helix/helix_remote/admin/lib/src/api/error_text.dart#L81-L87),
  [admin_session_controller.dart:327-331](file:///J:/Projects/helix/helix_remote/admin/lib/src/session/admin_session_controller.dart#L327-L331)).
- **App lock relocks and re-validates.** One minute in the background closes
  the API and keeps the vault; unlocking runs `_resume` again
  ([admin_session_controller.dart:70](file:///J:/Projects/helix/helix_remote/admin/lib/src/session/admin_session_controller.dart#L70),
  [:420-441](file:///J:/Projects/helix/helix_remote/admin/lib/src/session/admin_session_controller.dart#L420-L441)).
  The device prompt's own backgrounding is not counted as time away
  ([session_flow_test.dart:420-433](file:///J:/Projects/helix/helix_remote/admin/test/session_flow_test.dart#L420-L433)).
- **Nothing from an earlier session survives on screen.** Account pages and
  dialogs sit above the shell, and every non-signed-in phase pops to the first
  route; the shell is keyed by the API instance, so a new session starts with
  no controller state
  ([app.dart:53-57](file:///J:/Projects/helix/helix_remote/admin/lib/src/app.dart#L53-L57),
  [:99-108](file:///J:/Projects/helix/helix_remote/admin/lib/src/app.dart#L99-L108)).
- **Only the live log is a stream, and its failure is a fallback, not an
  error.** `logStream()` reports a platform with no socket (the web build)
  through the stream's error, so the logs controller falls back to polling
  instead of throwing out of the switch
  ([admin_client.dart:201-243](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/clients/admin_client.dart#L201-L243),
  [logs_controller.dart:119-156](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/logs/logs_controller.dart#L119-L156)).

## AUD-17a-1 A storage fault at start-up strands the console on the launch screen forever

**Severity:** P3
**Confidence:** likely
**Where:** [app.dart:27-33](file:///J:/Projects/helix/helix_remote/admin/lib/src/app.dart#L27-L33),
[admin_session_controller.dart:111-119](file:///J:/Projects/helix/helix_remote/admin/lib/src/session/admin_session_controller.dart#L111-L119),
[admin_session_controller.dart:149-151](file:///J:/Projects/helix/helix_remote/admin/lib/src/session/admin_session_controller.dart#L149-L151),
[token_vault.dart:40-52](file:///J:/Projects/helix/helix_remote/admin/lib/src/services/token_vault.dart#L40-L52),
[app.dart:113-147](file:///J:/Projects/helix/helix_remote/admin/lib/src/app.dart#L113-L147)

**What:** `initState` calls `start()` fire-and-forget. `start()` awaits
`services.loadSettings()` and then `_resume()`, which awaits
`services.vault.read()`. Neither call is inside a `try`. The vault catches only
`FormatException` from its own decoding; a `PlatformException` from
`flutter_secure_storage` (Android Keystore after a device restore, a locked
keystore, a missing plugin on an unsupported platform) and a failure of
`SharedPreferences.getInstance()` propagate out of `start()` as an unhandled
async error. `main()` installs no error handler, and the phase is still
`starting`, so `_Gate` keeps drawing `_Launching` (the mark, the name, the
skeleton line) with no message, no retry and no way to reach the sign-in form.

**Trigger:** launch the console on a device whose secure storage or
preferences cannot be read. The trigger is platform-dependent, which is why
this is `likely` and not `confirmed`; the code path itself is unconditional.

**Evidence:** `_phase` starts as `SessionPhase.starting`
([admin_session_controller.dart:45](file:///J:/Projects/helix/helix_remote/admin/lib/src/session/admin_session_controller.dart#L45))
and only `start()`, `unlock()` and `_setPhase` change it; the only phase-less
state is `starting`, which `_Launching` owns
([app.dart:99-107](file:///J:/Projects/helix/helix_remote/admin/lib/src/app.dart#L99-L107)).
The tests use `MemoryTokenVault` and `MemoryAdminSettings`, which cannot throw
([harness.dart:93-106](file:///J:/Projects/helix/helix_remote/admin/test/support/harness.dart#L93-L106)),
so no test reaches this.

**Impact:** The operator sees a console that never finishes starting; the only
recovery is to clear the app's data (which also discards the saved session)
or reinstall. Nothing is lost on the server, and it is an outage rather than a
security hole.

**Fix sketch:** make `start()` a guarded sequence: wrap the settings load and
`_resume()` in a `try`, and on failure clear the vault (when the vault is what
failed) and `_toSignedOut(error: 'The console could not read its saved
sign-in. Sign in again.')`. Adding `runZonedGuarded`/`FlutterError.onError`
in `main.dart` is a second line of defence, not the fix. No wire or schema
change.

**Test that proves it:** a `TokenVault` fake whose `read()` throws
`PlatformException` must land on the sign-in form with the message. Today the
harness has no throwing vault and the phase would never leave `starting`.

**Overlap:** none. This is a start-up robustness gap, not a state-machine
bug.

## AUD-17a-2 A transient failure at launch makes a still-valid saved session unusable until the app restarts

**Severity:** P3
**Confidence:** confirmed
**Where:** [admin_session_controller.dart:165-178](file:///J:/Projects/helix/helix_remote/admin/lib/src/session/admin_session_controller.dart#L165-L178),
[admin_session_controller.dart:396-401](file:///J:/Projects/helix/helix_remote/admin/lib/src/session/admin_session_controller.dart#L396-L401),
[sign_in_screen.dart:27-41](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/auth/sign_in_screen.dart#L27-L41),
[sign_in_screen.dart:45-57](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/auth/sign_in_screen.dart#L45-L57)

**What:** when the launch check fails for a reason that is not a rejected
token (timeout, DNS, 5xx, maintenance), `_resume` keeps the vault and calls
`_toSignedOut(error: …)`. The console then shows the sign-in form. The only
action there is `Continue`, which runs `checkServer` and, on success, asks for
the admin password; the saved session — still valid, still in secure storage —
can only be used by restarting the console, because nothing calls `_resume`
again. The screen's own copy ("Could not reach the server. Check the address
and your connection, then try again") invites exactly the retry that does not
exist.

**Trigger:** open the console while the server is briefly unreachable (a
restart, a Wi-Fi switch, a laptop waking before DNS is up). The session was
never invalid; the operator is now asked for the password and every other
admin session stays alive on the server.

**Evidence:** `_resume`'s success path is the only `_enter` besides
`_authenticate`
([admin_session_controller.dart:183](file:///J:/Projects/helix/helix_remote/admin/lib/src/session/admin_session_controller.dart#L183),
[:278](file:///J:/Projects/helix/helix_remote/admin/lib/src/session/admin_session_controller.dart#L278)),
and `SignInScreen._submit` only ever calls `checkServer`, `setup` or `signIn`
([sign_in_screen.dart:45-57](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/auth/sign_in_screen.dart#L45-L57)).
The test that covers the failure asserts the vault is kept
([session_flow_test.dart:251-260](file:///J:/Projects/helix/helix_remote/admin/test/session_flow_test.dart#L251-L260))
but never checks that the saved session can be used again.

**Impact:** a one-off network blip costs a password entry and leaves a valid
token sitting in storage; the operator may reasonably conclude the console
lost the session. Low severity, entirely recoverable, but the retained vault
is then dead weight until the next launch.

**Fix sketch:** when `_resume` fails with a non-session error and a stored
session exists, offer a "Try the saved session again" action (or make
`checkServer` consult the vault when the checked address matches the stored
one and the token is unexpired). No wire or schema change.

**Test that proves it:** start with a saved session, make the fake server
unreachable, launch, restore it, press the retry action, and assert the console
opens (and that `GET /v1/admin/config` was sent with the stored token) without
a `POST /v1/admin/sessions`.

**Overlap:** AUD-17a-1 is the same start-up seam but a different failure
(a throw, not a handled error); the fixes are independent.

## AUD-17a-3 The segmented bar's segments are 44 px tall, under the 48 px rule the console tests claim to enforce

**Severity:** P3
**Confidence:** confirmed
**Where:** [console_kit.dart:303-330](file:///J:/Projects/helix/helix_remote/admin/lib/src/widgets/console_kit.dart#L303-L330),
[rules_test.dart:85-98](file:///J:/Projects/helix/helix_remote/admin/test/rules_test.dart#L85-L98),
[accessibility_test.dart:37-42](file:///J:/Projects/helix/helix_remote/admin/test/accessibility_test.dart#L37-L42)

**What:** `_SegmentButton`'s `ConstrainedBox` is `minHeight: 44` and the
`InkWell` is its child, so the segment that answers taps is 44 px tall. The
`ConsoleSegmented` container adds 4 px of padding around the row, which is
painted as part of the control but is outside the tappable area. AGENTS.md's
product rule is "tap targets are at least 48 px", and the admin console repeats
it as its own rule; the a11y test's `androidTapTargetGuideline` still passes
because the `Semantics` node is not `container: true`, so its rect is the
padded row (52 px), not the `InkWell`. The shrinking-pattern rule does not look
for `minHeight: 44`
([rules_test.dart:86-90](file:///J:/Projects/helix/helix_remote/admin/test/rules_test.dart#L86-L90)).

**Trigger:** a thumb on the "Audit / Logs / Config" bar on a phone, or any
pointer landing in the 4 px band above or below a segment: the control looks
pressed-able and does nothing.

**Impact:** 4 px short of the stated minimum on the console's primary tab
control, and the two tests that exist to enforce the rule both miss it by
construction. Cosmetic-to-minor for most users; it matters for the
dexterity-impaired operator the rule is for.

**Fix sketch:** `minHeight: 48` in `_SegmentButton`, or wrap the segment in
`OrbitTapArea`-equivalent padding that is inside the `InkWell`; and extend the
rules test to flag `minHeight`/`maxHeight` below 48. No wire or schema change.

**Test that proves it:** `tester.getSize(find.byType(InkWell).first)` inside
`ConsoleSegmented` must be at least 48 high; today it is 44. Alternatively add
a `check()` at 2x text scale on `System > Audit`, which would also catch the
dialog content issue in 17b.

**Overlap:** the console's own copy of the tap-target rule; the app-side
primitives were covered in sweep 16b.

## Coverage gaps

- No test for a vault or preferences failure at start-up (AUD-17a-1), and none
  for a transient `_resume` failure followed by a retry (AUD-17a-2). Both are
  start-up states a real device can reach and a fake cannot today.
- The accessibility suite runs at 1x text scale in a 1000×1600 window for every
  screen, plus one phone-sized sign-in check
  ([accessibility_test.dart:137-181](file:///J:/Projects/helix/helix_remote/admin/test/accessibility_test.dart#L137-L181)).
  No console screen is checked at 2x, unlike the app's sign-in page.
- `AUD-17a-3` shows the guideline can be satisfied by a merged semantics rect;
  a per-widget size assertion is the only thing that would hold the 48 px rule.
- The vault has a test for an unreadable value (`FormatException`) but not for
  a platform exception, so the "treat as signed out" promise
  ([token_vault.dart:49-52](file:///J:/Projects/helix/helix_remote/admin/lib/src/services/token_vault.dart#L49-L52))
  is only half tested.

## Considered and dropped

- **A late `checkServer` response sending the password to a previously typed
  address.** The leading candidate from the first read does not survive the
  wiring: the URL field is disabled while the check runs
  ([sign_in_screen.dart:133](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/auth/sign_in_screen.dart#L133)),
  and `addressEdited` is only reachable after the check has set
  `_setupRequired` or an error, at which point `_discardPending` clears it
  ([admin_session_controller.dart:223-231](file:///J:/Projects/helix/helix_remote/admin/lib/src/session/admin_session_controller.dart#L223-L231)).
  Dropped.
- **The transport's default `followRedirects: true` leaking the bearer
  token.** Dart strips `authorization`, `cookie` and `www-authenticate` on a
  cross-origin redirect and only keeps them for a subdomain
  (`_httpClient.shouldCopyHeaderOnRedirect`, Dart SDK `http_impl.dart:3070-3086`),
  and a redirected request is sent with an empty body (`:3115-3117`), so the
  password POST cannot be replayed either. The remaining subdomain case is
  Dart's own policy; not a console defect.
- **The shell showing the Invites place before config arrives**
  (`usesInvites` is true while `_config == null`,
  [server_controller.dart:69-72](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/dashboard/server_controller.dart#L69-L72)).
  A sub-second flicker on a phone-registration server; the place is removed as
  soon as the config lands. Not worth a finding.
- **`AdminSessionScope.of` in `_sessionLine`**
  ([admin_shell.dart:142-149](file:///J:/Projects/helix/helix_remote/admin/lib/src/features/shell/admin_shell.dart#L142-L149)):
  subscribing in `build` is correct here (the line follows the expiry), not a
  bug.
