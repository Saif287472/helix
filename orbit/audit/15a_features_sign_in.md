# Sweep 15a - app `lib/features/sign_in`

Read in full (6 files, 1,540 lines): `application/sign_in_controller.dart`
(752), `application/sign_in_state.dart` (255), `application/sign_in_copy.dart`
(197), `application/sign_in_view.dart` (104),
`application/sign_in_countries.dart` (25),
`presentation/sign_in_screen.dart` (207). Cross-checks: `core/engine/post_sign_in.dart`,
`core/platform/saved_accounts.dart`, `core/platform/phone_numbers.dart`,
`core/engine/failure_copy.dart`, `features/devices/application/devices_providers.dart:570`,
`packages/helix_remote_api/lib/src/v2/transport/errors.dart:120-129`,
`packages/helix_remote_protocol/lib/src/json.dart:242`,
`packages/helix_remote_engine/lib/src/account/account_service.dart:100-120`,
`server/lib/src/modules/identity/{application/sign_up.dart,application/registration.dart,application/context.dart,domain/secrets.dart}`,
`packages/orbit_ui/lib/src/screens/signin/signin_screen.dart` (the model's
consumer, for copy only), `app/test/sign_in_flow_test.dart` (test names).

## What is sound

- **One state machine, one place.** Page order, Terms requirement
  (`showsTerms => requiresTerms`, deliberately not `isNewAccount &&`), the ask
  before a code is texted (ADR-032) and every transition live in the
  controller; the screen is a pure `SignInState` -> model connector
  (`sign_in_screen.dart:135-207`). The Global and personal-server paths share
  the same code, so they cannot drift the way two screens would.
- **A server from a code or link is approved before anything is sent**
  (`sign_in_controller.dart:247-262`), refused when cleartext/look-alike/userinfo
  (`ServerPolicy.check`), and the approval is forgotten on Back
  (`:275-282`). A Global-named code needs no approval (`:265-268`).
- **Nothing is texted before the person confirms the number**
  (`:399-412`, the dialog at `sign_in_screen.dart:48-91`), and the pre-check
  that chooses the page grants nothing (server: `sign_up.dart:44-53`).
- **Credential hygiene.** The password never leaves the device (engine
  derives the auth key); it is dropped from state on success
  (`sign_in_controller.dart:523-525`); the single-use verification token is
  held only between `submitOtp` and `register` (`:455-459`, `:475-476`);
  `remember` is read before the flow reset that a successful sign-in triggers
  (`:506`, `:565`); the saved-account list holds the number, server and name,
  never a password (`saved_accounts.dart:1-42`).
- **No exception text reaches a person.** `SignInCopy` translates every engine
  and API failure into a fixed sentence; the copy layer is the only text a
  sign-in page shows (`sign_in_copy.dart:1-197`).
- **Link handling is guarded.** A parked invite/recovery code is used only
  when the device is *known* signed out (`_knownSignedOut`, `:103-133`), and
  every link still walks the approval page.
- **A number already signed in here is opened, not signed in twice**
  (`:365-372`); the server is forced to Helix Global for a non-advanced
  sign-in (`_chooseServer`, `:620-626`), so a personal server approved and then
  backed out of never receives the Global page's typing.

## Findings

### AUD-15-1 A national number typed with its trunk zero becomes a different E.164

