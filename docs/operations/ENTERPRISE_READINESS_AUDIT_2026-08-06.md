# Helix Remote — Enterprise Readiness Audit & Execution Roadmap

**Date:** 2026-08-06
**Scope:** `helix_remote/` only — client app, admin console, backend, and the 8 `helix_remote_*`
packages, plus the CI and governance documents that govern them.
**Baseline:** branch `claude/new-session-15dyd6` @ `8dabdc2`.
**Method:** static read-through of all configuration, plus targeted reading of security-critical,
architectural, and UI paths.

---

## Scope statement — what this audit deliberately excludes

**`helix_local` is a separate product and is out of scope.** It is intentionally different from
Helix Remote in user interface, in logic, and in structure — a peer-to-peer LAN messenger with no
server, its own threat model, its own interaction design, and its own architectural choices
(ADR-002 records the two-shell split; ADR-009 records the separate crypto identities). Those
differences are product decisions, not drift to be corrected.

Accordingly, this document:

- makes **no** recommendation to unify, converge, or share user-interface code, themes, components,
  navigation, or state management between Helix Remote and Helix Local;
- draws **no** comparison between the two as though one were a benchmark for the other;
- proposes **no** work inside `helix_local/`, and no shared package that would couple them.

Every finding, score, metric, and roadmap item below is derived from `helix_remote/` alone and
applies to `helix_remote/` alone.

Two facts about the wider repository are recorded here once, for completeness, and then not acted
on: the CI workflow at `.github/workflows/ci.yml` currently gates its verification jobs on the
`remote` path filter only, and `docs/dependencies/WORKSPACE_LOCKFILE_POLICY.md` is written to cover
both workspaces. Where a fix below touches a shared file, it is written to change Helix Remote's
behaviour only and to leave Helix Local's arrangements exactly as they are.

> **Toolchain note.** The audit itself was written with no Dart or Flutter SDK available, so every
> finding is derived from reading source at a cited line, tagged **[CONFIRMED]** (verified by
> reading the code at the cited location) or **[POTENTIAL]** (consistent with the code but
> requiring a runtime check). Dependency currency data in §20 came from the pub.dev API.
>
> **A toolchain was subsequently installed during Phase 0** (Flutter 3.44.8 / Dart 3.12.2, matching
> the `^3.12.0` constraint), and the baseline in §28 is measured, not estimated. Findings verified
> or sharpened by that run are marked inline.

---

## 0. Roadmap status (updated 2026-08-07)

This section is the answer to "how much of the plan is done". It is kept current because the
alternative was demonstrated: the document previously recorded status only through Phase 2 while
Phases 3–10 had all been committed, so reading it gave the impression work had stopped four weeks in.

**Measured, not asserted.** Every number below came from running the gate named next to it.

### CI was red, and had been

Phases 3–9 were committed without a passing `scripts/verify.sh`. Three gates were failing at once:

| Gate | State before | Cause |
|---|---|---|
| `dart format --set-exit-if-changed` | 17 files unformatted | never run |
| `flutter analyze` | 49 issues | Phase 4 added `prefer_const_*` without fixing what they surfaced |
| `flutter test` | 6 failures | 2 real defects (below) + 4 platform-specific golden baselines |

All green as of this update. The two test failures were **real**, not stale expectations: the
localization delegate returned a plain `Future`, so `Localizations` rendered a blank frame on every
launch; and four golden baselines had been approved off-Linux, failing every Linux run at ~1% pixel
diff — font anti-aliasing, not a regression. Goldens are now scoped to the CI reference platform.

### Phase status

| Phase | State | Evidence and what remains |
|---|---|---|
| 0 — Ground truth | **Done** | Lockfile committed and enforced on both jobs against a pinned SDK; coverage ratchet; release gate runs |
| 1 — Critical security | **Done** | `is_admin` capability, `verifyToken(expect:)`, mandatory `exp`, constant-time compares. One follow-up recorded and open: deriving `account_id` from the identity key to make reserved ids unclaimable by construction |
| 2 — Data exposure | **Done** | Redaction at the write boundary, `allowBackup=false`, 401/403 split, invite code out of the URL. **HIGH-2 now covers Windows** — the runner sets `WDA_EXCLUDEFROMCAPTURE` with a `WDA_MONITOR` fallback. MED-11's 26 remaining catches are migration idempotency guards, left deliberately |
| 3 — Architecture | **Mostly done** | `main.dart` 1,588 → 73 lines; three `MaterialApp`s → one; composition root and messaging service split; router in place. **Open:** 182 `setState` and 17 inline `MaterialPageRoute` remain, and 6 view-models cover 6 screens of ~30. Two files sit just over the 700-line criterion (703, 713) — marginal, not the 2,239/3,591-line god objects the finding described |
| 4 — Performance | **Done** | Delta-apply, streaming log purge, `prefer_const_*` **with the fallout fixed**, CI budget job and burst test |
| 5 — UI | **Done for the stated criterion** | Zero colour literals outside `helix_remote_ui`, enforced by `phase5_design_tokens_test.dart`; 127 became named tokens grouped by meaning. `Colors.transparent` is exempt — it means "draw nothing". **Open:** responsive layout is still one `LayoutBuilder`, and motion is 6 widgets |
| 6 — UX | **Partly done** | Deep links with intent filters and a Windows URI handler; pull-to-refresh 2 → 6; search present. Snackbar-heavy feedback unchanged |
| 7 — Accessibility | **Done** | The 1.3× cap is gone and a test forbids its return. All 51 icon buttons labelled, enforced by a source sweep. Guidelines now run against a real screen in light, dark, and both high-contrast themes — the previous suite asserted them against three widgets in isolation and passed while twelve buttons announced nothing |
| 8 — Testing | **Partly done** | Coverage ratchet, gallery goldens, OSV + SBOM, and a regression matrix that is now machine-checked against the tests it names. **Open:** the `integration_test/` journeys remain thin; the substantive end-to-end coverage is `backend/test/phase4_e2e_harness_test.dart`, which does registration, send/receive and multi-device fan-out with real crypto |
| 9 — Hardening | **Done** | Durable rate limiting, multi-`kid` JWT rotation, feature flags, SBOM, R8, TLS pinning, DR evidence. **MED-4 and tracing were shapes without callers** and are now wired: crash reporting reaches a self-hosted sink behind two-part consent, and correlation ids propagate into every log line emitted while handling a request, and across the S2S hop |
| 10 — Polish | **Mostly done** | Localization is real: ARB + `gen-l10n` replaced the hand-rolled ternary catalog, and **every plain literal in the client is extracted** — 245 keys, 0 remaining, enforced by `phase10_localization_test.dart`. The 51 interpolated `Text('$…')` sites are left deliberately: each needs an ICU placeholder and a human deciding what the message says. Bengali stays English-backed with the gap recorded in `untranslated.json` rather than machine-invented. `file_picker` pinned exactly rather than by caret (the caret is what allowed the drift MED-7 recorded); `googleapis_auth` 1→2 with 451 backend tests green; unused foreground-service permissions removed; governance gate grown 6 → 19 controls. **Open:** four major dependency bumps, deferred *with reasons*, and the external security review |

### Deliberately not done

Recorded so these read as decisions rather than omissions.

- **Four major dependency upgrades** (`flutter_local_notifications` 18→22, `flutter_secure_storage`
  10→11, `flutter_contacts` 1→2, `connectivity_plus` 6→7). Each is a platform plugin whose failure
  mode is invisible to a headless suite — a notification that never arrives, a database key that
  cannot be read on an existing install. §26 already prescribes a device matrix for the first of
  these; taking any of them on a green CI run alone would be the failure it warns about. Reasons per
  package are in `docs/dependencies/DEPENDENCY_RISK_REGISTER.md`.
- **P1-1's root cause.** H2 is now *eliminated* rather than untested — compression is never
  negotiated in either direction, so diagnostic step 2 would have been a no-op build. What remains
  needs step 1, which needs the VPS.
- **P0-1 (TURN) and P2-1 (SMS vendor).** Infrastructure, not repository changes.

---

## 28. Measured baseline (Phase 0, 2026-08-06)

Established with Flutter 3.44.8 / Dart 3.12.2 against `helix_remote/`:

| Gate | Result |
|---|---|
| `flutter analyze` | **Clean** — no issues found |
| `dart test` (backend) | **411 passed**, 0 failed |
| `flutter test` (app) | **327 passed**, 0 failed |
| `flutter test` (admin) | **87 passed**, 0 failed |
| `flutter test` (7 packages) | **224 passed**, 0 failed |
| **Total** | **1,049 tests, all green** |
| Line coverage (app + admin + packages) | **58.41%** (10,446 / 17,884 lines) |

The backend's 411 tests run under `dart test`, which emits no lcov, so they are not represented in
the coverage figure — the true product-wide number is higher than 58.41%.

**Two findings were confirmed empirically by this run:**

- **MED-7** — a fresh resolve of the declared `file_picker: ^12.0.0-beta.5` produced
  **`12.0.0-beta.7`**. The pre-release drift is not theoretical; it reproduces on any clean checkout.
- **MED-9** — the generated lockfile records `file_picker` as `dependency: transitive`, because in a
  workspace the root lockfile classifies from the root package's perspective. That is almost
  certainly the origin of the risk register's incorrect "not directly declared by Helix" claim. It
  *is* directly declared, at `app/pubspec.yaml:34`.

### Field defect found after Phase 2 — outgoing calls capped at 20 seconds

**[CONFIRMED from production logs, fixed]** · `packages/helix_remote_calls/lib/src/remote_call_service.dart`

