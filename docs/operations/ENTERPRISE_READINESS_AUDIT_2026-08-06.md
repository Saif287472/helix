# Helix — Enterprise Readiness Audit & Execution Roadmap

**Date:** 2026-08-06
**Scope:** Full monorepo — `helix_local/`, `helix_remote/` (app, admin, backend, 20 packages), `docs/`, CI.
**Baseline:** branch `claude/new-session-15dyd6` @ `8dabdc2`.
**Method:** static read-through of all configuration, plus targeted reading of security-critical,
architectural, and UI paths.

> **Toolchain caveat — read this first.** No Dart or Flutter SDK is installed in the audit
> container (`dart`/`flutter` both `command not found`). **No analyzer run, no test run, no build,
> no coverage measurement was performed.** Every finding below is derived from reading source at a
> cited line. Findings are tagged **[CONFIRMED]** (verified by reading the code at the cited
> location) or **[POTENTIAL]** (consistent with the code but requiring a runtime check to prove).
> Nothing here is inferred from a test failure, because no test was executed.

---

## 1. Executive Summary

Helix is **two separate products in one monorepo**: `helix_local` (peer-to-peer LAN messenger,
no server) and `helix_remote` (server-backed E2EE messenger + Dart backend + Flutter admin
console). Together: ~154,000 lines of Dart, 586 Dart files, ~1,330 test cases, and an unusually
mature documentation estate (16 ADRs, threat model, key lifecycle, privacy claim matrix,
governance and release docs).

**This is not a low-quality codebase.** The cryptographic core is serious work — X3DH, double
ratchet, per-group epoch keys, SQLCipher-backed local storage, Ed25519-signed registration
transcripts, deliberate `relayOnly` ICE policy to prevent IP disclosure between peers. The
backend is a cleanly layered modular monolith. Inline comments are exceptional: they explain
*why*, and repeatedly document bugs that were found and fixed. Lint configuration is strict
(`strict-casts`, `strict-raw-types`, `avoid_dynamic_calls`, `always_use_package_imports`) with
only 12 suppressions in the entire repository.

The problems are concentrated in three specific places, and they are serious:

1. **Authorization has a claimable-identity hole.** The server's admin gate is
   `adminAccountIds.contains(accountId)` where the set is `{'admin'}`, and `account_id` is chosen
   by the client at registration with no reserved-name check. On the public Helix Global instance
   (auto-issued invites), the first user to register as `account_id: "admin"` obtains the full
   operator console. See **CRIT-1**.
2. **The flagship Flutter client is the least-engineered artifact in the repo.** `helix_remote/app`
   has no state management, no router, no design system, no localization, no responsive layout,
   and essentially no accessibility semantics — while `helix_local/app`, the *secondary* product,
   has all five. See **§17, §19**.
3. **Governance documents assert controls that do not exist in code.** `LOG_REDACTION.md` requires
   redaction of tokens and payloads; the remote client's `AppLogger` performs none.
   `WORKSPACE_LOCKFILE_POLICY.md` states `pubspec.lock` is committed; it is not tracked at all.
   The dependency risk register describes `file_picker` as "not directly declared by Helix"; it is
   directly declared in both apps. See **CRIT-2, HIGH-4, MED-9**.

Half the codebase — all of `helix_local` — **has no CI coverage whatsoever**. The workflow says so
explicitly.

**Verdict: not production-ready for a large user base today.** Roughly 3–4 weeks of focused work
closes the security and correctness gaps (Phases 1–2). Reaching a genuinely enterprise-grade bar
across UI, accessibility, observability, and scale is a 5–6 month programme.

---

## 2. Overall Health Score: **63 / 100**

| Dimension | Score | One-line justification |
|---|---:|---|
| **3. Architecture** | 68 | Backend and packages are exemplary; the flagship client has no state or navigation architecture. |
| **4. Security** | 62 | Strong cryptographic core undermined by one critical authz hole and several missing platform hardening controls. |
| **5. Performance** | 70 | Real work done (pagination, isolates, WS backpressure); one O(n²) hot path and no perceived-performance strategy. |
| **6. UI** | 48 | Three unrelated theme systems; 194 hardcoded colours; no skeletons, no responsive layout in the main app. |
| **7. UX** | 58 | Coherent flows and good error copy, but text-scale capped, spinner-only loading, no deep links. |
| **8. Maintainability** | 72 | Outstanding docs and comments; 25 production files exceed 700 lines and two stacks diverge. |
| **9. Scalability** | 55 | SQLite single-writer, in-memory rate limiter, no key-rotation window, no horizontal story. |
| **10. Testing** | 60 | ~1,330 tests and strong backend coverage, but zero integration tests and half the repo untested in CI. |

Weighting: Security ×2, Architecture ×1.5, Testing ×1.5, all others ×1.

---

## 11. Major Findings

| ID | Finding | Severity | Confidence |
|---|---|---|---|
| **CRIT-1** | Reserved admin account ID `"admin"` is claimable by any registering user → full operator console takeover | Critical | CONFIRMED |
| **CRIT-2** | Refresh tokens are accepted as access tokens on every REST route and the WebSocket | High→Critical | CONFIRMED |
| **HIGH-1** | Client diagnostic log is unredacted, persistent, and user-shared — contradicts `LOG_REDACTION.md` | High | CONFIRMED |
| **HIGH-2** | No `FLAG_SECURE` anywhere: message content is screenshot-, recorder-, and recents-visible | High | CONFIRMED |
| **HIGH-3** | `android:allowBackup` left at default `true` — E2EE database extractable via ADB/cloud backup | High | CONFIRMED |
| **HIGH-4** | `pubspec.lock` is not committed despite policy — builds are not reproducible | High | CONFIRMED |
| **HIGH-5** | HTTP 403 is overloaded for both "expired token" and "not permitted", causing spurious refresh-token rotation on every authorization denial | High | CONFIRMED |
| **HIGH-6** | `helix_local` (≈47% of the codebase) is excluded from CI | High | CONFIRMED |
| **MED-1** | Full loaded-window re-fetch + re-decrypt on every inbound message (O(n²) under burst) | Medium | CONFIRMED |
| **MED-2** | `helix_remote/app` has no design system, router, state management, l10n, or responsive layout | Medium | CONFIRMED |
| **MED-3** | Non-constant-time comparison of JWT signature and admin bearer token | Medium | CONFIRMED |
| **MED-4** | No crash reporting or analytics in any app | Medium | CONFIRMED |
| **MED-5** | Accessibility: 1 `Semantics` widget in 30k LOC; text scale hard-capped at 1.3× | Medium | CONFIRMED |
| **MED-6** | In-memory rate limiter — resets on restart, not shared across processes | Medium | CONFIRMED |
| **MED-7** | Pre-release (`file_picker 12.0.0-beta.5`) and EOL (`sqlite3_flutter_libs 0.6.0+eol`) dependencies in production | Medium | CONFIRMED |
| **MED-8** | Cross-product dependency drift (`flutter_local_notifications` 18 vs 22, `connectivity_plus` 6 vs 7) | Medium | CONFIRMED |
| **MED-9** | Dependency risk register is factually wrong about `file_picker` | Medium | CONFIRMED |
| **MED-10** | `remote_release_gate.ps1` is unrunnable — statement precedes `param()` | Medium | CONFIRMED |
| **MED-11** | ~145 silently swallowed exceptions across the repo | Medium | CONFIRMED |
| **LOW-1** | No release obfuscation / R8 / resource shrinking | Low | CONFIRMED |
| **LOW-2** | Duplicate private helpers (`_bytesToHex` / `_hexBytes`), dead `is_admin` claim | Low | CONFIRMED |
| **LOW-3** | Invite codes travel in URL query strings | Low | CONFIRMED |
| **LOW-4** | Unused Android foreground-service permissions declared | Low | POTENTIAL |
| **LOW-5** | No iOS support in either consumer app | Low | CONFIRMED |

### Verified clean (audited, no issue found)

Worth recording so future audits don't re-tread:

- **SQL injection** — every interpolated fragment (`$table`, `$where` in
  `audit_tokens_repository.dart:60,67`, `operational_repository.dart:157`,
  `accounts_devices_repository.dart:741`) is a compile-time constant; all user values are bound
  parameters.
- **Path traversal** — `object_storage.dart:15-22` rejects `/`, `\`, `..`; the attachments module
  additionally applies `p.basename()` at every filesystem call site.
- **Committed secrets** — none. `.env.example` only; no keystores, no service-account JSON.
- **WebSocket credential handling** — token sent in the `Authorization` header, never the URL;
  log lines emit host and path only (`remote_websocket_client.dart:60-64,120-123`).
- **TLS posture** — `HttpClient` is constructed without a `badCertificateCallback`
  (`remote_rest_client.dart:22-26`), so validation is strict; `RemoteDevelopmentConfig._validate()`
  rejects any plaintext or localhost target under the production profile
  (`remote_config.dart:596-623`).

---

## 12. Critical Issues

### CRIT-1 · Reserved admin account ID is claimable by any user → operator console takeover

**Severity: Critical · Likelihood: High on public instances · [CONFIRMED]**

**Location**
- `helix_remote/backend/lib/src/modules/auth/registration.dart:7` — `accountId` read from request body
- `helix_remote/backend/lib/src/server_impl.dart:81` — `this.adminAccountIds = const {'admin'}`
- `helix_remote/backend/lib/src/modules/operability.dart:268-283` — `_isAdmin()`
- `helix_remote/backend/lib/src/modules/privacy_compliance.dart:94`, `contacts.dart:670` — same set

**Root cause.** The server's only admin authorization primitive is:

```dart
// operability.dart:272
if (accountId == null || !adminAccountIds.contains(accountId)) { ... deny ... }
```

`adminAccountIds` defaults to `const {'admin'}` and `bin/server.dart` never overrides it. The
literal string `'admin'` therefore *is* the admin credential. Separately, `_registerHandler` takes
`account_id` verbatim from the client body with **no format constraint and no reserved-name list**
— I grepped for one; the only occurrences of `'admin'` in the backend are the `adminAccountIds`
default and the synthetic claims at `server_impl.dart:492`.

`_validateRegistrationKeys` (`registration.dart:229-271`) does bind `accountId` into a signed
transcript — but the signature is made with the *registrant's own* key, so it proves the client
committed to the ID, not that the ID is legitimately theirs. An attacker signs `"admin"` as
happily as a UUID.

**Attack.** Register normally, substituting `account_id: "admin"`. Requirements: a valid invite
and a phone number that can receive an OTP. On the Helix Global instance, `globalInstanceMode`
auto-issues invites through the *unauthenticated* route `/accounts/invite/auto-issue`
(`server_impl.dart:464`, `auth/invites.dart:66`), so the only real barrier is receiving one SMS.
The issued JWT then carries `account_id: "admin"`, and `_isAdmin()` returns `true`.

**Impact.** Complete compromise of the operator surface: `/ops/users/<id>/delete`,
`/suspend`, `/block`, `/ops/logs`, `/ops/backup`, `/ops/config`, `/ops/invites`,
`/ops/federation/worldwide`, plus the privacy-compliance and contacts admin paths. It is
first-come-first-served and permanent — once `getAccount('admin')` is non-null, the legitimate
operator can never claim it either.

**Fix (layered — do all three).**
1. **Reserve the namespace.** Reject `account_id` values in a reserved set (`admin`, `system`,
   `root`, `helix`, …) at registration, and constrain the format — the honest client generates a
   random ID (`composition_root/registration.dart:101`), so requiring a UUIDv4 costs nothing.
2. **Stop using a string as a capability.** Replace `adminAccountIds` with an explicit
   `is_admin` column on the accounts table, or better, key admin off the already-existing
   `is_admin: true` claim that `server_impl.dart:494` sets for the admin-token path — that claim
   is currently written and **never read by anything** (see LOW-2).
3. **Add a migration guard** that fails startup if an account row with a reserved ID exists, so an
   already-compromised deployment is caught rather than silently trusted.

**Regression test.** Assert that `POST /accounts/register` with `account_id: "admin"` returns 400,
and that a JWT minted for a self-registered account cannot reach any `/ops/*` route.

---

### CRIT-2 · Refresh tokens are accepted as access tokens

**Severity: High, escalating to Critical in combination with CRIT-1 · [CONFIRMED]**

**Location**
- `helix_remote/backend/lib/src/jwt.dart:34-36` — mints `token_type`
- `helix_remote/backend/lib/src/server_impl.dart:500-527` — REST auth middleware
- `helix_remote/backend/lib/src/websocket.dart:170` — WebSocket upgrade

**Root cause.** `generateToken` correctly stamps `token_type: 'refresh'` on refresh tokens.
`verifyToken` (`jwt.dart:43-86`) validates signature, `iss`, `aud`, `nbf`, `exp` — but
**not `token_type`**. The REST middleware and the WebSocket handler both call `verifyToken` and
then check only `account_id`, `device_id`, device-active and account-suspended state. Neither
rejects a refresh token. Only `_refreshHandler` (`auth/refresh.dart:16-18`) checks
`claims['refresh'] != true`, and it checks it in the *opposite* direction.

**Impact.** The access/refresh split is nullified:
- Effective credential lifetime becomes **7 days instead of 1 hour**
  (`auth/refresh.dart:61-75` sets those durations).
- A stolen refresh token grants immediate full API and realtime access **without ever calling
  `/accounts/refresh`** — so it never triggers the rotation-and-revoke logic, and the
  replay-detection at `auth/refresh.dart:44-50` (which revokes all device sessions on reuse of a
  revoked token) is bypassed entirely. The single strongest detection control in the auth design
  is silently unreachable.

**Fix.** In both middleware paths, reject when `claims['refresh'] == true` or
`claims['token_type'] != 'access'`. Prefer asserting the positive (`== 'access'`) so tokens minted
before `token_type` existed fail closed rather than open.

**Hardening while you are in this file.** `verifyToken` treats `exp` as optional
(`jwt.dart:76-81`) — a token without `exp` never expires. Unreachable today because
`generateToken` always sets it, but make absence a rejection.

---

## 13. High Priority Issues

### HIGH-1 · Unredacted, persistent, user-shared diagnostic log

**[CONFIRMED]** · `helix_remote/app/lib/services/app_logger.dart`

`AppLogger._write` (line 53) performs exactly one transformation — newline flattening — and
appends verbatim to `helix_remote_anomaly_log.txt` in the app documents directory. There is **no
redaction of any kind**. This is measured against the repository's own
`docs/security/LOG_REDACTION.md`, which mandates redaction of "private keys, session keys, proofs,
access tokens, and API keys" and "full peer fingerprints".

What actually reaches that file:

- `main.dart:59` — `AppLogger.instance.error('uncaught', '$error', stack)` for every uncaught
  zone error, plus `main.dart:46` for every `FlutterError`.
- `remote_rest_client.dart:155-165` — `RemoteRestException.message` is set to the **entire raw
  response body**, and `.uri` to the full request URI. When such an exception goes uncaught it
  lands in the log with both.
- `main.dart:1338` — `'OTP request failed: $e'` on the phone-registration path.

This is not hypothetical: `docs/operations/HELIX_REMEDIATION_PLAN.md` quotes a real captured log
line containing a full API URI and server error body. The file is then **exported to arbitrary
apps** via `SharePlus.instance` (`settings_screen.dart:113`), and users are asked to share it for
support.

Notably, `helix_local` *does* have a redaction helper (`app.dart:320`, `_home_tab.dart:1230` —
strips long hex/base64 runs) and the backend has a whole `RedactedLogger` plus IP truncation
(`audit_tokens_repository.dart:108-116`). The flagship client is the one place with nothing.

**Fix.** Introduce a single redaction function applied inside `_write` (not at call sites, which
cannot be enforced): strip bearer tokens, long hex/base64 runs, `phone`/`otp`/`invite_code` query
and JSON values, and truncate response bodies. Add an allowlist-based structured-event path for
new logging. Add a unit test that feeds a synthetic token/phone/body through the logger and
asserts absence.

### HIGH-2 · No screenshot or screen-recording protection

**[CONFIRMED]** · `grep -rn "FLAG_SECURE|setSecure" --include=*.kt --include=*.dart` → **zero hits**

Neither app ever sets `WindowManager.LayoutParams.FLAG_SECURE`. Consequences: message content is
screenshot-able and screen-recordable; the Android recents/task-switcher thumbnail retains the
last-rendered conversation in plaintext; any app holding `MediaProjection` can capture the screen.

This is materially inconsistent with the product's own privacy posture — `privacy_screen.dart:296`
advertises that "Locked chats and strict mode always redact content", and the remote app's
`MainActivity.kt` already manipulates window flags for calls, so the mechanism is in place and
simply not used for secrecy.

**Fix.** Set `FLAG_SECURE` by default on conversation, backup-key, and QR/verification screens;
expose a user toggle if screenshots are a wanted feature elsewhere. On Windows, use
`SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)`.

### HIGH-3 · `android:allowBackup` left at default

**[CONFIRMED]** · both `AndroidManifest.xml` files

Neither manifest sets `android:allowBackup="false"`, `android:fullBackupContent`, or
`android:dataExtractionRules`. The platform default is `true`. On many devices the app's private
directory — which holds the SQLCipher database, the anomaly log, and shared preferences — is
therefore eligible for ADB backup and cloud auto-backup. SQLCipher protects the database contents
against offline reading only insofar as the key stays in Keystore, but the **log file is
plaintext** and is included.

**Fix.** `android:allowBackup="false"` plus explicit `dataExtractionRules` (Android 12+) excluding
the database and log directories, in both apps.

### HIGH-4 · `pubspec.lock` is not committed, contradicting stated policy

**[CONFIRMED]** · `git ls-files | grep -c pubspec.lock` → `0`; `.gitignore` does not mention it

`docs/dependencies/WORKSPACE_LOCKFILE_POLICY.md` opens with: *"Helix … commits `pubspec.lock` as
the reproducible dependency snapshot for both apps, all packages, backend code, and tooling."*
No lockfile is tracked anywhere in the repository.

**Impact.** Every CI run and every developer `pub get` re-resolves ~40 direct dependencies within
their caret ranges. Builds are not reproducible; a malicious or merely broken patch release lands
silently in the next build; and a CI failure cannot be distinguished from an upstream change. For
a security product this is a genuine supply-chain exposure, not a hygiene nit.

**Fix.** Commit `helix_remote/pubspec.lock` and `helix_local/pubspec.lock`. Add a CI step that
runs `pub get --enforce-lockfile` and fails on drift. Move version bumps to a deliberate,
reviewed action.

### HIGH-5 · HTTP 403 overloaded → spurious refresh-token rotation on every permission denial

**[CONFIRMED]** · `server_impl.dart:501-506` and `remote_rest_client.dart:179-180`

The server returns **403** for an invalid or expired token
(`'Forbidden: Invalid or expired token'`) rather than 401. The client compensates:

```dart
// remote_rest_client.dart:179
bool _isAuthFailure(int? statusCode) => statusCode == 401 || statusCode == 403;
```

But the backend also uses `AppError.forbidden` for ordinary authorization denials — 40+ sites,
e.g. `group_calls.dart:182` `'only the host can kick participants'`, `attachments.dart:358`
`'Access denied'`, `contacts.dart:130` `'Contact unavailable'`.

**Consequence.** Every legitimate "you may not do that" triggers `_refreshAuthOnce()`, which
performs a **rotating** refresh (`auth/refresh.dart:53` revokes the used token, then mints a new
pair) and then **retries the forbidden request** with `attempt = 0`
(`remote_rest_client.dart:85-87`), resetting the retry budget. So a single denied action costs a
token rotation, a database write, and up to three re-attempts of an operation that will never
succeed. Under multi-account usage (`account_runtime_registry.dart`) several clients rotate
independently, and any interleaving risks tripping the replay detector at `auth/refresh.dart:44`,
which revokes **all** sessions for the device.

**Fix.** Server: return **401** for authentication failures (missing/invalid/expired token) and
reserve **403** for authorization denials. Client: narrow `_isAuthFailure` to `401` only, and stop
resetting `attempt` after a refresh. These must ship together or in the order server-then-client.

### HIGH-6 · Half the codebase has no CI

**[CONFIRMED]** · `.github/workflows/ci.yml`

Both verification jobs are gated on `needs.changes.outputs.remote`. A `helix_local`-only change
matches no gate and lands in the `no-source-changes` job, which prints:

> `"No Helix Remote source, docs, or CI changes detected (helix_local changes are not yet wired into this workflow)."`

`helix_local` is 118 app files + 99 package files — including `secure_channel.dart` (1,154 lines
of transport cryptography) and `lan_lobby_service.dart` (926 lines). None of it is analyzed,
formatted, or tested on any PR. Its package test coverage is also the thinnest in the repo: 5 test
files for 99 source files.

**Fix.** Add `verify-local` jobs mirroring the remote ones, gated on the existing `local` filter
(which already exists and is simply unused).

---

## 14. Medium Priority Issues

**MED-1 · Full window re-decrypt on every inbound message.**
`conversation_screen.dart:224-229`. `_refreshVisibleMessages()` sets
`visibleLimit = _messages.length` and re-runs `messageHistory(limit: visibleLimit)`, replacing the
whole list. If the user has paged back to 500 messages, **every** arriving message, receipt, or
edit re-reads 500 rows from SQLCipher and re-runs 500 AEAD decryptions, then rebuilds the list.
During a burst this is quadratic. The surrounding comment shows the team already fought a runaway
loop here; this is the remaining cost. **Fix:** apply the delta from `RemoteSyncChange` to the
in-memory list, falling back to a bounded re-read only when the change cannot be applied locally.

**MED-2 · The flagship client has no UI architecture.** Measured across `helix_remote/app/lib`:
0 state-management package (208 raw `setState` calls, 0 `ChangeNotifier`/`InheritedWidget`),
0 named routes and 0 `onGenerateRoute` (18 inline `MaterialPageRoute`s), 0 theme file
(`ThemeData` built inline at `main.dart:244` *and again* at `main.dart:745`, with divergent
config — one declares `highContrastTheme`, the other does not), 3 separate `MaterialApp`s,
0 `LayoutBuilder` and 0 breakpoints despite shipping a Windows desktop build, 0 `.arb` files and
274 hardcoded `Text('…')` strings. `helix_local/app` has a 323-line design system with component
themes, a 136-line named router with a `navigatorKey`, Riverpod (89 providers), full l10n
scaffolding, and 24 breakpoint references. The secondary product is better engineered than the
primary one. See §17 and §22.

**MED-3 · Non-constant-time secret comparison.**
`jwt.dart:52` — `if (signature != expectedSignature) return null;` compares HMAC signatures with
short-circuiting string equality. `server_impl.dart:444` — `token == adminTokenOverride` compares
the **raw** admin bearer token the same way; `:449` does so for its SHA-256 hex. Remote timing
attacks over a network are difficult, but this is a standard finding and the fix is a five-line
constant-time byte comparison.

**MED-4 · No crash reporting and no analytics.** No `sentry`, `firebase_crashlytics`,
`firebase_analytics`, or equivalent in any pubspec. The only telemetry is the local file logger,
retrieved by asking the user to share it. Production crash rate, ANR rate, and adoption are
currently unobservable. For a privacy-first product this may be *deliberate* — but it needs to be
an explicit, documented decision. A self-hosted, opt-in, redacted crash sink satisfies both goals.

**MED-5 · Accessibility is effectively absent in the remote app.** 1 `Semantics` widget and 1
`semanticLabel` across 104 files; 49 `IconButton`s against 43 tooltips. Text scaling is
**hard-capped at 1.3×** (`main.dart:32-40`), and the comment states why: *"Several fixed-size
layout elements … don't grow with text scale, so leaving it unbounded clips or overflows them."*
That is an accessibility regression accepted to paper over non-responsive layout. Android and
WCAG expect usability to ~2×. `helix_local` is better (7 `Semantics`, a `helix_semantics.dart`
component) but still thin; the admin app has zero.

**MED-6 · In-memory rate limiter.** `rate_limiter.dart` — `InMemoryRateLimitStore` holds buckets
in a `Map` with a 5-minute idle-eviction timer. The eviction logic is thoughtful
(`isFullyRefilledAt` projects the lazy refill rather than reading the stale field), but state is
per-process and lost on restart. Restart-to-reset defeats OTP and login throttling, and the design
cannot survive a second backend instance.

**MED-7 · Pre-release and EOL dependencies in production.**
`file_picker: ^12.0.0-beta.5` in **both** apps (`helix_remote/app/pubspec.yaml:34`,
`helix_local/app/pubspec.yaml:98`) and `sqlite3_flutter_libs: ^0.6.0+eol`
(`helix_local/app/pubspec.yaml:87`). A caret range on a pre-release is especially unpredictable.

**MED-8 · Cross-product dependency drift.** Same plugin, different majors:
`flutter_local_notifications` **18** (remote) vs **22** (local) — four majors behind in the
flagship; `connectivity_plus` **6.1.3** vs **7.1.1**; `cryptography_flutter` **2.0.0** vs
**2.3.2**. Also `helix_local/app` declares `cryptography: ^2.7.0` while its own packages require
`^2.9.0` — workspace resolution unifies them, so the app's declared constraint is misleading rather
than broken.

**MED-9 · Dependency risk register is factually wrong.** It states `file_picker` *"is not directly
declared by Helix"*. It is directly declared in both application pubspecs. The register also
predates the current resolution (it lists `12.0.0-beta.7` against a declared `^12.0.0-beta.5`).
A control document that is wrong is worse than none, because reviewers trust it.

**MED-10 · The release gate script cannot run.** `helix_remote/scripts/remote_release_gate.ps1`
places `$ErrorActionPreference = "Stop"` on line 1, **before** the `param(...)` block on line 3.
PowerShell requires `param()` to be the first statement; with an assignment ahead of it the block
is parsed as a command invocation and the script fails. Trivial fix (swap the two), but it means
the documented release gate has not been exercised as written.

**MED-11 · ~145 swallowed exceptions.** Counts of bare `catch (_) {}` / `catch (e) {}`:
`helix_local/packages` 73, `helix_local/app` 27, `helix_remote/packages` 22, `helix_remote/app` 17,
backend 6, admin 0. Some are legitimate (best-effort log cleanup). Many hide real failures — and
they hide them specifically in the un-CI'd half of the repo.

---

## 15. Low Priority Issues

- **LOW-1 · No release hardening.** Neither `build.gradle.kts` sets `isMinifyEnabled` or
  `isShrinkResources`, and no release script passes `--obfuscate --split-debug-info`. The
  `.gitignore` already anticipates symbol files (`app.*.symbols`, `app.*.map.json`), so the
  intent existed. Dart AOT limits the exposure, but Kotlin/Java and resources ship in the clear.
- **LOW-2 · Dead and duplicated code.** `composition_root.dart:122-128` defines `_bytesToHex` and
  `_hexBytes` — byte-identical implementations. `server_impl.dart:494` sets an `is_admin: true`
  claim that no code ever reads (the real gate is the account-ID set — see CRIT-1).
- **LOW-3 · Invite codes in URLs.** `remote_rest_client.dart:294-299` passes `invite_code` as a
  query parameter, so it reaches nginx access logs, and reaches the client's own diagnostic log
  via `RemoteRestException.uri` (HIGH-1). Move to a POST body or a header.
- **LOW-4 · [POTENTIAL] Unused foreground-service permissions.** The remote manifest declares
  `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CAMERA`, and `FOREGROUND_SERVICE_MICROPHONE`, but
  declares no `<service>` element (unlike `helix_local`, which declares `HelixForegroundService`).
  `android_call_runtime_service.dart` only drives window flags through a MethodChannel. Verify
  whether a merged plugin manifest supplies the service; if not, remove the permissions — Play
  Console requires justification for each.
- **LOW-5 · No iOS support.** Neither consumer app has an `ios/` directory (`helix_remote/app`:
  android + windows; `helix_local/app`: android + windows). The admin app has macOS, Linux, and
  web. A "production app for millions" without iOS is a product-scope decision that should be
  recorded, not an oversight to fix silently.

---

## 16. Security Audit

**Threat model in force:** `docs/security/THREAT_MODEL.md` and `TRUST_MODEL.md` exist and are
substantive. This audit tests the code against them.

| Area | Assessment |
|---|---|
| **Cryptographic core** | **Strong.** X3DH, double ratchet, per-group epoch keys, attachment crypto, backup crypto, transfer handshake — all as separate, tested packages (`helix_remote_crypto`, 224 package tests). Registration binds account and device keys into a signed transcript over Ed25519 (`registration.dart:229-271`). Device signing and agreement keys are required to be distinct (`:246`). Public keys are length-checked at 32 bytes (`:274-281`). |
| **Authentication** | **Weak at the boundary.** JWT HS256 is fine for a monolith, but `token_type` is unvalidated (CRIT-2), `exp` is optional, and signature comparison is not constant-time (MED-3). Key rotation is impossible without a flag day: `verifyToken` requires `headerMap['kid'] == keyId` (`jwt.dart:59`) with a single fixed `kid`, so changing the secret invalidates every live token instantly, with no overlap window. |
| **Authorization** | **Critically flawed** (CRIT-1). Mitigating credit: every one of the 16 privileged handlers in `operability.dart` *does* call `_isAdmin` — the gate is consistently applied; it is the identity behind it that is forgeable. |
| **Session management** | Rotation-on-use with replay detection and blast-radius revocation (`auth/refresh.dart:44-50`) is a genuinely good design — currently bypassable via CRIT-2 and needlessly triggered via HIGH-5. |
| **Transport** | HTTPS/WSS enforced by config validation; production profile rejects plaintext and localhost (`remote_config.dart:596-623`); physical-Android profile explicitly refuses LAN HTTP (`:242-248`). **No certificate pinning** — defensible, since users may point the app at arbitrary self-hosted servers, but the known-host Helix Global endpoint could be pinned with a fallback. |
| **Storage** | SQLCipher via `hooks.user_defines.sqlite3.source: sqlcipher`; keys in `flutter_secure_storage` (Keystore/DPAPI) under a product-scoped prefix (`composition_root.dart:48-64`); a defined reset key list (`:102-120`). Undermined by `allowBackup` (HIGH-3) and the plaintext log (HIGH-1). |
| **Input validation** | Good. Path traversal blocked (`object_storage.dart:15-22`); no SQL injection; server URL parsing is careful, with a documented lookbehind regex preventing scheme mangling (`remote_config.dart:490-516`); `phone_last4` regex-validated and silently dropped rather than fatal (`registration.dart:52-56`). |
| **Sensitive data exposure** | The weakest non-authz area: HIGH-1 (logs), HIGH-2 (screen capture), HIGH-3 (backup), LOW-3 (invite in URL). The backend side is much better — audit logs truncate IPs to /24 and reject payloads containing forbidden keys (`audit_tokens_repository.dart:78-116`). |
| **Platform channels** | One channel, `com.helix.remote/calls`, single method, `notImplemented()` otherwise (`MainActivity.kt`). Clean. |
| **Admin surface** | Single static bearer token, no expiry, no rotation, no scoping, no MFA, written in plaintext to `ADMIN_TOKEN.txt` beside the database (`bin/src/admin_token_file.dart`). The file's own text tells the operator to delete it, which is honest but not a control. |
| **Dependencies** | No committed lockfile (HIGH-4); pre-release and EOL packages (MED-7); no vulnerability scanning in CI — `flutter pub outdated` is advisory and non-blocking. |

---

## 17. Architecture Review

**What is genuinely good.** The `helix_remote` backend is a well-executed modular monolith: 130
files, ~21k lines, one module per bounded context (`auth`, `messaging`, `calls`, `groups`,
`attachments`, `backups`, `contacts`, `federation`, `operability`, `privacy_compliance`), each with
its own router and repository. Large modules are split with `part` files along real seams
(`auth/registration.dart`, `auth/refresh.dart`, `calls/signaling.dart`). Dependency direction is
clean: `domain` ← `api`/`crypto`/`storage` ← `sync`/`calls`/`groups` ← `app`. 16 ADRs document the
decisions, including the two-app-shell split (ADR-002) and separate local/remote crypto identities
(ADR-009). `docs/architecture/module_boundaries.json` encodes the boundaries as data.

**The central problem: two products, two unrelated engineering standards.**

| Concern | `helix_local/app` | `helix_remote/app` |
|---|---|---|
| State management | Riverpod, 89 providers, 13 provider files | none — 208 `setState`, 24 manual `StreamSubscription`s |
| Navigation | `AppRouter.generateRoute` + `AppRoutes` constants + `navigatorKey` | 18 inline `MaterialPageRoute`, 0 named routes |
| Theming | `app_theme.dart`, 323 lines, component themes | inline `ThemeData` in `main.dart`, twice, divergent |
| Localization | `l10n.yaml` + `.arb` + generated delegates | none; 274 hardcoded strings |
| Responsive | 24 breakpoint refs, `LayoutBuilder` | 0 breakpoints, 0 `LayoutBuilder` (ships on Windows) |
| CI | **none** | analyze + format + test on 2 OSes |

Each product is internally coherent; together they are two codebases sharing a monorepo and a
brand. The cost is real: no shared widget library, no shared theme tokens, no transferable
reviewer knowledge, and duplicated `AppLogger` implementations that have already diverged in
security-relevant ways (one redacts, one does not).

**Secondary architectural findings.**
- **`part`-file god objects.** `RemoteCompositionRoot` is 2,239 lines across 9 `part` files;
  `RemoteMessagingService` is 3,591 lines across 9. `part` improves file size but not coupling —
  every part shares one private namespace and one class's state, so nothing is independently
  testable or replaceable. These are the two natural extraction targets.
- **UI holds business logic.** With no view-model layer, screens own service calls, decryption
  orchestration, pagination state, and error mapping directly — `conversation_list_screen.dart`
  (1,570 lines), `calls_tab_screen.dart` (1,623), `contact_info_screen.dart` (1,377). This is why
  MED-1 lives in a widget's `State`.
- **`main.dart` at 1,588 lines** carries bootstrap, three `MaterialApp`s, theme definitions,
  connectivity handling, and the registration UI.
- **SOLID.** Dependency inversion is respected at package boundaries (`KeyValueStore`,
  `ObjectStorageAdapter`, `RateLimitStore`, `HelixRemoteRestClient` are all abstract). It is
  absent in the UI layer, which depends on concrete services directly.

---

## 18. Performance Review

**Done well.** Message pagination with a 50-item page and offset-based `loadMore`
(`conversation_screen.dart:126,231-250`); `ListView.builder`/`.separated` for all 13 unbounded
lists; isolate offloading (`helix_isolate_compute.dart`, with `phase10_isolate_compute_test.dart`);
chunked, yielding deletes so a large mailbox purge cannot hold SQLite's single writer lock
(`accounts_devices_repository.dart:733-751`); WebSocket replay backpressure — the client acks each
page before the server sends the next (`remote_websocket_client.dart:166-172`); protocol-level ping
at 20s to survive proxy idle timeouts (`:86`); lazy token-bucket refill with idle eviction.

**Issues.**

| # | Issue | Location | Impact |
|---|---|---|---|
| P-1 | Full window re-fetch + re-decrypt per change (MED-1) | `conversation_screen.dart:224-229` | Quadratic under message bursts; main-thread jank and battery drain in the app's hottest screen |
| P-2 | 8 non-lazy `ListView(` with `children:` | `calls_tab_screen.dart:351,686,951`, `settings_screen.dart:726`, `contact_info_screen.dart:615`, `device_management_screen.dart:188`, `profile_screen.dart:94`, `message_actions.dart:357` | Builds every child eagerly. Settings/profile are bounded and fine; the calls-tab and device-management lists grow with user data |
| P-3 | Log purge reads the entire file into memory | `app_logger.dart:101-124` — `readAsLines()` on up to 5,000 lines, at every app start | Startup cost and a memory spike on the critical boot path |
| P-4 | Every log write awaits a serialized file append | `app_logger.dart:87-99` | Chained `Future` per entry; a burst of logging serializes behind disk I/O |
| P-5 | Contacts-area change rebuilds the whole conversation screen | `conversation_screen.dart:167-171` — `setState(() {})` on *any* contact change | Unnecessary full-subtree rebuild |
| P-6 | No `const` discipline audit possible | — | `prefer_const_constructors` is not in the lint set; with 194 hardcoded colours and inline styling, const-promotion is likely being missed widely |
| P-7 | No perceived-performance strategy | repo-wide | 0 skeleton/shimmer loaders; 62 raw `CircularProgressIndicator`s across the three apps |

**Not measurable here.** `docs/performance/PERFORMANCE_BUDGETS.md` and `BENCHMARK_DATASETS.md`
define budgets, but no CI job enforces them and no profiling artifacts are committed. Startup
time, frame timings, and memory are unverified.

---

## 19. UI / UX Review

### UI

The remote app reads as functional-but-unfinished next to its own sibling:

- **No design system.** 194 hardcoded colour references, concentrated in
  `message_tile.dart` (31), `conversation_screen.dart` (24), `call_screen.dart` (22),
  `conversation_list_screen.dart` (20). 134 inline `EdgeInsets` literals with no spacing scale.
  Compare `helix_local/app/lib/ui/app_theme.dart`, which centralises card, elevated/filled/outlined
  button, list-tile, navigation-bar, snackbar, and divider themes.
- **Three unrelated theme systems** across three shipped apps (remote inline, local 323-line,
  admin 119-line) — no shared tokens, so the products cannot look like one family.
- **Two divergent `ThemeData` definitions inside one file** (`main.dart:244` and `:745`); only the
  second declares `highContrastTheme`/`highContrastDarkTheme`, so high-contrast support depends on
  which shell you enter through.
- **Motion is essentially absent.** 4 `Animated*` widgets, 0 `Hero`, 0 custom page transitions in
  30k LOC. Local app: 10, 2, and 2 respectively.
- **No skeleton loaders anywhere** in any app.
- **Not responsive.** 0 `LayoutBuilder`, 0 breakpoints, despite a shipped Windows target. Phone
  layouts are stretched across desktop widths. `phase16_responsive_test.dart` does not test this —
  its assertions are `find.text('Create Backup')` and `find.byType(SingleChildScrollView)`, which
  pass at any window size.

**Credit where due:** `SafeArea` usage is asserted by test, empty states exist (11 in the remote
app), error copy is centralised and tested (`remote_error_copy.dart` +
`remote_error_copy_test.dart`), and onboarding has purpose-built security badges
(`onboarding_security_badges.dart`, with tests).

### UX

- **Loading is uniformly spinner-based** — 24 indicators in the remote app, 2 `RefreshIndicator`s
  in total. No optimistic skeletons, no progressive disclosure.
- **Feedback is snackbar-heavy** — 49 `ScaffoldMessenger` call sites. Transient toasts are a poor
  fit for failures the user must act on (send failure, key change).
- **Text scaling capped at 1.3×** (MED-5) — a real user-facing limitation with a documented cause.
- **No deep linking.** Two `intent-filter`s, both `MAIN`/`LAUNCHER`. Invite links, call links
  (`call_link_sheet.dart`), and group join links must be copy-pasted manually.
- **Offline behaviour is designed** — `_BootState.offline`, a sync outbox, a redacted outbox status
  banner (`conversation_list_screen.dart:951`), and connectivity subscription (`main.dart:648`).
  This is one of the better-handled UX areas.
- **Keyboard navigation** is untested and unlikely to work well on the Windows build given no
  `Shortcuts`/`Actions`/`FocusTraversal` usage.
- **Screen-reader support is effectively absent** in the remote app (MED-5).

---

## 20. Dependency Audit

Roughly 40 direct third-party dependencies across 27 pubspecs, workspace-resolved per product.

| Package | Status | Action |
|---|---|---|
| `file_picker ^12.0.0-beta.5` | **Pre-release, both apps** | Pin exactly, or move to stable; a caret on a pre-release is unpredictable |
| `sqlite3_flutter_libs ^0.6.0+eol` | **EOL-marked**, `helix_local` | Migrate as the register already requires; the remote side already removed it |
| `flutter_local_notifications` | **18 (remote) vs 22 (local)** | Converge on 22; four majors of fixes are unapplied in the flagship |
| `connectivity_plus` | 6.1.3 vs 7.1.1 | Converge on 7 |
| `cryptography_flutter` | 2.0.0 vs 2.3.2 | Converge on 2.3.2 |
| `cryptography` | app declares ^2.7.0, packages need ^2.9.0 | Correct the app constraint (resolution already unifies; the declaration misleads) |
| `flutter_webrtc ^1.5.1` | Consistent everywhere | Keep; largest native surface, worth a dedicated upgrade test |
| `flutter_secure_storage ^10.3.1`, `mobile_scanner ^7.2.0`, `qr_flutter ^4.1.0`, `share_plus ^13.1.0`, `sqlite3 ^3.3.3` | Consistent | No action |
| `googleapis_auth ^1.6.0` (backend) | Justified in a comment — RSA signing for FCM JWTs is unavailable in `package:crypto`/`package:cryptography` on the VM | Keep |
| `basic_utils`, `pointycastle` (local) | X.509 generation for TLS identity certs | Heavy; review whether still needed |
| `flutter_markdown_plus ^1.0.7` + `markdown ^7.2.2` | Two markdown paths in one app | Consolidate |

**Unused packages:** none detectable by static reading — every declared dependency has at least one
import. Confirm with `dart pub deps` once a toolchain is available.

**Missing:** no lockfile (HIGH-4), no vulnerability scanner, no license audit, no SBOM. For a
security product shipping to a large audience, all four are table stakes.

---

## 21. Technical Debt

| Debt | Size | Interest rate |
|---|---|---|
| Remote client has no UI architecture (state, routing, theme, l10n, responsive) | Large | **High** — every new screen deepens it |
| `helix_local` outside CI | Medium | **High** — silent regressions accumulate now |
| `RemoteCompositionRoot` (2,239 lines) and `RemoteMessagingService` (3,591 lines) | Large | Medium |
| 25 production files over 700 lines | Medium | Medium |
| ~145 swallowed exceptions | Medium | Medium — hides the bugs you will hunt later |
| Two divergent `AppLogger` implementations | Small | **High** — already caused HIGH-1 |
| Governance docs asserting non-existent controls | Small | **High** — erodes trust in every other doc |
| No integration tests | Medium | Medium |
| No iOS platform | Large | Low (until it becomes a product requirement) |
| Duplicate helpers, dead `is_admin` claim | Trivial | Low |

---

## 22. Recommended Refactors

1. **Introduce a view-model layer in `helix_remote/app`.** Adopt Riverpod — the team already runs
   it competently in `helix_local`, so this is convergence, not a new bet. Move service calls,
   pagination, and error mapping out of `State` classes. Do it screen-by-screen, starting with
   `conversation_screen.dart` (which also fixes MED-1).
2. **Extract a shared `helix_ui` package.** Design tokens, theme builders, and common components
   (empty state, error state, skeleton, async panel, confirm dialog) used by all three apps.
   `helix_local/app/lib/ui/components/` is already most of the source material — promote it.
3. **Split `RemoteCompositionRoot`** into `SessionManager`, `RegistrationCoordinator`,
   `RuntimeSupervisor`, and `SecurityGateway`, each independently constructible and testable.
   Replace `part` with real files and injected interfaces.
4. **Split `RemoteMessagingService`** along its existing seams — sending, crypto, history/receipts,
   conversations, contacts/privacy — into collaborating objects behind one facade.
5. **Introduce a router.** `onGenerateRoute` with route constants at minimum; `go_router` if deep
   linking is wanted (it should be — invite and call links need it).
6. **Unify logging.** One `helix_logging` package with mandatory redaction at the write boundary,
   consumed by both apps.
7. **Replace `adminAccountIds` with a real capability** (CRIT-1 fix #2).
8. **Centralise auth-failure semantics** — one `AuthFailure` type mapped from 401 only.

---

## 23. Enterprise Readiness Assessment

| Capability | State | Gap |
|---|---|---|
| Production deployment | ⚠️ Partial | Signing enforced; release gate script is broken (MED-10); no obfuscation |
| Large user base | ❌ Not ready | CRIT-1 must be closed first |
| High traffic | ❌ Not ready | SQLite single-writer, in-memory rate limiter, no horizontal scaling path |
| Maintainability | ✅ Good | Docs, ADRs, and comments are a genuine asset |
| Scalability | ❌ Weak | No sharding, no read replicas, no JWT key-rotation window |
| Team collaboration | ⚠️ Partial | Ownership matrices exist; half the repo has no CI |
| CI/CD | ⚠️ Partial | Good remote pipeline; no local pipeline, no coverage gate, no security scanning, no deploy automation |
| Monitoring | ⚠️ Partial | `/health`, `/ready`, `/metrics` endpoints exist and are admin-gated; nothing scrapes them |
| Observability | ❌ Weak | No distributed tracing; correlation IDs are generated (`remote_rest_client.dart:219`) but not propagated to a backend trace store |
| Crash reporting | ❌ Absent | MED-4 |
| Analytics | ❌ Absent | MED-4 |
| Feature flags | ❌ Absent | Only `globalInstanceMode` and server config rows |
| Environment separation | ✅ Good | Four validated runtime profiles with enforced invariants |
| Configuration management | ✅ Good | `.env.example`, `env_sanitize.dart`, server-config table, `/server/info` publishing limits |
| Disaster recovery | ⚠️ Documented | `DR_DRILL_RUNBOOK.md` and `ROLLBACK_REHEARSAL.md` exist; no evidence of execution |

---

## 24. Phase-by-Phase Implementation Roadmap

Sequenced so that each phase is independently shippable and nothing later invalidates anything
earlier. Complexity is engineering difficulty; risk is the chance of introducing a regression.

---

### Phase 0 — Establish the ground truth
**Objective.** Make the codebase measurable before changing it. Nothing in this audit was verified
by running anything; that must not remain true.

**Tasks**
1. Stand up a toolchain (Flutter stable matching `sdk: ^3.12.0`) and run `verify.sh` end to end;
   record the true analyzer and test baseline.
2. Commit `pubspec.lock` for both workspaces (**HIGH-4**) and add `pub get --enforce-lockfile` to CI.
3. Wire `helix_local` into CI (**HIGH-6**) using the `local` filter that already exists.
4. Add coverage collection with a **non-blocking** initial report; publish the number.
5. Fix `remote_release_gate.ps1` (**MED-10**) and execute it once.

**Files.** `.github/workflows/ci.yml`, `helix_*/pubspec.lock`, `helix_remote/scripts/*`
**Complexity** Low · **Risk** Low · **Dependencies** none
**Success criteria.** Green CI on both products; a published coverage baseline; a release gate that
runs. **Do this first — Phases 1+ need a working test loop.**

---

### Phase 1 — Critical security fixes
**Objective.** Close the two issues that make the current deployment unsafe.

| # | Task | Files | Complexity | Risk |
|---|---|---|---|---|
| 1.1 | Reserve account-ID namespace + enforce UUID format (**CRIT-1** fix 1) | `auth/registration.dart` | Low | Low |
| 1.2 | Replace `adminAccountIds` with a real admin capability (**CRIT-1** fix 2) | `server_impl.dart`, `operability.dart`, `privacy_compliance.dart`, `contacts.dart`, `migrations.dart` | Medium | Medium |
| 1.3 | Startup guard rejecting an existing reserved-ID account (**CRIT-1** fix 3) | `bin/server.dart`, `migrations.dart` | Low | Low |
| 1.4 | Reject refresh tokens at both auth boundaries (**CRIT-2**) | `server_impl.dart:500`, `websocket.dart:170` | Low | **Medium** — mis-implementation locks every client out |
| 1.5 | Require `exp`; constant-time signature compare (**MED-3**) | `jwt.dart:52,76` | Low | Low |
| 1.6 | Constant-time admin-token compare | `server_impl.dart:442-450` | Low | Low |

**Success criteria.** New tests prove: `account_id: "admin"` is rejected; a refresh token returns
401 on `/ops/*`, on a normal REST route, and on WS upgrade; an `exp`-less token is rejected; a
self-registered account cannot reach any admin route.
**Order.** 1.1 → 1.3 → 1.2 → 1.4 → 1.5 → 1.6. Deploy 1.1/1.3 immediately — they are the
cheapest possible stop-gap for CRIT-1 while 1.2 is built.

---

### Phase 2 — Critical bug and data-exposure fixes
**Objective.** Stop leaking user data through channels the threat model already forbids.

| # | Task | Files | Complexity | Risk |
|---|---|---|---|---|
| 2.1 | Redaction at the log write boundary (**HIGH-1**) | `app_logger.dart` (both apps) | Medium | Low |
| 2.2 | Truncate `RemoteRestException.message`; stop logging raw bodies | `remote_rest_client.dart:155-165` | Low | Low |
| 2.3 | `FLAG_SECURE` on sensitive screens (**HIGH-2**) | `MainActivity.kt`, new Dart channel, conversation/backup/QR screens | Medium | Low |
| 2.4 | `allowBackup=false` + `dataExtractionRules` (**HIGH-3**) | both `AndroidManifest.xml` | Low | Low |
| 2.5 | 401/403 split, server and client (**HIGH-5**) | `server_impl.dart:501`, `remote_rest_client.dart:179` | Medium | **Medium** — must ship server-first |
| 2.6 | Move `invite_code` out of the query string (**LOW-3**) | `remote_rest_client.dart:294`, `auth/invites.dart` | Low | Low |
| 2.7 | Triage ~145 silent catches; log-or-rethrow (**MED-11**) | repo-wide | High | Medium |

**Dependencies.** 2.7 depends on Phase 0 CI, or the local half is unverifiable.
**Success criteria.** A test feeding a token, phone number, and error body through `AppLogger`
asserts none survive. Manual check: recents thumbnail is blank. A permission denial performs zero
token rotations.

---

### Phase 3 — Architecture refactoring
**Objective.** Give the flagship client the architecture the secondary product already has.

**Tasks**
1. Adopt Riverpod in `helix_remote/app`; establish the view-model pattern on one screen first.
2. Migrate `conversation_screen.dart` — carries the MED-1 fix (delta-apply instead of full reload).
3. Migrate the remaining large screens: `conversation_list_screen`, `calls_tab_screen`,
   `contact_info_screen`, `settings_screen`, `groups_screen`.
4. Split `RemoteCompositionRoot` (2,239 lines) into four injectable collaborators.
5. Split `RemoteMessagingService` (3,591 lines) along its existing part seams.
6. Introduce `onGenerateRoute` + route constants; extract routing out of `main.dart`.
7. Reduce `main.dart` from 1,588 lines to a bootstrap shell.
8. Remove duplicate helpers and the dead `is_admin` claim (**LOW-2**).

**Files.** `helix_remote/app/lib/**`
**Complexity** High · **Risk** **High** — the largest regression surface in the programme
**Dependencies.** Phases 0–2. **Do not start before coverage exists on these screens.**
**Success criteria.** No production file over 700 lines in `helix_remote/app`; no screen calls a
service directly; coverage on migrated screens does not drop.
**Order.** 1 → 2 → 4 → 5 → 3 → 6 → 7 → 8. Screen migration follows the service split so
view-models bind to stable interfaces.

---

### Phase 4 — Performance optimization
**Objective.** Remove the quadratic path and establish measurement.

**Tasks**
1. Delta-apply message changes (**MED-1 / P-1**) — folded into Phase 3.2 if sequenced together.
2. Convert the growth-bearing non-lazy `ListView`s (**P-2**) — calls tab, device management.
3. Rewrite log purge as a streaming tail; batch appends (**P-3, P-4**).
4. Scope contacts-change rebuilds to the affected contact (**P-5**).
5. Add `prefer_const_constructors` and `prefer_const_literals_to_create_immutables` to the lint set;
   fix the fallout (**P-6**).
6. Wire `PERFORMANCE_BUDGETS.md` to a CI job asserting startup time and frame budgets on a
   reference device.

**Complexity** Medium · **Risk** Low · **Dependencies** Phase 3 for task 1
**Success criteria.** Sustained 60fps in a 1,000-message conversation under a 20-message burst;
p95 cold start within the documented budget; budgets enforced in CI.

---

### Phase 5 — UI modernization
**Objective.** Make three apps look like one product.

**Tasks**
1. Extract `packages/helix_ui`: colour/spacing/typography/radius/elevation tokens, light + dark +
   high-contrast theme builders.
2. Migrate all three apps onto it; delete the inline `ThemeData` in `main.dart` (both copies).
3. Replace 194 hardcoded colours and 134 inline `EdgeInsets` with tokens.
4. Build the shared component set: empty state, error state, **skeleton loaders**, async panel,
   confirm/destructive dialogs, status badges — promoting `helix_local/app/lib/ui/components/`.
5. Replace 62 bare `CircularProgressIndicator`s with skeletons where content shape is known.
6. Establish button hierarchy (filled/tonal/outlined/text) and apply it consistently.
7. Add motion: page transitions, list item animations, `Hero` on avatars.
8. Introduce responsive breakpoints and `LayoutBuilder`; build real tablet and desktop layouts
   (master-detail for conversations).

**Complexity** High · **Risk** Medium · **Dependencies** Phase 3
**Success criteria.** Zero hardcoded colours outside `helix_ui`; a documented component gallery;
screenshot tests at phone/tablet/desktop widths.

---

### Phase 6 — UX improvements
**Objective.** Move from functional to polished.

**Tasks**
1. Deep linking for invite, call, and group-join links (`app_links` / `go_router`) with
   `intent-filter`s and Windows URI registration.
2. Replace transient snackbars with persistent, actionable surfaces for failures needing user action.
3. Real empty states with a primary action on every list.
4. Pull-to-refresh on every refreshable surface (currently 2 in the whole remote app).
5. Search, filter, and sort across conversations, contacts, and calls.
6. Onboarding flow review — reduce steps to first message.
7. Offline: surface outbox state inline per message, not only in a banner.
8. Windows keyboard navigation — `Shortcuts`, `Actions`, focus traversal.

**Complexity** Medium · **Risk** Low · **Dependencies** Phase 5
**Success criteria.** A tapped invite link opens the app to the right screen; every failure path
offers a retry; task-completion walkthrough passes on phone and desktop.

---

### Phase 7 — Accessibility
**Objective.** Reach WCAG 2.2 AA and platform accessibility parity.

**Tasks**
1. **Remove the 1.3× text-scale cap** (`main.dart:32-40`) — depends on Phase 5's responsive
   layouts, which is the whole reason the cap exists.
2. `Semantics` on every interactive and status element (from 1 → full coverage).
3. Tooltips/labels on all 49 `IconButton`s.
4. Verify 4.5:1 contrast across both themes; keep high-contrast themes on both shells.
5. Enforce 48×48dp minimum touch targets.
6. Screen-reader passes: TalkBack (Android), Narrator (Windows).
7. Focus order and visible focus indicators.
8. Add `flutter_test` accessibility guideline assertions
   (`meetsGuideline(textContrastGuideline)`, `androidTapTargetGuideline`) to widget tests.

**Complexity** Medium · **Risk** Low · **Dependencies** Phase 5
**Success criteria.** Automated guideline assertions pass on all screens; usable at 2× text scale;
a documented manual screen-reader pass.

---

### Phase 8 — Testing
**Objective.** Make regressions expensive to ship.

**Tasks**
1. Create `integration_test/` for both apps — currently **zero** exist. Cover: registration,
   send/receive, attachment round-trip, call setup, backup/restore, device linking.
2. Raise `helix_local/packages` coverage (5 test files for 99 sources).
3. Add coverage thresholds to CI — start at the Phase 0 baseline, ratchet upward.
4. Golden tests for the `helix_ui` component gallery.
5. Property/fuzz testing beyond the existing scheduled seed corpus.
6. Load-test the backend; establish the concurrency ceiling before SQLite becomes the bottleneck.
7. Security regression suite: one test per finding in this document.

**Complexity** High · **Risk** Low · **Dependencies** Phases 1–5
**Success criteria.** Integration suite green in CI; coverage ratchet enforced; every
Critical/High finding has a named failing-before/passing-after test.

---

### Phase 9 — Production hardening
**Objective.** Make the system operable at scale.

**Tasks**
1. Opt-in, redacted crash reporting and minimal analytics (**MED-4**) — with an explicit privacy
   decision recorded in an ADR.
2. Persistent, shared rate limiting (**MED-6**) — survives restart, works across processes.
3. JWT key rotation with an overlap window (multiple `kid`s accepted, one used for signing).
4. Scoped, expiring, rotatable admin credentials replacing the static bearer token; MFA on the
   admin console.
5. Database scaling decision: PostgreSQL migration, or a documented and enforced SQLite ceiling.
6. Release obfuscation, R8, resource shrinking, symbol upload (**LOW-1**).
7. Feature-flag infrastructure.
8. Dependency vulnerability scanning + SBOM in CI.
9. Distributed tracing propagating the existing correlation IDs.
10. Certificate pinning for the known Helix Global host, with a documented rotation procedure.
11. Execute the DR drill and rollback rehearsal; record evidence.

**Complexity** High · **Risk** Medium · **Dependencies** Phases 1–8
**Success criteria.** Crash-free-session rate observable; rate limits survive restart; keys
rotatable with zero forced logouts; a load-tested and documented capacity number.

---

### Phase 10 — Final polish
**Objective.** Close the long tail.

**Tasks**
1. Localization for `helix_remote/app` — 274 hardcoded strings; complete `helix_local`'s
   English-only `.arb` with real translations.
2. Resolve the iOS decision (**LOW-5**) — build it or record the exclusion in an ADR.
3. Reconcile every governance document against the code (**MED-9** and the rest of §21) and add a
   CI check that fails when a doc asserts an unimplemented control.
4. Converge dependency versions; retire pre-release and EOL packages (**MED-7, MED-8**).
5. Remove unused Android permissions (**LOW-4**).
6. Final external penetration test and cryptographic review against
   `EXTERNAL_SECURITY_REVIEW_GATE.md`.

**Complexity** Medium · **Risk** Low · **Dependencies** all prior phases

---

## 25. Estimated Timeline

Assumes 2 senior Flutter engineers, 1 backend engineer, 1 designer (Phases 5–7), 1 QA (Phase 8+).

| Phase | Duration | Cumulative |
|---|---|---|
| 0 — Ground truth | 1 week | 1 wk |
| 1 — Critical security | 1–1.5 weeks | 2.5 wks |
| 2 — Bugs & data exposure | 2 weeks | 4.5 wks |
| 3 — Architecture | 4–6 weeks | 10.5 wks |
| 4 — Performance | 2 weeks | 12.5 wks |
| 5 — UI modernization | 4–5 weeks | 17.5 wks |
| 6 — UX | 3 weeks | 20.5 wks |
| 7 — Accessibility | 2 weeks | 22.5 wks |
| 8 — Testing | 3 weeks (overlaps 5–7) | 23 wks |
| 9 — Production hardening | 4 weeks | 27 wks |
| 10 — Final polish | 2 weeks | **29 wks (~7 months)** |

**Critical path to a safe deployment: Phases 0–2 ≈ 4.5 weeks.** Phases 1 and 2 can ship to
production independently of everything after them, and should.

---

## 26. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| CRIT-1 exploited before the fix ships | Medium | **Critical** | Deploy tasks 1.1/1.3 within days — both are small and independent. Audit existing accounts for reserved IDs *now*. |
| CRIT-2 fix locks out all clients | Low | High | Roll out behind a config flag that logs-but-allows first, then enforces once telemetry shows no `token_type`-less traffic. |
| Phase 3 refactor regresses messaging | **High** | High | Do not start before Phase 0 coverage exists. One screen per PR. Keep the old path behind a flag for one release. |
| 401/403 change breaks older clients | Medium | Medium | Server first; keep 403 accepted client-side for two releases before narrowing. |
| Riverpod migration stalls half-done | Medium | Medium | Timebox per screen; a mixed codebase is acceptable if each screen is internally consistent. |
| `helix_local` CI reveals a backlog of failures | **High** | Medium | Expect it. Land CI in report-only mode for one week, fix, then make it blocking. |
| Committing a lockfile surfaces breaking transitive updates | Medium | Medium | Commit the lockfile at the currently-working resolution, then upgrade deliberately. |
| Design system rewrite outruns the roadmap | Medium | Medium | Ship tokens and theme first (immediate consistency win), components incrementally. |
| SQLite becomes the ceiling before Phase 9 | Medium | High | Load-test in Phase 8, not Phase 9 — the answer changes the Phase 9 plan. |
| Two-product divergence widens during the programme | **High** | Medium | Freeze new `helix_local` UI work until `helix_ui` exists; make convergence a review requirement. |

---

## 27. Final Recommendations

**Do this week.**
1. **Audit production for an account with `account_id = "admin"`.** If one exists that you did not
   create, treat it as an active compromise. This is the single most urgent action in this document.
2. Ship CRIT-1 tasks 1.1 and 1.3 — a reserved-name check and a startup guard, both small.
3. Ship CRIT-2 — two lines in two files.
4. Set `allowBackup="false"`. One attribute, two files.

**Do this month.** Phases 0–2 in full. After that the product is *safe* to run, even though it is
not yet *polished*.

**Then choose deliberately.** Phases 3–10 are a genuine 6-month programme. Three framing points:

- **The security core is worth protecting.** The crypto, the relay-only ICE policy, the signed
  registration transcripts, the rotation-with-replay-detection design — this is thoughtful work by
  people who understood the problem. The failures found here are all at the *boundaries* around
  that core, not in it. That is the good kind of security debt: localised and fixable.

- **The documentation estate is an asset that is currently decaying.** Sixteen ADRs, a threat
  model, a privacy claim matrix, performance budgets — and at least three documents that assert
  controls the code does not implement. Docs that describe reality accelerate a team; docs that
  describe intentions mislead auditors and new engineers alike. Add the CI check in Phase 10.3,
  and consider moving it earlier.

- **The two-product split is the root cause of the largest cost item.** Nearly every UI, UX, and
  accessibility finding reduces to "the remote app lacks what the local app has." Phases 5–7 are
  expensive mostly because that work is being done twice, badly, in parallel. `helix_ui` is the
  highest-leverage refactor in this roadmap — it is what makes Phases 5, 6, and 7 tractable
  instead of merely long.

**One thing to reconsider outright.** The 1.3× text-scale cap is a decision to trade an
accessibility guarantee for layout convenience. It is documented honestly in the code, which is to
the team's credit — but it should be treated as a temporary defect with a removal date (Phase 7.1),
not a design choice.

---

*Analysis complete. No code changes have been made. Implementation should begin with Phase 0.*