**Severity:** P3
**Confidence:** confirmed
**Where:** [sign_in_state.dart:139-145](file:///J:/Projects/helix/helix_remote/app/lib/features/sign_in/application/sign_in_state.dart#L139-L145) (`e164` concatenates `countryCode` + digits), [sign_in_controller.dart:357-364](file:///J:/Projects/helix/helix_remote/app/lib/features/sign_in/application/sign_in_controller.dart#L357-L364) (`submitPhone` checks only length), [signin_screen.dart:529-542](file:///J:/Projects/helix/helix_remote/packages/orbit_ui/lib/src/screens/signin/signin_screen.dart#L529-L542) (hint `1711 000001`, prefix `+880`)
**What:** The field after the `+880` prefix takes the national number verbatim.
A number typed the way every phone in the default country displays it -
`01711 000001`, eleven digits - is sent as `+88001711000001`. The server's
`requireE164` accepts it (`secrets.dart:28-42`: `^\+[1-9][0-9]{7,14}$`), so no
layer refuses or corrects it. The app already owns the normaliser for exactly
this convention - `PhoneNumbers.normalize` strips the trunk zero against a
default calling code ([phone_numbers.dart:44-70](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/phone_numbers.dart#L44-L70)) -
but sign-in does not call it.
**Trigger:** A person in Bangladesh (the default, and the only country the
launch audience needs) types their number with the leading `0`, or Android
autofill (`AutofillHints.telephoneNumberNational`) fills it that way.
**Evidence:** `+880` + `01711000001` passes the `minDigits: 10` check
(`sign_in_countries.dart:12`, `:24-25`) and matches the server's E.164 regex. The
account-status pre-check (`:373`) then describes a number nobody owns:
"no account", so the flow offers to create one and texts a stranger's handset;
or, if the mistyped number happens to be registered, the password page is shown
for *that* account and each wrong guess spends that account's lockout budget
(`server/.../sign_in.dart:41-57`).
**Impact:** The person cannot sign in and is told nothing useful ("Could not
reach the server" / "That code is not right"); in the unlucky case a code is
texted to a stranger and a stranger's account is locked by repeated attempts.
No data loss, no takeover (the code goes to the other handset).
**Fix sketch:** App only. In `submitPhone`/`useCodeInstead` (or once, in the
`e164` getter) pass the national digits through
`PhoneNumbers.normalize(digits, defaultCallingCode: countryCode.substring(1))`
and refuse with `badPhoneNumber` when it returns null; keep `phoneLabel` as
typed. Optionally show the resulting E.164 under the field. No wire, schema or
server change. Also make the hint country-specific (it is Bangladesh's format
for all nine countries) or drop the digits from it.
**Test that proves it:** A controller test: `updateDigits('01711000001')` then
`submitPhone()` with a fake `accountStatus` recording the number; assert the
recorded number is `+8801711000001`. Today it records `+88001711000001`.
**Overlap:** None. Sweep 14 (app `core/`) owns `phone_numbers.dart` itself;
this finding is that sign-in bypasses it.

### AUD-15-2 The lockout time is read in seconds, but the wire carries milliseconds

**Severity:** P3
**Confidence:** confirmed
**Where:** [sign_in_copy.dart:117-124](file:///J:/Projects/helix/helix_remote/app/lib/features/sign_in/application/sign_in_copy.dart#L117-L124) (`DateTime.fromMillisecondsSinceEpoch(seconds * 1000)`), against [transport/errors.dart:120-129](file:///J:/Projects/helix/helix_remote/packages/helix_remote_api/lib/src/v2/transport/errors.dart#L120-L129) (`lockedUntil`, already parsed), [json.dart:242](file:///J:/Projects/helix/helix_remote/packages/helix_remote_protocol/lib/src/json.dart#L242) (`toWireTime` = epoch **ms**), [server/.../identity/application/context.dart:326-329](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/application/context.dart#L326-L329) (the sender)
**What:** The server sends `details.locked_until` as epoch milliseconds
(`toWireTime`). `SignInCopy.passwordRejected` reads the raw map, treats the
number as epoch seconds and multiplies by 1000, so the sentence says a time
~55,000 years from now. The API's `ApiException.lockedUntil` getter parses the
same field correctly, and `core/engine/failure_copy.dart:71-80` uses it; only
sign-in takes the raw value.
**Trigger:** Three wrong passwords on a number that has a password (the lockout
is 15 minutes; `server/.../sign_in.dart:41-45`).
**Evidence:** `locked_until` in the JSON body is
`1.7…e12`; `fromMillisecondsSinceEpoch(1.7e15)` yields a DateTime in year
58,000 whose `.hour`/`.minute` are arbitrary, so the person reads "Try again
after 03:47" with no relation to the real unlock.
**Impact:** Wrong sentence at the moment a person is already stuck; no
security effect (the server enforces the lockout regardless).
**Fix sketch:** App only: use `error.lockedUntil` (and fall back to the plain
`passwordLocked` sentence when null), or divide by 1000 once. Do not add a
second parser.
**Test that proves it:** A unit test on `SignInCopy.passwordRejected` with
`details: {'locked_until': someUtc.millisecondsSinceEpoch}`; assert the
sentence names `someUtc`'s hour and minute. The settings suite already has this
assertion for `describeFailure` (`app/test/settings/a3b_rules_test.dart:220-237`,
`settings_pages_test.dart:449-468`), which is why the two copies now disagree.
**Overlap:** This is the drift inside S15-1 below.

### AUD-15-3 A third copy of the legal version, which is never sent

**Severity:** P3
**Confidence:** confirmed
**Where:** [sign_in_state.dart:51](file:///J:/Projects/helix/helix_remote/app/lib/features/sign_in/application/sign_in_state.dart#L51) (`static const termsVersion = '2026-09-25'`, no reader), [sign_in_screen.dart:192-197](file:///J:/Projects/helix/helix_remote/app/lib/features/sign_in/presentation/sign_in_screen.dart#L192-L197) ("`termsVersion` is sent at registration"), [account_service.dart:112](file:///J:/Projects/helix/helix_remote/packages/helix_remote_engine/lib/src/account/account_service.dart#L112) (what is actually sent)
**What:** The version is sent by the engine from the **protocol** package's
`HelixLegalDocuments.termsVersion`; the screen shows the **domain** package's
copy (`sign_in_screen.dart:7`, `:197`); and `SignInState.termsVersion` is a
third copy that nothing reads. The comment beside the screen's legal documents
claims the state's constant is what registration sends, which is false.
**Trigger:** Any future edit that changes one copy and believes it changed
what is agreed to or installed.
**Evidence:** `grep termsVersion app/lib/features/sign_in` returns only the
constant and the screen's comment; the engine sends its own constant. The two
live copies (`helix_remote_domain/lib/domain/legal_documents.dart:7` and
`helix_remote_protocol/lib/src/legal.dart:9`) are byte-identical today, and the
protocol copy's header says it is a deliberate copy "removed at cutover".
**Impact:** Consent drift: a person could be shown version A and the server
recorded as accepting version B (the server refuses only when its configured
version differs, `server/.../registration.dart:31-33`). Latent today, silent
when it happens.
**Fix sketch:** App + domain: delete `SignInState.termsVersion`; have the screen
display the same constant the engine sends (import the protocol constant, or
have the domain copy be the only one the app reads). No wire or schema change.
**Test that proves it:** A test that asserts the version the screen shows equals
`HelixLegalDocuments.termsVersion` used by `AccountService.register` - e.g.
make `signInModel` carry the version and compare it to the protocol constant.
**Overlap:** S15-1 (two copies of the same sentences); sweep 14 owns the domain
package boundary.

### AUD-15-4 "This number already has an account" is unreachable in the code path it is written for

**Severity:** P3
**Confidence:** confirmed
**Where:** [sign_in_controller.dart:428-433](file:///J:/Projects/helix/helix_remote/app/lib/features/sign_in/application/sign_in_controller.dart#L428-L433) (`_isAccountExists` branch in `useCodeInstead`), [sign_in_copy.dart:60-62](file:///J:/Projects/helix/helix_remote/app/lib/features/sign_in/application/sign_in_copy.dart#L60-L62) (`phoneAlreadyRegistered`), [server/.../application/sign_up.dart:55-131](file:///J:/Projects/helix/helix_remote/server/lib/src/modules/identity/application/sign_up.dart#L55-L131) (`requestPhoneChallenge` never throws it)
**What:** `useCodeInstead` catches `ErrorCode.accountExists` and shows "Ask
your server admin for a recovery code". The only server route that raises
`accountExists` is `register` (`registration.dart:62-64`); `requestPhoneChallenge`
never does - it texts a code to an existing number on purpose (that is the
password-reset path). So the branch cannot fire, and its sentence (aimed at a
personal server) would be wrong if it did, because this is the Helix Global
flow's own "I forgot my password".
**Trigger:** None reachable; the cost is that the code reads as evidence for a
server rule that does not exist.
**Evidence:** `grep -rn 'ErrorCode.accountExists' server/lib` returns only
`registration.dart:63`; the whole of `requestPhoneChallenge` (checks: SMS
configured, country allowed, banned, resend interval, per-number limit, daily
budget) has no account lookup.
**Impact:** Dead branch and misleading copy in the most security-sensitive
flow; a future change that "restores" it would refuse the reset path.
**Fix sketch:** App only: drop the branch (and the copy if unused), or replace
it with the reason the server can actually give (`smsUnavailable`,
`rateLimited` - both already handled).
**Test that proves it:** None needed after deletion; today a test asserting the
branch is unreachable would only pin the absence of a server rule.
**Overlap:** None.

### AUD-15-5 The post-sign-in doc says a take-over asks for the restore step; the code does not, and cannot usefully

**Severity:** P3
**Confidence:** confirmed
**Where:** [post_sign_in.dart:5-7](file:///J:/Projects/helix/helix_remote/app/lib/core/engine/post_sign_in.dart#L5-L7) ("password sign-in, linking, taking a number over"), against [sign_in_controller.dart:545-604](file:///J:/Projects/helix/helix_remote/app/lib/features/sign_in/application/sign_in_controller.dart#L545-L604) (`completeSetup` never calls `offerRestore`) and the only two callers, [sign_in_controller.dart:512](file:///J:/Projects/helix/helix_remote/app/lib/features/sign_in/application/sign_in_controller.dart#L512) and [devices_providers.dart:570](file:///J:/Projects/helix/helix_remote/app/lib/features/devices/application/devices_providers.dart#L570)
**What:** The doc names three paths; only two set the step. Take-over
(`register(replaceExisting: true)`) skips it. That is defensible - the server
replaces the identity key and revokes every device (`registration.dart:59-70`,
`:126-138`), so a backup sealed under the old identity can no longer be opened
(`backup_gateway.dart:227-241` rejects a mismatched archive) - but the comment
says otherwise, and the two facts together are the whole reason the missing
call is right.
**Trigger:** A maintainer reconciling the comment with the code adds
`offerRestore()` to `completeSetup`; the restore step then shows a backup that
can only fail with "This backup cannot be opened with your account".
**Evidence:** `grep offerRestore app/lib` finds two call sites, neither in the
name page. `_replaceIdentity` deletes the password, the recovery codes and the
key wrapping; `restoreRecoveryBackup` throws `accountMismatch` when the archive
carries secrets for a different identity.
**Impact:** Documentation that invites a wrong fix in a data-loss-adjacent
flow.
**Fix sketch:** Comment only: say that a take-over does not offer the step
because the identity it would restore under is gone, and name the condition
under which that changes.
**Test that proves it:** A test that a take-over completes with
`postSignInProvider == none` (today) and a comment linking the two facts.
**Overlap:** `backup`'s FEATURE.md wiring paragraph (sweep 15b, AUD-15-7) says
"password sign-in (and linking)", which is already accurate.

## Structural proposals

### S15-1 One failure-copy layer, not two

**Current shape:** `core/engine/failure_copy.dart` translates engine/API errors
for settings, devices, groups and profile; `features/sign_in/application/sign_in_copy.dart`
translates the same errors again for sign-in. They have already drifted on
`locked_until` (AUD-15-2) and on `invalidCredentials` wording.
**Hazard:** every new error code, or every change to an existing one's
`details`, has to be applied twice, and nothing tests that the two agree. The
drift found here is the third time this class of bug would appear (settings has
the test, sign-in does not).
**Proposed shape:** `SignInCopy` keeps only the sentences that are specific to
sign-in steps (empty code, truncated code, insecure server, invite/recovery
reasons) and delegates everything else to `describeFailure`. The sign-in page
shows `Failure.message`.
**Migration path:** expand - add delegation and keep the current strings where
they differ; migrate - move each branch, one test at a time, to assert the
delegated sentence; contract - delete the duplicated branches.
**Risk:** low; the sentences the person sees change only where they were
wrong.
**Rough size:** one file, ~80 lines removed; two test files touched.

### S15-2 Sign-in numbers are assembled by string concatenation while a normaliser exists

**Current shape:** three places split a number by country code
(`SignInState.e164`, `SignInController.pickSavedAccount`,
`sign_in_view._countryCodeOf`) against a hand-written nine-country table, and
none consults `core/platform/phone_numbers.dart`, which already knows calling
codes and the trunk-zero rule.
**Hazard:** AUD-15-1; plus a saved account from a country outside the table is
masked with `+880`. Adding a country means editing the table, the hint string
and the masking in three places.
**Proposed shape:** one `SignInNumbers` helper in the sign-in application
layer that wraps `PhoneNumbers` (`normalize` for input, `callingCodeOf` for
display) and the country table becomes the single source for code, name,
minimum length and hint.
**Migration path:** expand - add the helper and route `e164` through it;
migrate - switch `pickSavedAccount`/`_countryCodeOf` to `callingCodeOf`; contract
- delete the longest-prefix loops.
**Risk:** low; the picker's list stays as it is.
**Rough size:** ~60 lines across three files, plus tests.

### S15-3 Page-scoped controllers for operations that outlive their page

**Current shape:** `restoreFlowProvider` and `recoveryBackupProvider` are
`autoDispose`; the engine work they start (a restore, a backup creation) is
app-scoped and keeps running after the page is popped, while the controller is
disposed (`backup_providers.dart:240-282`, `:518-621`).
**Hazard:** AUD-15-6 (writes to a disposed notifier throw
`UnmountedRefException`), and the reverse: a restore that finished while the
person was on another page has no state to return to.
**Proposed shape:** make the two flow providers app-scoped (like
`backupRunProvider`, which already survives navigation) and reset them when the
page is entered with a fresh intent; only the *secret generator* stays
page-scoped.
**Migration path:** expand - drop `autoDispose`, add an explicit `reset()` call
on page entry; migrate - replace the `_disposed` flags with `ref.mounted`
guards where the flow genuinely ends; contract - one pattern for
"operation outlives page" in the feature.
**Risk:** low; the secret must still be dropped when the recovery page closes
(pinned by `backup_pages_test.dart:678-700`).
**Rough size:** ~50 lines in one file.

## Coverage gaps

- No test types a trunk-zero number (AUD-15-1); the one E.164 test uses
  `170 000-0000` (`sign_in_flow_test.dart:246-253`).
- No test asserts the lockout sentence (AUD-15-2); the settings suite does.
- The take-over path has a test for the Terms box (`:436-454`) but none for
  the post-sign-in step (AUD-15-5).
- `pickSavedAccount` is untested for a number outside the nine-country table.
- Sweep 15 covers 2 of `lib/features/`'s 11 features; still to read: chats
  (420), conversation (5,054), groups (3,287), settings (3,775), devices
  (1,488), people (1,669), calls (2,604), profile (482), home (85).