Reported as "calls fail on the office network, work over VPN". It was neither — it was a timer.

`_startOutgoingTimers` armed **two** timers on the outgoing offer, both calling
`_failCallIfActive(..., failed)`:

| Timer | Limit | Cancelled by |
|---|---|---|
| `_outgoingRingTimer` | 45s | answer, or terminal state |
| `_offerAnswerTimer` | **20s** | **the answer only** — i.e. a human tapping Accept |

Being the shorter of the two, the 20s timer always won, so **every outgoing call was really capped
at 20 seconds and the 45s ring limit was dead code.** The callee's phone kept ringing for its full
45s while the caller had already given up. Two field failures fired at 20.005s and 20.004s — a
timer, not a network.

The margin was thinner than 20s in practice. Measured from a *successful* call in the same logs,
the callee spent **5.06s** between the user tapping Accept and the answer going out (ICE-config
REST fetch 1.9s, mic init 1.5s, SDP), leaving the human roughly 13s. On a slower link that
disappears — which is exactly why it correlated with one network and not another.

It also reported the result as `failed`, whose copy is *"The call could not be completed. Check
your network and try again"* — sending users to diagnose a network that was fine.

**Fix.** The offer-answer timer is removed entirely; the 45s ring limit is now the sole authority
for "nobody answered", which is what a phone does. Ring timeout now reports **"No answer."**
rather than blaming the network. `_failCallIfActive` gained a message override so a timeout can
say why without inventing a new terminal state.

**Regression tests** (`remote_call_service_test.dart`): one asserts the timer-start diagnostic
contains `outgoing_ring_ms=` and **not** `offer_answer_ms=` — the removed timer announced itself
on that line, so its absence is what prevents a silent reintroduction; the other asserts an
unanswered call surfaces `No answer.`. A harness detail surfaced on the way: `makeService` passed
`terminalStateGrace: Duration.zero`, and `_finishCall` only emits the terminal status when that
grace is `> 0`, so no test could previously observe terminal copy at all. It is now a parameter.

**Still open, separately** — both contribute to call reliability but neither caused these failures:
FCM is unconfigured (`push_ready: false`), so a backgrounded callee cannot be woken at all; and the
WebSocket closes with `1002` every 2–110 seconds (P1-1 in `HELIX_REMEDIATION_PLAN.md`, still
unresolved), which can delay or lose the offer.

### Phase 2 — what was and was not done

Two items are deliberately incomplete, recorded here rather than quietly closed:

- **HIGH-2 covers Android only.** `FLAG_SECURE` is applied through a
  `com.helix.remote/screen_security` channel, reference-counted so overlapping route
  transitions never drop the flag mid-swap, and applied to the conversation, conversation-list,
  and backup screens. The **Windows** desktop build is still capturable — that needs
  `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` in the C++ runner, which is a separate piece
  of work.
- **MED-11 is partial by design.** The 19 app-layer swallowed exceptions now log (control flow
  unchanged — the failure is still swallowed, it is simply no longer invisible). The remaining 26
  live in migration files and are `ALTER TABLE … ADD COLUMN` idempotency guards where
  "column already exists" *is* the expected outcome; rewriting them would add risk to schema
  migration for no diagnostic gain. `AppLogger`'s own three catches stay silent deliberately —
  logging a logging failure recurses.

One protocol note: **the server must be deployed before or with the client.** The 401/403 split and
the invite-lookup POST both change the contract. Both were written so an *older client* keeps
working against the new server (the client retains a narrow legacy-403 branch keyed to the exact
old response text; the server still answers the GET invite lookup), but a *newer client* against an
old server would not.

### Post-Phase-1 baseline

| Gate | Result |
|---|---|
| `dart format --set-exit-if-changed` | Clean (367 files) |
| `flutter analyze` / `dart analyze backend tool` | Clean |
| Backend | **425 passed** (411 + 14 new security regressions) |
| App / admin / packages | 327 / 87 / 224 passed |
| **Total** | **1,063 tests, all green** |

---

## 1. Executive Summary

Helix Remote is a server-backed, end-to-end-encrypted messenger: a Flutter client
(`app/`, 104 files), a Flutter operator console (`admin/`, 41 files), a Dart backend monolith
(`backend/`, 130 files, ~21k lines), and 8 domain packages. Total ~110,000 lines of Dart across
364 files, with ~1,053 test cases and a mature documentation estate (16 ADRs, threat model, key
lifecycle, privacy claim matrix, performance budgets, release and governance runbooks).

**This is not a low-quality codebase.** The cryptographic core is serious work — X3DH, double
ratchet, per-group epoch keys, SQLCipher-backed local storage, Ed25519-signed registration
transcripts, and a deliberate `relayOnly` ICE policy so call peers never learn each other's IP
addresses. The backend is a cleanly layered modular monolith with one module per bounded context.
Inline comments are exceptional: they explain *why*, and repeatedly document bugs that were found
and fixed. Lint configuration is strict (`strict-casts`, `strict-raw-types`, `avoid_dynamic_calls`,
`always_use_package_imports`) with only 8 suppressions across the whole product.

The problems are concentrated in three specific places, and they are serious:

1. **Authorization has a claimable-identity hole.** The server's admin gate is
   `adminAccountIds.contains(accountId)` where the set is `{'admin'}`, and `account_id` is chosen
   by the client at registration with no reserved-name check. On the public Helix Global instance
   (auto-issued invites), the first user to register as `account_id: "admin"` obtains the full
   operator console. See **CRIT-1**.
2. **The client has no UI architecture.** `app/` is ~30,000 lines of Flutter with no state
   management (208 raw `setState` calls), no router (18 inline `MaterialPageRoute`s, zero named
   routes), no theme file (`ThemeData` constructed inline in `main.dart`, twice, with divergent
   configuration), no localization (274 hardcoded strings), no responsive layout (zero
   `LayoutBuilder`, despite shipping a Windows desktop build), and effectively no accessibility
   semantics (one `Semantics` widget). See **MED-2, §17, §19**.
3. **Governance documents assert controls that do not exist in code.**
   `docs/security/LOG_REDACTION.md` requires redaction of tokens and payloads; the client's
   `AppLogger` performs none, and that log is then exported to arbitrary apps via the share sheet.
   `WORKSPACE_LOCKFILE_POLICY.md` states `pubspec.lock` is committed; it is not tracked.
   `DEPENDENCY_RISK_REGISTER.md` describes `file_picker` as "not directly declared by Helix"; it is
   directly declared in `app/pubspec.yaml:34`. See **HIGH-1, HIGH-4, MED-9**.

**Verdict: not production-ready for a large user base today.** Roughly 4 weeks of focused work
closes the security and correctness gaps (Phases 0–2). Reaching a genuinely enterprise-grade bar
across UI, accessibility, observability, and scale is a 5–6 month programme.

---

## 2. Overall Health Score: **63 / 100**

| Dimension | Score | One-line justification |
|---|---:|---|
| **3. Architecture** | 67 | Backend and packages are exemplary; the client has no state or navigation architecture. |
| **4. Security** | 62 | Strong cryptographic core undermined by one critical authz hole and several missing platform hardening controls. |
| **5. Performance** | 70 | Real work done (pagination, isolates, WS backpressure); one O(n²) hot path and no perceived-performance strategy. |
| **6. UI** | 48 | No design system; 194 hardcoded colours; no skeletons; no responsive layout despite a desktop target. |
| **7. UX** | 58 | Coherent flows and good error copy, but text scale capped, spinner-only loading, no deep links. |
| **8. Maintainability** | 70 | Outstanding docs and comments; 24 production files exceed 700 lines, two of them god objects. |
| **9. Scalability** | 55 | SQLite single-writer, in-memory rate limiter, no JWT key-rotation window, no horizontal story. |
| **10. Testing** | 68 | ~1,053 tests with strong backend and service coverage, but zero integration tests and no coverage gate. |

Weighting: Security ×2, Architecture ×1.5, Testing ×1.5, all others ×1. → 627.5 / 10 = **62.75**.

---

## 11. Major Findings

| ID | Finding | Severity | Confidence |
|---|---|---|---|
| **CRIT-1** ✅ | Reserved admin account ID `"admin"` is claimable by any registering user → full operator console takeover | Critical | CONFIRMED · **fixed (Phase 1)** |
| **CRIT-2** ✅ | Refresh tokens are accepted as access tokens on every REST route and the WebSocket | High→Critical | CONFIRMED · **fixed (Phase 1)** |
| **HIGH-1** ✅ | Client diagnostic log is unredacted, persistent, and user-shared — contradicts `LOG_REDACTION.md` | High | CONFIRMED · **fixed (Phase 2)** |
| **HIGH-2** ✅ | No `FLAG_SECURE` anywhere: message content is screenshot-, recorder-, and recents-visible | High | CONFIRMED · **fixed on Android (Phase 2), Windows (2026-08-07)** |
| **HIGH-3** ✅ | `android:allowBackup` left at default `true` — app-private data extractable via ADB/cloud backup | High | CONFIRMED · **fixed (Phase 2)** |
| **HIGH-4** ✅ | `pubspec.lock` is not committed despite policy — builds are not reproducible | High | CONFIRMED · **fixed (Phase 0)** |
| **HIGH-5** ✅ | HTTP 403 is overloaded for both "expired token" and "not permitted", causing spurious refresh-token rotation on every authorization denial | High | CONFIRMED · **fixed (Phase 2)** |
| **MED-1** ✅ | Full loaded-window re-fetch + re-decrypt on every inbound message (O(n²) under burst) | Medium | CONFIRMED · **fixed (Phase 3/4)** |
| **MED-2** ◐ | Client has no state management, router, design system, localization, or responsive layout | Medium | CONFIRMED · **router, single shell, design tokens and localization done**; state management partial (182 `setState`), responsive layout open |
| **MED-3** ✅ | Non-constant-time comparison of JWT signature and admin bearer token | Medium | CONFIRMED · **fixed (Phase 1)** |
| **MED-4** ✅ | No crash reporting or analytics | Medium | CONFIRMED · **fixed (2026-08-07)** — opt-in, redacted, self-hosted sink. The consent and event types had existed since Phase 9 with no caller |
| **MED-5** ✅ | Accessibility: 1 `Semantics` widget in ~30k LOC; text scale hard-capped at 1.3× | Medium | CONFIRMED · **fixed (Phase 7 / 2026-08-07)** — cap removed and guarded, all icon buttons labelled, guidelines run against a real screen |
| **MED-6** ✅ | In-memory rate limiter — resets on restart, not shared across processes | Medium | CONFIRMED · **fixed (Phase 9)** |
| **MED-7** ✅ | `file_picker` pinned to a pre-release with a caret range that has already drifted | Medium | CONFIRMED · **fixed (2026-08-07)** — exact pin; ADR-024 records the win32 conflict that keeps it on 12.x |
| **MED-8** ◐ | Client dependencies materially behind current — `flutter_local_notifications` 4 majors, `flutter_contacts` 1 major, `connectivity_plus` 1 major | Medium | CONFIRMED · minor gaps closed, `googleapis_auth` 1→2; **four majors deferred with reasons** |
| **MED-9** ✅ | Dependency risk register is factually wrong about `file_picker` | Medium | CONFIRMED · **fixed (2026-08-07)** — corrected, and a governance control keeps the withdrawn claim withdrawn |
| **MED-10** ✅ | `remote_release_gate.ps1` is unrunnable — statement precedes `param()` | Medium | CONFIRMED · **fixed (Phase 0)**, along with two dev scripts carrying the same defect |
| **MED-11** ◐ | 45 silently swallowed exceptions | Medium | CONFIRMED · **app layer fixed (Phase 2)**; 26 migration guards left as legitimate |
| **MED-12** ◐ | CI has no coverage gate, no vulnerability scanning, and no integration tests | Medium | CONFIRMED · coverage ratchet, OSV and SBOM done; integration journeys still thin |
| **LOW-1** ✅ | No release obfuscation / R8 / resource shrinking | Low | CONFIRMED · **fixed (Phase 9)** |
| **LOW-2** ✅ | Duplicate private helpers (`_bytesToHex` / `_hexBytes`), dead `is_admin` claim | Low | CONFIRMED · **fixed (Phase 3)** |
| **LOW-3** ✅ | Invite codes travel in URL query strings | Low | CONFIRMED · **fixed (Phase 2)** |
| **LOW-4** ✅ | Unused Android foreground-service permissions declared | Low | **CONFIRMED and fixed (2026-08-07)** — no service element anywhere, none contributed by merged plugin manifests, no caller for `startForegroundService` |
| **LOW-5** ✅ | No iOS support | Low | CONFIRMED · **recorded in ADR-023 (Phase 10)** |

### Verified clean (audited, no issue found)

Recorded so a future pass need not re-tread them:

- **SQL injection** — every interpolated fragment (`$table`, `$where` in
  `audit_tokens_repository.dart:60,67`, `operational_repository.dart:157`,
  `accounts_devices_repository.dart:741`) is a compile-time constant; all user values are bound
  parameters.
- **Path traversal** — `object_storage.dart:15-22` rejects `/`, `\`, `..`; the attachments module
  additionally applies `p.basename()` at every filesystem call site.
- **Committed secrets** — none. `.env.example` only; no keystores, no service-account JSON.
- **WebSocket credential handling** — token sent in the `Authorization` header, never the URL; log
  lines emit host and path only (`remote_websocket_client.dart:60-64,120-123`).
- **TLS posture** — `HttpClient` is constructed without a `badCertificateCallback`
  (`remote_rest_client.dart:22-26`), so validation is strict; `RemoteDevelopmentConfig._validate()`
  rejects any plaintext or localhost target under the production profile
  (`remote_config.dart:596-623`).
- **Admin gate application** — all 16 privileged handlers in `operability.dart` call `_isAdmin`.
  The gate is applied consistently; it is the identity behind it that is forgeable (CRIT-1).

---

## 12. Critical Issues

### CRIT-1 · Reserved admin account ID is claimable by any user → operator console takeover

**Severity: Critical · Likelihood: High on public instances · [CONFIRMED]**

**Location**
- `backend/lib/src/modules/auth/registration.dart:7` — `accountId` read from request body
- `backend/lib/src/server_impl.dart:81` — `this.adminAccountIds = const {'admin'}`
- `backend/lib/src/modules/operability.dart:268-283` — `_isAdmin()`
- `backend/lib/src/modules/privacy_compliance.dart:94`, `contacts.dart:670` — same set

**Root cause.** The server's only admin authorization primitive is:

```dart
// operability.dart:272
if (accountId == null || !adminAccountIds.contains(accountId)) { ... deny ... }
```

`adminAccountIds` defaults to `const {'admin'}` and `bin/server.dart` never overrides it. The
literal string `'admin'` therefore *is* the admin credential. Separately, `_registerHandler` takes
`account_id` verbatim from the client body with **no format constraint and no reserved-name list** —
the only occurrences of `'admin'` in the backend are the `adminAccountIds` default and the
synthetic claims at `server_impl.dart:492`.

`_validateRegistrationKeys` (`registration.dart:229-271`) does bind `accountId` into a signed
transcript — but the signature is made with the *registrant's own* key, so it proves the client
committed to the ID, not that the ID is legitimately theirs. An attacker signs `"admin"` as
happily as a UUID.

**Attack.** Register normally, substituting `account_id: "admin"`. Requirements: a valid invite and
a phone number that can receive an OTP. On the Helix Global instance, `globalInstanceMode`
auto-issues invites through the *unauthenticated* route `/accounts/invite/auto-issue`
(`server_impl.dart:464`, `auth/invites.dart:66`), so the only real barrier is receiving one SMS.
The issued JWT then carries `account_id: "admin"`, and `_isAdmin()` returns `true`.

**Impact.** Complete compromise of the operator surface: `/ops/users/<id>/delete`, `/suspend`,
`/block`, `/ops/logs`, `/ops/backup`, `/ops/config`, `/ops/invites`, `/ops/federation/worldwide`,
plus the privacy-compliance and contacts admin paths. It is first-come-first-served and permanent —
once `getAccount('admin')` is non-null, the legitimate operator can never claim it either.

**Fix (layered — do all three).** ✅ **Fixed in Phase 1.**
1. **Reserve the namespace.** Reject `account_id` values in a reserved set (`admin`, `system`,
   `root`, `helix`, …) at registration, and bound the format.
   > **Correction to this audit.** An earlier draft said "requiring a UUIDv4 costs nothing". That
   > was wrong. The client derives `account_id` as **16 lowercase hex characters** — the first 8
   > bytes of the Ed25519 identity public key
   > (`app/lib/app/composition_root/pending_registration.dart:65`) — not a UUID, and existing
   > deployments also hold ids predating any rule. Enforcing UUIDv4 would have broken every
   > client. Implemented instead: a reserved-name check plus loose character/length bounds that
   > only reject what no honest client sends.
   >
   > A stronger control remains available and is **not** yet implemented: because the id *is*
   > derivable from the identity public key the server already receives, registration could verify
   > the derivation and make reserved ids unclaimable by construction. That is a test-suite and
   > data migration (the backend suite registers accounts as `alice`, `bob`, …), so it is recorded
   > here as follow-up rather than smuggled into a security fix.
2. **Stop using a string as a capability.** Replace `adminAccountIds` with an explicit `is_admin`
   column on the accounts table (migration 40), resolved once in the auth middleware and read by
   every gate. The parameter is gone from `BackendServer`, `OperabilityModule`, `ContactsModule`,
   and `PrivacyComplianceModule`. Promotion is `setAccountAdmin`, an out-of-band database action
   with no HTTP route, so a compromised account cannot promote itself.
3. **Add a startup guard** that refuses to serve a database containing a reserved id, since such a
   row can only predate the check and is the fingerprint of a claimed-admin compromise.

**Regression test.** `backend/test/phase1_privilege_escalation_test.dart` — 14 cases covering
reserved-id rejection (including casing), ordinary ids still registering, `/ops/*` refusing a
self-registered account across five routes, grant-then-revoke of the capability, and the startup
guard.

---

### CRIT-2 · Refresh tokens are accepted as access tokens

**Severity: High, escalating to Critical in combination with CRIT-1 · [CONFIRMED]**

**Location**
- `backend/lib/src/jwt.dart:34-36` — mints `token_type`
- `backend/lib/src/server_impl.dart:500-527` — REST auth middleware
- `backend/lib/src/websocket.dart:170` — WebSocket upgrade

**Root cause.** `generateToken` correctly stamps `token_type: 'refresh'` on refresh tokens.
`verifyToken` (`jwt.dart:43-86`) validates signature, `iss`, `aud`, `nbf`, `exp` — but **not
`token_type`**. The REST middleware and the WebSocket handler both call `verifyToken` and then
check only `account_id`, `device_id`, device-active and account-suspended state. Neither rejects a
refresh token. Only `_refreshHandler` (`auth/refresh.dart:16-18`) checks `claims['refresh'] != true`,
and it checks it in the *opposite* direction.

**Impact.** The access/refresh split is nullified:
- Effective credential lifetime becomes **7 days instead of 1 hour** (`auth/refresh.dart:61-75`).
- A stolen refresh token grants immediate full API and realtime access **without ever calling
  `/accounts/refresh`** — so it never triggers the rotation-and-revoke logic, and the
  replay-detection at `auth/refresh.dart:44-50` (which revokes all device sessions on reuse of a
  revoked token) is bypassed entirely. The single strongest detection control in the auth design is
  silently unreachable.

**Fix.** ✅ **Fixed in Phase 1.** `verifyToken` now takes a **required** `expect:
ExpectedTokenType` argument, so the expectation cannot be inherited by omission at a new call site.
It asserts the positive (`token_type == 'access'`), so a token minted before the claim existed
fails closed; it also cross-checks the legacy boolean `refresh` claim and rejects any token where
the two disagree. All three production call sites now state their expectation:
`server_impl.dart` and `websocket.dart` require `access`, `auth/refresh.dart` requires `refresh` —
which closes the swap in both directions.

**Hardening done alongside.** `exp` is now mandatory (`jwt.dart`) — absence is a rejection rather
than an unexpiring token. Signature comparison is constant-time (MED-3).

---

## 13. High Priority Issues

### HIGH-1 · Unredacted, persistent, user-shared diagnostic log

**[CONFIRMED]** · `app/lib/services/app_logger.dart`

`AppLogger._write` (line 53) performs exactly one transformation — newline flattening — and appends
verbatim to `helix_remote_anomaly_log.txt` in the app documents directory. There is **no redaction
of any kind**. Measured against the product's own `docs/security/LOG_REDACTION.md`, which mandates
redaction of "private keys, session keys, proofs, access tokens, and API keys" and "full peer
fingerprints".

What actually reaches that file:

- `main.dart:59` — `AppLogger.instance.error('uncaught', '$error', stack)` for every uncaught zone
  error, plus `main.dart:46` for every `FlutterError`.
- `remote_rest_client.dart:155-165` — `RemoteRestException.message` is set to the **entire raw
  response body**, and `.uri` to the full request URI. When such an exception goes uncaught it lands
  in the log with both.
- `main.dart:1338` — `'OTP request failed: $e'` on the phone-registration path.

This is not hypothetical: `docs/operations/HELIX_REMEDIATION_PLAN.md` quotes a real captured log
line containing a full API URI and server error body. The file is then **exported to arbitrary
apps** via `SharePlus.instance` (`settings_screen.dart:113`), and users are asked to share it for
support.

Worth noting that the backend side of the same product is handled well — `RedactedLogger` exists,
and audit logging truncates client IPs to /24 and rejects payloads containing forbidden keys
(`audit_tokens_repository.dart:78-116`). The client is the gap.

**Fix.** Introduce a single redaction function applied inside `_write` (not at call sites, which
cannot be enforced): strip bearer tokens, long hex/base64 runs, `phone`/`otp`/`invite_code` query
and JSON values, and truncate response bodies. Add an allowlist-based structured-event path for new
logging. Add a unit test that feeds a synthetic token/phone/body through the logger and asserts
absence.

### HIGH-2 · No screenshot or screen-recording protection

**[CONFIRMED]** · `grep -rn "FLAG_SECURE|setSecure"` across `helix_remote/` → **zero hits**

`FLAG_SECURE` is never set. Consequences: message content is screenshot-able and
screen-recordable; the Android recents/task-switcher thumbnail retains the last-rendered
conversation in plaintext; any app holding `MediaProjection` can capture the screen.

This is materially inconsistent with the product's own privacy posture — `privacy_screen.dart:296`
advertises that "Locked chats and strict mode always redact content" — and the mechanism is already
present: `MainActivity.kt` manipulates window flags for calls, so it is simply not used for secrecy.

**Fix.** Set `FLAG_SECURE` by default on conversation, backup-key, and QR/verification screens;
expose a user toggle if screenshots are wanted elsewhere. On Windows, use
`SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)`.

### HIGH-3 · `android:allowBackup` left at default

**[CONFIRMED]** · `app/android/app/src/main/AndroidManifest.xml`

The manifest sets neither `android:allowBackup="false"`, `android:fullBackupContent`, nor
`android:dataExtractionRules`. The platform default is `true`. On many devices the app's private
directory — which holds the SQLCipher database, the anomaly log, and shared preferences — is
therefore eligible for ADB backup and cloud auto-backup. SQLCipher protects database contents only
insofar as the key stays in Keystore, but the **log file is plaintext** and is included.

**Fix.** `android:allowBackup="false"` plus explicit `dataExtractionRules` (Android 12+) excluding
the database and log directories.

### HIGH-4 · `pubspec.lock` is not committed, contradicting stated policy

**[CONFIRMED]** · `git ls-files | grep -c pubspec.lock` → `0`, and `helix_remote/.gitignore:5`
listed `pubspec.lock` explicitly

`docs/dependencies/WORKSPACE_LOCKFILE_POLICY.md` states that the lockfile is committed "as the
reproducible dependency snapshot". No lockfile was tracked — and this was not an oversight: the
Helix Remote workspace `.gitignore` actively excluded it. (The root `.gitignore` does not mention
`pubspec.lock`; the exclusion was one level down, which is why an initial check missed it.)

**Impact.** Every CI run and every developer `pub get` re-resolves ~23 direct client dependencies
within their caret ranges. Builds are not reproducible; a malicious or merely broken patch release
lands silently in the next build; and a CI failure cannot be distinguished from an upstream change.
MED-7 shows this drift has already occurred in practice. For a security product this is a genuine
supply-chain exposure, not a hygiene nit.

**Fix.** Commit `helix_remote/pubspec.lock`. Add a CI step running `pub get --enforce-lockfile`
against the Helix Remote workspace and failing on drift. Move version bumps to a deliberate,
reviewed action.

### HIGH-5 · HTTP 403 overloaded → spurious refresh-token rotation on every permission denial

**[CONFIRMED]** · `server_impl.dart:501-506` and `app/lib/app/remote_rest_client.dart:179-180`

The server returns **403** for an invalid or expired token (`'Forbidden: Invalid or expired token'`)
rather than 401. The client compensates:

```dart
// remote_rest_client.dart:179
bool _isAuthFailure(int? statusCode) => statusCode == 401 || statusCode == 403;
```

But the backend also uses `AppError.forbidden` for ordinary authorization denials — 40+ sites,
e.g. `group_calls.dart:182` `'only the host can kick participants'`, `attachments.dart:358`
`'Access denied'`, `contacts.dart:130` `'Contact unavailable'`.

**Consequence.** Every legitimate "you may not do that" triggers `_refreshAuthOnce()`, which
performs a **rotating** refresh (`auth/refresh.dart:53` revokes the used token, then mints a new
pair) and then **retries the forbidden request** with `attempt = 0` (`remote_rest_client.dart:85-87`),
resetting the retry budget. A single denied action therefore costs a token rotation, a database
write, and up to three re-attempts of an operation that can never succeed. Under multi-account usage
(`account_runtime_registry.dart`) several clients rotate independently, and any interleaving risks
tripping the replay detector at `auth/refresh.dart:44`, which revokes **all** sessions for the
device.

**Fix.** Server: return **401** for authentication failures and reserve **403** for authorization
denials. Client: narrow `_isAuthFailure` to `401` only, and stop resetting `attempt` after a
refresh. Ship server-first.

---

## 14. Medium Priority Issues

**MED-1 · Full window re-decrypt on every inbound message.**
`app/lib/screens/conversation_screen.dart:224-229`. `_refreshVisibleMessages()` sets
`visibleLimit = _messages.length` and re-runs `messageHistory(limit: visibleLimit)`, replacing the
whole list. If the user has paged back to 500 messages, **every** arriving message, receipt, or edit
re-reads 500 rows from SQLCipher and re-runs 500 AEAD decryptions, then rebuilds the list. During a
burst this is quadratic. The surrounding comment shows the team already fought a runaway loop here;
this is the remaining cost. **Fix:** apply the delta from `RemoteSyncChange` to the in-memory list,
falling back to a bounded re-read only when the change cannot be applied locally.

**MED-2 · The client has no UI architecture.** Measured across `app/lib` (~30k lines, 104 files):

| Concern | State |
|---|---|
| State management | none — 208 raw `setState`, 0 `ChangeNotifier`/`ValueNotifier`/`InheritedWidget`, 24 hand-managed `StreamSubscription`s |
| Navigation | 18 inline `MaterialPageRoute`, **0** named routes, **0** `onGenerateRoute`, 3 separate `MaterialApp`s |
| Theming | no theme file; `ThemeData` built inline at `main.dart:244` **and again** at `main.dart:745`, with divergent config — one declares `highContrastTheme`/`highContrastDarkTheme`, the other does not, so high-contrast support depends on which shell the user enters through |
| Design tokens | 194 hardcoded colour references, 134 inline `EdgeInsets` literals, no spacing scale |
| Localization | none — no `l10n.yaml`, no `.arb`, 274 hardcoded `Text('…')` strings, while `flutter_localizations` is declared as a dependency |
| Responsive | **0** `LayoutBuilder`, **0** breakpoints — while shipping a Windows desktop build |
| Accessibility | 1 `Semantics` widget, 1 `semanticLabel`, 49 `IconButton`s against 43 tooltips |

These are not stylistic preferences. A Flutter application of this size without a view-model layer
puts service orchestration, pagination, decryption sequencing and error mapping directly into
`State` classes — which is precisely why MED-1 lives inside a widget, and why
`conversation_list_screen.dart` (1,570 lines), `calls_tab_screen.dart` (1,623) and
`contact_info_screen.dart` (1,377) are the size they are.

**MED-3 · Non-constant-time secret comparison.** `jwt.dart:52` — `if (signature != expectedSignature)`
compares HMAC signatures with short-circuiting string equality. `server_impl.dart:444` —
`token == adminTokenOverride` compares the **raw** admin bearer token the same way; `:449` does so
for its SHA-256 hex. Remote timing attacks over a network are difficult, but this is a standard
finding and the fix is a five-line constant-time byte comparison.

**MED-4 · No crash reporting and no analytics.** No `sentry`, `firebase_crashlytics`,
`firebase_analytics`, or equivalent in any Helix Remote pubspec. The only telemetry is the local
file logger, retrieved by asking the user to share it. Production crash rate, ANR rate, and adoption
are currently unobservable. For a privacy-first product this may be *deliberate* — but it needs to
be an explicit, documented decision. A self-hosted, opt-in, redacted crash sink satisfies both goals.

**MED-5 · Accessibility is effectively absent.** See the MED-2 table. Additionally, text scaling is
**hard-capped at 1.3×** (`main.dart:32-40`), and the comment states why: *"Several fixed-size layout
elements … don't grow with text scale, so leaving it unbounded clips or overflows them."* That is an
accessibility guarantee traded away to paper over non-responsive layout. Android and WCAG expect
usability to ~2×. The admin console has zero `Semantics` widgets.

**MED-6 · In-memory rate limiter.** `backend/lib/src/rate_limiter.dart` — `InMemoryRateLimitStore`
holds buckets in a `Map` with a 5-minute idle-eviction timer. The eviction logic is thoughtful
(`isFullyRefilledAt` projects the lazy refill rather than reading the stale field), but state is
per-process and lost on restart. Restart-to-reset defeats OTP and login throttling, and the design
cannot survive a second backend instance.

**MED-7 · `file_picker` is a pre-release under a caret range, and has already drifted.**
`app/pubspec.yaml:34` declares `file_picker: ^12.0.0-beta.5`. Queried against pub.dev on the audit
date, the latest **stable** release of `file_picker` is **11.0.3** — so the app is running a
pre-release *ahead of* the stable line, where no stability guarantee applies. The caret range
permits any later pre-release, and `DEPENDENCY_RISK_REGISTER.md` records `12.0.0-beta.7` as the
resolved version against a declared `beta.5`: the drift is not theoretical, it has already happened,
and with no committed lockfile (HIGH-4) nothing pins it. **Fix:** pin an exact version, or move back
to the 11.x stable line, and record the decision.

**MED-8 · Client dependencies are materially behind current.** Declared versions in
`app/pubspec.yaml` against the latest published on pub.dev at the audit date:

| Package | Declared | Latest | Gap |
|---|---|---|---|
| `flutter_local_notifications` | `^18.0.0` | 22.2.0 | **4 major versions** |
| `flutter_contacts` | `^1.1.9+2` | 2.3.1 | 1 major |
| `connectivity_plus` | `^6.1.3` | 7.3.1 | 1 major |
| `cryptography_flutter` | `^2.0.0` | 2.3.4 | minor, but a crypto dependency |
| `mobile_scanner` | `^7.2.0` | 7.4.0 | minor |
| `flutter_webrtc` | `^1.5.1` | 1.6.0 | minor |
| `path_provider` | `^2.1.6` | 2.1.6 | current |

`flutter_local_notifications` is the notable one: four majors of API changes, Android 14/15
behavioural fixes, and permission-model updates are unapplied on the notification path of a
messaging app.

**MED-9 · Dependency risk register is factually wrong.** It states `file_picker` *"is not directly
declared by Helix"*. It is directly declared at `app/pubspec.yaml:34`. A control document that is
wrong is worse than none, because reviewers trust it.

**MED-10 · The release gate script cannot run.** `scripts/remote_release_gate.ps1` places
`$ErrorActionPreference = "Stop"` on line 1, **before** the `param(...)` block on line 3. PowerShell
requires `param()` to be the first statement; with an assignment ahead of it the block is parsed as
a command invocation and the script fails. Trivial fix (swap the two), but it means the documented
release gate has not been exercised as written.

**MED-11 · 45 swallowed exceptions.** Bare `catch (_) {}` / `catch (e) {}`: `packages/` 22,
`app/lib` 17, `backend/lib` 6, `admin/lib` 0. Some are legitimate (best-effort log cleanup). Many
hide real failures.

**MED-12 · CI verifies correctness but not quality or safety.** `.github/workflows/ci.yml` runs
format, analyze, and the full test suite for Helix Remote on Windows and Linux, with mandatory
debug builds — that part is good. Missing: no coverage collection or threshold (`**/coverage/` is
gitignored), no dependency vulnerability scanning (`flutter pub outdated` is advisory and
non-blocking), no SAST, no SBOM, and **no integration tests at all** — there is no
`integration_test/` directory anywhere in the product.

---

## 15. Low Priority Issues

- **LOW-1 · No release hardening.** `app/android/app/build.gradle.kts` sets neither
  `isMinifyEnabled` nor `isShrinkResources`, and no release script passes
  `--obfuscate --split-debug-info`. The `.gitignore` already anticipates symbol files
  (`app.*.symbols`, `app.*.map.json`), so the intent existed. Dart AOT limits the exposure, but
  Kotlin/Java and resources ship in the clear. Signing itself is handled well — the build fails
  loudly if release keystore material is absent.
- **LOW-2 · Dead and duplicated code.** `app/lib/app/composition_root.dart:122-128` defines
  `_bytesToHex` and `_hexBytes` — byte-identical implementations. `server_impl.dart:494` sets an
  `is_admin: true` claim that no code ever reads (the real gate is the account-ID set — CRIT-1).
- **LOW-3 · Invite codes in URLs.** `remote_rest_client.dart:294-299` passes `invite_code` as a
  query parameter, so it reaches nginx access logs, and reaches the client's own diagnostic log via
  `RemoteRestException.uri` (HIGH-1). Move to a POST body or a header.
- **LOW-4 · [POTENTIAL] Unused foreground-service permissions.** The manifest declares
  `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CAMERA`, and `FOREGROUND_SERVICE_MICROPHONE`, but
  declares no `<service>` element. `android_call_runtime_service.dart` only drives window flags
  through a MethodChannel. Verify whether a merged plugin manifest supplies the service; if not,
  remove the permissions — Play Console requires justification for each.
- **LOW-5 · No iOS support.** `app/` targets android + windows; `admin/` adds linux, macOS, and web.
  A consumer messenger without iOS is a product-scope decision that should be recorded in an ADR,
  not left as an implicit gap.

---

## 16. Security Audit

**Threat model in force:** `docs/security/THREAT_MODEL.md` and `TRUST_MODEL.md` exist and are
substantive. This audit tests the code against them.

| Area | Assessment |
|---|---|
| **Cryptographic core** | **Strong.** X3DH, double ratchet, per-group epoch keys, attachment crypto, backup crypto, transfer handshake — all as separate, tested packages (`helix_remote_crypto`, 224 package tests). Registration binds account and device keys into a signed transcript over Ed25519 (`registration.dart:229-271`). Device signing and agreement keys are required to be distinct (`:246`). Public keys are length-checked at 32 bytes (`:274-281`). |
| **Authentication** | **Weak at the boundary.** JWT HS256 is fine for a monolith, but `token_type` is unvalidated (CRIT-2), `exp` is optional, and signature comparison is not constant-time (MED-3). Key rotation is impossible without a flag day: `verifyToken` requires `headerMap['kid'] == keyId` (`jwt.dart:59`) with a single fixed `kid`, so changing the secret invalidates every live token instantly, with no overlap window. |
| **Authorization** | **Critically flawed** (CRIT-1). Mitigating credit: the gate is applied consistently at all 16 privileged handlers; it is the identity behind it that is forgeable. |
| **Session management** | Rotation-on-use with replay detection and blast-radius revocation (`auth/refresh.dart:44-50`) is a genuinely good design — currently bypassable via CRIT-2 and needlessly triggered via HIGH-5. |
| **Transport** | HTTPS/WSS enforced by config validation; production profile rejects plaintext and localhost (`remote_config.dart:596-623`); physical-Android profile explicitly refuses LAN HTTP (`:242-248`). **No certificate pinning** — defensible, since users may point the app at arbitrary self-hosted servers, but the known-host Helix Global endpoint could be pinned with a fallback. |
| **Storage** | SQLCipher via `hooks.user_defines.sqlite3.source: sqlcipher`; keys in `flutter_secure_storage` (Keystore/DPAPI) under a product-scoped prefix (`composition_root.dart:48-64`); a defined reset key list (`:102-120`). Undermined by `allowBackup` (HIGH-3) and the plaintext log (HIGH-1). |
| **Input validation** | Good. Path traversal blocked (`object_storage.dart:15-22`); no SQL injection; server URL parsing is careful, with a documented lookbehind regex preventing scheme mangling (`remote_config.dart:490-516`); `phone_last4` regex-validated and silently dropped rather than fatal (`registration.dart:52-56`). |
| **Sensitive data exposure** | The weakest non-authz area: HIGH-1 (logs), HIGH-2 (screen capture), HIGH-3 (backup), LOW-3 (invite in URL). The backend side is much better — audit logs truncate IPs to /24 and reject payloads containing forbidden keys (`audit_tokens_repository.dart:78-116`). |
| **Platform channels** | One channel, `com.helix.remote/calls`, single method, `notImplemented()` otherwise (`MainActivity.kt`). Clean. |
| **Admin surface** | Single static bearer token, no expiry, no rotation, no scoping, no MFA, written in plaintext to `ADMIN_TOKEN.txt` beside the database (`bin/src/admin_token_file.dart`). The file's own text tells the operator to delete it, which is honest but not a control. |
| **Dependencies** | No committed lockfile (HIGH-4); a drifting pre-release (MED-7); four-major staleness on the notification path (MED-8); no vulnerability scanning (MED-12). |

---

## 17. Architecture Review

**What is genuinely good.** The backend is a well-executed modular monolith: 130 files, ~21k lines,
one module per bounded context (`auth`, `messaging`, `calls`, `groups`, `attachments`, `backups`,
`contacts`, `federation`, `operability`, `privacy_compliance`), each with its own router and
repository. Large modules are split with `part` files along real seams (`auth/registration.dart`,
`auth/refresh.dart`, `calls/signaling.dart`). Dependency direction is clean: `domain` ←
`api`/`crypto`/`storage` ← `sync`/`calls`/`groups` ← `app`. Sixteen ADRs document the decisions, and
`docs/architecture/module_boundaries.json` encodes the boundaries as data. Abstractions are
introduced where they earn their place — `KeyValueStore`, `ObjectStorageAdapter`, `RateLimitStore`,
`HelixRemoteRestClient` are all interfaces with injectable implementations, which is why the backend
and packages are testable.

**The central problem: the client layer has no architecture at all.** Everything in MED-2's table
compounds. With no view-model layer, screens own service calls, decryption orchestration, pagination
state and error mapping directly. The consequences are visible in the file sizes and in MED-1.

**Secondary architectural findings.**

- **`part`-file god objects.** `RemoteCompositionRoot` is 2,239 lines across 9 `part` files;
  `RemoteMessagingService` is 3,591 lines across 9. `part` improves file size but not coupling —
  every part shares one private namespace and one class's state, so nothing is independently
  testable or replaceable. These are the two natural extraction targets.
- **`main.dart` at 1,588 lines** carries bootstrap, three `MaterialApp`s, theme definitions,
  connectivity handling, and the registration UI.
- **24 production files exceed 700 lines**, led by `calls_tab_screen.dart` (1,623),
  `main.dart` (1,588), `conversation_list_screen.dart` (1,570), and `remote_call_service.dart`
  (1,498). The two `migrations.dart` files (1,344 and 1,319) are append-only by nature and are not a
  concern.
- **SOLID.** Dependency inversion is respected at package boundaries and absent in the UI layer,
  which depends on concrete services directly.

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
| P-6 | No `const` discipline enforced | `analysis_options.yaml` | `prefer_const_constructors` is not in the lint set; with 194 hardcoded colours and inline styling, const-promotion is likely being missed widely |
| P-7 | No perceived-performance strategy | `app/lib` | 0 skeleton/shimmer loaders; 24 raw `CircularProgressIndicator`s |

**Not measurable here.** `docs/performance/PERFORMANCE_BUDGETS.md` and `BENCHMARK_DATASETS.md`
define budgets, but no CI job enforces them and no profiling artifacts are committed. Startup time,
frame timings, and memory are unverified.

---

## 19. UI / UX Review

### UI

The client is functional but visually unfinished, and the cause is structural rather than
decorative — there is no design system to be consistent *with*.

- **No design tokens.** 194 hardcoded colour references, concentrated in `message_tile.dart` (31),
  `conversation_screen.dart` (24), `call_screen.dart` (22), `conversation_list_screen.dart` (20).
  134 inline `EdgeInsets` literals with no spacing scale. Component appearance is therefore decided
  per screen, by whoever wrote it.
- **Two divergent `ThemeData` definitions inside one file** (`main.dart:244` and `:745`) — only the
  second declares high-contrast variants.
- **Three `MaterialApp`s** in one client, each with its own theme configuration.
- **Motion is essentially absent.** 4 `Animated*` widgets, 0 `Hero`, 0 custom page transitions in
  ~30k lines. Navigation is instantaneous and unexplained; nothing signals hierarchy or continuity.
- **No skeleton loaders.**
- **Not responsive.** 0 `LayoutBuilder`, 0 breakpoints, despite a shipped Windows target. Phone
  layouts are stretched across desktop widths. `phase16_responsive_test.dart` does not test this —
  its assertions are `find.text('Create Backup')` and `find.byType(SingleChildScrollView)`, which
  pass at any window size, so the suite gives false assurance on exactly this point.

**Credit where due:** `SafeArea` usage is asserted by test, empty states exist (11), error copy is
centralised and tested (`remote_error_copy.dart` + `remote_error_copy_test.dart`), and onboarding
has purpose-built security badges (`onboarding_security_badges.dart`, with tests).

### UX

- **Loading is uniformly spinner-based** — 24 indicators, 2 `RefreshIndicator`s in the whole client.
  No optimistic skeletons, no progressive disclosure.
- **Feedback is snackbar-heavy** — 49 `ScaffoldMessenger` call sites. Transient toasts are a poor
  fit for failures the user must act on (send failure, key change).
- **Text scaling capped at 1.3×** (MED-5) — a real user-facing limitation with a documented cause.
- **No deep linking.** Two `intent-filter`s, both `MAIN`/`LAUNCHER`. Invite links, call links
  (`call_link_sheet.dart`), and group join links must be copy-pasted manually.
- **Offline behaviour is designed** — `_BootState.offline`, a sync outbox, a redacted outbox status
  banner (`conversation_list_screen.dart:951`), and a connectivity subscription (`main.dart:648`).
  One of the better-handled UX areas.
- **Keyboard navigation** is untested and unlikely to work well on the Windows build: no
  `Shortcuts`, `Actions`, or `FocusTraversal` usage.
- **Screen-reader support is effectively absent** (MED-5).

---

## 20. Dependency Audit

23 direct dependencies in `app/`, 6 in `admin/`, 10 in `backend/`, resolved through the
`helix_remote_workspace`. Currency data below was obtained from the pub.dev API on the audit date.

| Package | Declared | Status | Action |
|---|---|---|---|
| `file_picker` | `^12.0.0-beta.5` | **Pre-release ahead of the 11.0.3 stable line; already drifted to beta.7** | Pin exactly or move to 11.x stable (MED-7) |
| `flutter_local_notifications` | `^18.0.0` | **4 majors behind (22.2.0)** | Upgrade — notification path of a messaging app |
| `flutter_contacts` | `^1.1.9+2` | 1 major behind (2.3.1) | Upgrade |
| `connectivity_plus` | `^6.1.3` | 1 major behind (7.3.1) | Upgrade |
| `cryptography_flutter` | `^2.0.0` | Behind 2.3.4 | Upgrade — crypto dependency, keep current |
| `mobile_scanner` | `^7.2.0` | Behind 7.4.0 | Routine |
| `flutter_webrtc` | `^1.5.1` | Behind 1.6.0 | Routine, but largest native surface — upgrade with a dedicated test pass |
| `path_provider` | `^2.1.6` | Current | None |
| `flutter_secure_storage`, `share_plus`, `qr_flutter`, `crypto`, `cryptography`, `path`, `sqlite3` | — | Consistent across the workspace | None |
| `googleapis_auth ^1.6.0` (backend) | — | Justified in a comment: RSA signing for FCM JWTs is unavailable in `package:crypto`/`package:cryptography` on the VM | Keep |

**Unused packages:** none detectable by static reading — every declared dependency has at least one
import. Confirm with `dart pub deps` once a toolchain is available.

**Missing:** no lockfile (HIGH-4), no vulnerability scanner, no license audit, no SBOM (MED-12).

---

## 21. Technical Debt

| Debt | Size | Interest rate |
|---|---|---|
| Client has no UI architecture (state, routing, theme, l10n, responsive) | Large | **High** — every new screen deepens it |
| `RemoteCompositionRoot` (2,239 lines) and `RemoteMessagingService` (3,591 lines) | Large | Medium |
| 24 production files over 700 lines | Medium | Medium |
| 45 swallowed exceptions | Medium | Medium — hides the bugs you will hunt later |
| Governance docs asserting non-existent controls | Small | **High** — erodes trust in every other doc |
| No integration tests | Medium | Medium |
| Dependency staleness with no lockfile | Medium | **High** — compounds silently |
| No iOS platform | Large | Low (until it becomes a product requirement) |
| Duplicate helpers, dead `is_admin` claim | Trivial | Low |

---

## 22. Recommended Refactors

1. **Introduce a view-model layer.** Pick one state-management approach and apply it consistently;
   move service calls, pagination, and error mapping out of `State` classes. Do it screen-by-screen,
   starting with `conversation_screen.dart` (which also delivers the MED-1 fix).
2. **Create `packages/helix_remote_ui`.** Design tokens (colour, spacing, typography, radius,
   elevation), theme builders including high-contrast, and common components (empty state, error
   state, skeleton, confirm/destructive dialogs, status badges). Scoped to Helix Remote; the client
   and the admin console may share tokens where it suits them, and need not share layouts.
3. **Split `RemoteCompositionRoot`** into `SessionManager`, `RegistrationCoordinator`,
   `RuntimeSupervisor`, and `SecurityGateway`, each independently constructible and testable.
   Replace `part` with real files and injected interfaces.
4. **Split `RemoteMessagingService`** along its existing seams — sending, crypto, history/receipts,
   conversations, contacts/privacy — into collaborating objects behind one facade.
5. **Introduce a router.** `onGenerateRoute` with route constants at minimum; a declarative router
   if deep linking is wanted (it should be — invite and call links need it).
6. **Add mandatory redaction to `AppLogger`** at the write boundary, where it cannot be bypassed.
7. **Replace `adminAccountIds` with a real capability** (CRIT-1 fix #2).
8. **Centralise auth-failure semantics** — one `AuthFailure` type mapped from 401 only.

---

## 23. Enterprise Readiness Assessment

| Capability | State | Gap |
|---|---|---|
| Production deployment | ⚠️ Partial | Signing enforced and well-guarded; release gate script is broken (MED-10); no obfuscation |
| Large user base | ❌ Not ready | CRIT-1 must be closed first |
| High traffic | ❌ Not ready | SQLite single-writer, in-memory rate limiter, no horizontal scaling path |
| Maintainability | ✅ Good | Docs, ADRs, and comments are a genuine asset |
| Scalability | ❌ Weak | No sharding, no read replicas, no JWT key-rotation window |
| Team collaboration | ✅ Good | Ownership matrices, ADRs, module boundary data, full CI on this product |
| CI/CD | ⚠️ Partial | Format/analyze/test/build on two OSes; no coverage gate, no security scanning, no integration tests, no deploy automation |
| Monitoring | ⚠️ Partial | `/health`, `/ready`, `/metrics` exist and are admin-gated; nothing scrapes them |
| Observability | ❌ Weak | No distributed tracing; correlation IDs are generated (`remote_rest_client.dart:219`) but not propagated to a trace store |
| Crash reporting | ❌ Absent | MED-4 |
| Analytics | ❌ Absent | MED-4 |
| Feature flags | ❌ Absent | Only `globalInstanceMode` and server config rows |
| Environment separation | ✅ Good | Four validated runtime profiles with enforced invariants |
| Configuration management | ✅ Good | `.env.example`, `env_sanitize.dart`, server-config table, `/server/info` publishing limits |
| Disaster recovery | ⚠️ Documented | `DR_DRILL_RUNBOOK.md` and `ROLLBACK_REHEARSAL.md` exist; no evidence of execution |

---

## 24. Phase-by-Phase Implementation Roadmap

All work is inside `helix_remote/` unless a shared file is named explicitly, in which case the change
is written to affect Helix Remote only. Complexity is engineering difficulty; risk is the chance of
introducing a regression.

---

### Phase 0 — Establish the ground truth
**Objective.** Make the product measurable before changing it. Nothing in this audit was verified by
running anything; that must not remain true.

**Tasks**
1. Stand up a toolchain (Flutter stable matching `sdk: ^3.12.0`) and run `scripts/verify.sh` end to
   end; record the true analyzer and test baseline.
2. Commit `helix_remote/pubspec.lock` (**HIGH-4**) and add a `pub get --enforce-lockfile` step to the
   two Helix Remote CI jobs.
3. Add coverage collection to the Helix Remote jobs with a **non-blocking** initial report; publish
   the number (**MED-12**).
4. Fix `scripts/remote_release_gate.ps1` (**MED-10**) and execute it once.

**Files.** `.github/workflows/ci.yml` (Helix Remote jobs only), `helix_remote/pubspec.lock`,
`helix_remote/scripts/*`
**Complexity** Low · **Risk** Low · **Dependencies** none
**Success criteria.** A published coverage baseline and a release gate that runs.
**Do this first — Phases 1+ need a working test loop.**

---

### Phase 1 — Critical security fixes
**Objective.** Close the two issues that make the current deployment unsafe.

| # | Task | Files | Complexity | Risk |
|---|---|---|---|---|
| 1.1 | Reserve account-ID namespace + enforce UUID format (**CRIT-1** fix 1) | `backend/lib/src/modules/auth/registration.dart` | Low | Low |
| 1.2 | Replace `adminAccountIds` with a real admin capability (**CRIT-1** fix 2) | `server_impl.dart`, `operability.dart`, `privacy_compliance.dart`, `contacts.dart`, `migrations.dart` | Medium | Medium |
| 1.3 | Startup guard rejecting an existing reserved-ID account (**CRIT-1** fix 3) | `bin/server.dart`, `migrations.dart` | Low | Low |
| 1.4 | Reject refresh tokens at both auth boundaries (**CRIT-2**) | `server_impl.dart:500`, `websocket.dart:170` | Low | **Medium** — mis-implementation locks every client out |
| 1.5 | Require `exp`; constant-time signature compare (**MED-3**) | `jwt.dart:52,76` | Low | Low |
| 1.6 | Constant-time admin-token compare | `server_impl.dart:442-450` | Low | Low |

**Success criteria.** New tests prove: `account_id: "admin"` is rejected; a refresh token returns 401
on `/ops/*`, on a normal REST route, and on WS upgrade; an `exp`-less token is rejected; a
self-registered account cannot reach any admin route.
**Order.** 1.1 → 1.3 → 1.2 → 1.4 → 1.5 → 1.6. Deploy 1.1/1.3 immediately — they are the cheapest
possible stop-gap for CRIT-1 while 1.2 is built.

---

### Phase 2 — Critical bug and data-exposure fixes
**Objective.** Stop leaking user data through channels the threat model already forbids.

| # | Task | Files | Complexity | Risk |
|---|---|---|---|---|
| 2.1 | Redaction at the log write boundary (**HIGH-1**) | `app/lib/services/app_logger.dart` | Medium | Low |
| 2.2 | Truncate `RemoteRestException.message`; stop logging raw bodies | `app/lib/app/remote_rest_client.dart:155-165` | Low | Low |
| 2.3 | `FLAG_SECURE` on sensitive screens (**HIGH-2**) | `MainActivity.kt`, new Dart channel, conversation/backup/QR screens | Medium | Low |
| 2.4 | `allowBackup=false` + `dataExtractionRules` (**HIGH-3**) | `app/android/app/src/main/AndroidManifest.xml` | Low | Low |
| 2.5 | 401/403 split, server and client (**HIGH-5**) | `server_impl.dart:501`, `remote_rest_client.dart:179` | Medium | **Medium** — must ship server-first |
| 2.6 | Move `invite_code` out of the query string (**LOW-3**) | `remote_rest_client.dart:294`, `auth/invites.dart` | Low | Low |
| 2.7 | Triage 45 silent catches; log-or-rethrow (**MED-11**) | `helix_remote/**` | Medium | Medium |

**Success criteria.** A test feeding a token, phone number, and error body through `AppLogger` asserts
none survive. Manual check: recents thumbnail is blank. A permission denial performs zero token
rotations.

---

### Phase 3 — Architecture refactoring
**Objective.** Give the client an architecture proportionate to its size.

**Tasks**
1. Choose and adopt a state-management approach; establish the view-model pattern on one screen first.
2. Migrate `conversation_screen.dart` — carries the MED-1 fix (delta-apply instead of full reload).
3. Migrate the remaining large screens: `conversation_list_screen`, `calls_tab_screen`,
   `contact_info_screen`, `settings_screen`, `groups_screen`.
4. Split `RemoteCompositionRoot` (2,239 lines) into four injectable collaborators.
5. Split `RemoteMessagingService` (3,591 lines) along its existing part seams.
6. Introduce `onGenerateRoute` + route constants; extract routing out of `main.dart`.
7. Reduce `main.dart` from 1,588 lines to a bootstrap shell; collapse the three `MaterialApp`s to one.
8. Remove duplicate helpers and the dead `is_admin` claim (**LOW-2**).

**Files.** `helix_remote/app/lib/**`
**Complexity** High · **Risk** **High** — the largest regression surface in the programme
**Dependencies.** Phases 0–2. **Do not start before coverage exists on these screens.**
**Success criteria.** No production file over 700 lines in `app/lib`; no screen calls a service
directly; coverage on migrated screens does not drop.
**Order.** 1 → 2 → 4 → 5 → 3 → 6 → 7 → 8. Screen migration follows the service split so view-models
bind to stable interfaces.

---

### Phase 4 — Performance optimization
**Objective.** Remove the quadratic path and establish measurement.

**Tasks**
1. Delta-apply message changes (**MED-1 / P-1**) — folded into Phase 3.2 if sequenced together.
2. Convert the growth-bearing non-lazy `ListView`s (**P-2**) — calls tab, device management.
3. Rewrite log purge as a streaming tail; batch appends (**P-3, P-4**).
4. Scope contacts-change rebuilds to the affected contact (**P-5**).
5. Add `prefer_const_constructors` and `prefer_const_literals_to_create_immutables` to
   `helix_remote/analysis_options.yaml`; fix the fallout (**P-6**).
6. Wire `PERFORMANCE_BUDGETS.md` to a CI job asserting startup time and frame budgets on a reference
   device.

**Complexity** Medium · **Risk** Low · **Dependencies** Phase 3 for task 1
**Success criteria.** Sustained 60fps in a 1,000-message conversation under a 20-message burst; p95
cold start within the documented budget; budgets enforced in CI.

---

### Phase 5 — UI modernization
**Objective.** Give Helix Remote its own coherent visual identity, expressed as code.

**Tasks**
1. Create `packages/helix_remote_ui`: colour/spacing/typography/radius/elevation tokens, and light,
   dark, and high-contrast theme builders.
2. Migrate the client onto it; delete both inline `ThemeData` blocks in `main.dart`. Adopt tokens in
   the admin console where they suit an operator tool.
3. Replace 194 hardcoded colours and 134 inline `EdgeInsets` with tokens.
4. Build the component set: empty state, error state, **skeleton loaders**, async panel,
   confirm/destructive dialogs, status badges.
5. Replace the 24 bare `CircularProgressIndicator`s with skeletons where content shape is known.
6. Establish button hierarchy (filled/tonal/outlined/text) and apply it consistently.
7. Add motion: page transitions, list item animations, `Hero` on avatars.
8. Introduce responsive breakpoints and `LayoutBuilder`; build real tablet and desktop layouts
   (master-detail for conversations) — and replace `phase16_responsive_test.dart`'s width-insensitive
   assertions with tests that actually vary the surface size.

**Complexity** High · **Risk** Medium · **Dependencies** Phase 3
**Success criteria.** Zero hardcoded colours outside `helix_remote_ui`; a documented component
gallery; screenshot tests at phone, tablet, and desktop widths.

---

### Phase 6 — UX improvements
**Objective.** Move from functional to polished.

**Tasks**
1. Deep linking for invite, call, and group-join links, with `intent-filter`s and Windows URI
   registration.
2. Replace transient snackbars with persistent, actionable surfaces for failures needing user action.
3. Real empty states with a primary action on every list.
4. Pull-to-refresh on every refreshable surface (currently 2 in the whole client).
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
1. **Remove the 1.3× text-scale cap** (`main.dart:32-40`) — depends on Phase 5's responsive layouts,
   which is the whole reason the cap exists.
2. `Semantics` on every interactive and status element (from 1 → full coverage).
3. Tooltips/labels on all 49 `IconButton`s.
4. Verify 4.5:1 contrast across both themes; keep high-contrast themes on the unified shell.
5. Enforce 48×48dp minimum touch targets.
6. Screen-reader passes: TalkBack (Android), Narrator (Windows).
7. Focus order and visible focus indicators.
8. Add `flutter_test` accessibility guideline assertions (`meetsGuideline(textContrastGuideline)`,
   `androidTapTargetGuideline`) to widget tests.
9. Apply the same pass to the admin console, which currently has zero `Semantics`.

**Complexity** Medium · **Risk** Low · **Dependencies** Phase 5
**Success criteria.** Automated guideline assertions pass on all screens; usable at 2× text scale; a
documented manual screen-reader pass.

---

### Phase 8 — Testing
**Objective.** Make regressions expensive to ship.

**Tasks**
1. Create `app/integration_test/` and `admin/integration_test/` — currently **zero** exist. Cover:
   registration, send/receive, attachment round-trip, call setup, backup/restore, device linking.
2. Add coverage thresholds to CI — start at the Phase 0 baseline, ratchet upward.
3. Golden tests for the `helix_remote_ui` component gallery.
4. Property/fuzz testing beyond the existing scheduled seed corpus.
5. Load-test the backend; establish the concurrency ceiling before SQLite becomes the bottleneck.
6. Security regression suite: one test per finding in this document.

**Complexity** High · **Risk** Low · **Dependencies** Phases 1–5
**Success criteria.** Integration suite green in CI; coverage ratchet enforced; every Critical/High
finding has a named failing-before/passing-after test.

---

### Phase 9 — Production hardening
**Objective.** Make the system operable at scale.

**Tasks**
1. Opt-in, redacted crash reporting and minimal analytics (**MED-4**) — with an explicit privacy
   decision recorded in an ADR.
2. Persistent, shared rate limiting (**MED-6**) — survives restart, works across processes.
3. JWT key rotation with an overlap window (multiple `kid`s accepted, one used for signing).
4. Scoped, expiring, rotatable admin credentials replacing the static bearer token; MFA on the admin
   console.
5. Database scaling decision: PostgreSQL migration, or a documented and enforced SQLite ceiling.
6. Release obfuscation, R8, resource shrinking, symbol upload (**LOW-1**).
7. Feature-flag infrastructure.
8. Dependency vulnerability scanning + SBOM in CI (**MED-12**).
9. Distributed tracing propagating the existing correlation IDs.
10. Certificate pinning for the known Helix Global host, with a documented rotation procedure.
11. Execute the DR drill and rollback rehearsal; record evidence.

**Complexity** High · **Risk** Medium · **Dependencies** Phases 1–8
**Success criteria.** Crash-free-session rate observable; rate limits survive restart; keys rotatable
with zero forced logouts; a load-tested and documented capacity number.

---

### Phase 10 — Final polish
**Objective.** Close the long tail.

**Tasks**
1. Localization — extract the 274 hardcoded strings; `flutter_localizations` is already a declared
   dependency with nothing behind it.
2. Resolve the iOS decision (**LOW-5**) — build it or record the exclusion in an ADR.
3. Reconcile every Helix Remote governance document against the code (**MED-9** and §21) and add a CI
   check that fails when a doc asserts an unimplemented control.
4. Complete the dependency upgrades (**MED-7, MED-8**), retiring the pre-release pin.
5. Remove unused Android permissions (**LOW-4**).
6. Final external penetration test and cryptographic review against
   `EXTERNAL_SECURITY_REVIEW_GATE.md`.

**Complexity** Medium · **Risk** Low · **Dependencies** all prior phases

---

## 25. Estimated Timeline

Assumes 2 senior Flutter engineers, 1 backend engineer, 1 designer (Phases 5–7), 1 QA (Phase 8+).

| Phase | Duration | Cumulative |
|---|---|---|
| 0 — Ground truth | 0.5 week | 0.5 wk |
| 1 — Critical security | 1–1.5 weeks | 2 wks |
| 2 — Bugs & data exposure | 2 weeks | 4 wks |
| 3 — Architecture | 4–6 weeks | 10 wks |
| 4 — Performance | 2 weeks | 12 wks |
| 5 — UI modernization | 4–5 weeks | 17 wks |
| 6 — UX | 3 weeks | 20 wks |
| 7 — Accessibility | 2 weeks | 22 wks |
| 8 — Testing | 3 weeks (overlaps 5–7) | 22.5 wks |
| 9 — Production hardening | 4 weeks | 26.5 wks |
| 10 — Final polish | 2 weeks | **28.5 wks (~6.5 months)** |

**Critical path to a safe deployment: Phases 0–2 ≈ 4 weeks.** Phases 1 and 2 can ship to production
independently of everything after them, and should.

---

## 26. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| CRIT-1 exploited before the fix ships | Medium | **Critical** | Deploy tasks 1.1/1.3 within days — both are small and independent. Audit existing accounts for reserved IDs *now*. |
| CRIT-2 fix locks out all clients | Low | High | Roll out behind a config flag that logs-but-allows first, then enforces once telemetry shows no `token_type`-less traffic. |
| Phase 3 refactor regresses messaging | **High** | High | Do not start before Phase 0 coverage exists. One screen per PR. Keep the old path behind a flag for one release. |
| 401/403 change breaks older clients | Medium | Medium | Server first; keep 403 accepted client-side for two releases before narrowing. |
| State-management migration stalls half-done | Medium | Medium | Timebox per screen; a mixed codebase is acceptable if each screen is internally consistent. |
| Committing a lockfile surfaces breaking transitive updates | Medium | Medium | Commit the lockfile at the currently-working resolution, then upgrade deliberately in Phase 10.4. |
| `flutter_local_notifications` 18→22 breaks the notification path | **High** | Medium | Four majors is a migration, not a bump. Do it alone, with a dedicated device test matrix, not bundled with other upgrades. |
| Design system rewrite outruns the roadmap | Medium | Medium | Ship tokens and themes first (immediate consistency win), components incrementally. |
| SQLite becomes the ceiling before Phase 9 | Medium | High | Load-test in Phase 8, not Phase 9 — the answer changes the Phase 9 plan. |

---

## 27. Final Recommendations

**Do this week.**
1. **Audit production for an account with `account_id = "admin"`.** If one exists that you did not
   create, treat it as an active compromise. This is the single most urgent action in this document.
2. Ship CRIT-1 tasks 1.1 and 1.3 — a reserved-name check and a startup guard, both small.
3. Ship CRIT-2 — two lines in two files.
4. Set `allowBackup="false"`. One attribute, one file.

**Do this month.** Phases 0–2 in full. After that Helix Remote is *safe* to run, even though it is
not yet *polished*.

**Then choose deliberately.** Phases 3–10 are a genuine 6-month programme. Three framing points:

- **The security core is worth protecting.** The crypto, the relay-only ICE policy, the signed
  registration transcripts, the rotation-with-replay-detection design — this is thoughtful work by
  people who understood the problem. Every failure found here is at the *boundaries* around that
  core, not in it. That is the good kind of security debt: localised and fixable.

- **The backend and the client are at different levels of maturity, and the gap is the plan.** The
  backend has interfaces, bounded contexts, injectable dependencies, and 415 tests; the client has
  208 `setState` calls and three `MaterialApp`s. Phases 3, 5, 6, and 7 exist almost entirely to
  bring the client up to the standard the backend already sets. Sequence them in that order —
  architecture before design system before UX before accessibility — because each genuinely depends
  on the one before it. Attempting the visual work first produces polish sitting on a structure that
  cannot support it, and the 1.3× text-scale cap is exactly what that looks like.

- **The documentation estate is an asset that is currently decaying.** Sixteen ADRs, a threat model,
  a privacy claim matrix, performance budgets — and at least three documents asserting controls the
  code does not implement. Docs that describe reality accelerate a team; docs that describe
  intentions mislead auditors and new engineers alike. The CI check in Phase 10.3 is cheap; consider
  pulling it forward.

**One thing to reconsider outright.** The 1.3× text-scale cap is a decision to trade an accessibility
guarantee for layout convenience. It is documented honestly in the code, which is to the team's
credit — but it should be treated as a temporary defect with a removal date (Phase 7.1), not a design
choice.

---

*Analysis complete. Scoped to `helix_remote/`; no work is proposed in `helix_local/`. No code changes
have been made. Implementation should begin with Phase 0.*
