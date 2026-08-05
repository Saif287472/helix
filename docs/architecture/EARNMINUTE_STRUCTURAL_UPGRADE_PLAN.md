# Structural Upgrade Plan — Lessons from EarnMinute

Status: Planning only. No code changed by this document.
Source: [`docs/architecture/external-references/EarnMinute_PROJECT_ARCHITECTURE.md`](external-references/EarnMinute_PROJECT_ARCHITECTURE.md)
Date: 2026-08-04

## Method

EarnMinute (Node/Express + React, MongoDB) and Helix (Dart/Shelf backend +
Flutter apps, SQLite/Postgres) are different stacks, so nothing below was
copied blind. Each EarnMinute pattern was checked against what actually
exists in this repo right now — not against the aspirational
`packages/apps/services` layout described in
[`PROJECT_STRUCTURE.md`](PROJECT_STRUCTURE.md) and
[`CURRENT_STATE_2026-06-20.md`](CURRENT_STATE_2026-06-20.md), which describe a
multi-package split that the repo does not currently have (actual root is
just `helix_local/` and `helix_remote/`, each a single Flutter/Dart workspace
with an internal `packages/` folder). Evidence below is from the live tree.

Verdicts:

- **Adopt** — real gap, evidence found, worth doing.
- **Already covered** — Helix has an equivalent or stronger mechanism.
- **Not applicable** — solves a problem specific to EarnMinute's stack that
  doesn't exist in Dart/Flutter.

---

## A. Adopt

### A1. Centralized error format for the Remote backend

**Evidence of the gap:** `helix_remote/backend/lib/src/modules/*.dart`
constructs ad-hoc `Response(...)` / `jsonEncode({'error': ...})` bodies
inline — **350 occurrences across 16 files** (heaviest: `groups.dart` 94,
`messaging.dart` 43, `contacts.dart` 46, `s2s_module.dart` 19). Shapes are
inconsistent (`{'error': 'Unauthorized'}` vs whatever each handler decided
that day). Separately, four unrelated one-off exception classes exist
(`FederationHttpException`, `FcmTokenNotFoundException`,
`FcmDeliveryException`, `SmsDeliveryException`) with no shared base and no
machine-readable error codes for the client to branch on.

**What EarnMinute does:** one `AppError` class (statusCode, code, details,
`.withCode()`), a frozen `ERROR_CODES` enum, and a single
`errorMiddleware.js` that normalizes every error type (framework errors,
validation errors, custom errors) into one `{success, message, code,
details?}` JSON shape. Every handler just throws; the response shape is
never reinvented per-route.

**Plan:**
1. Add `lib/src/app_error.dart` to the backend: one `AppError` class
   (message, statusCode, code, details) plus a `RemoteErrorCode` enum
   covering the cases already implicit in the 350 sites above
   (`unauthorized`, `not_a_member`, `invalid_envelope`, `validation_error`,
   `internal_error`, etc.).
2. Add one Shelf middleware (alongside the existing
   `_requestLogMiddleware`/`_rateLimitMiddleware` in `server_impl.dart`) that
   catches `AppError` (and unhandled exceptions) once and emits the
   normalized JSON body — instead of each module building `Response(...)`
   directly.
3. Migrate module-by-module (start with `messaging.dart` and `groups.dart`,
   the two heaviest), replacing inline `jsonEncode({'error': ...})` with
   `throw AppError(...)`. This can land incrementally — old and new styles
   can coexist during migration since the middleware only intercepts thrown
   errors.
4. Fold `FederationHttpException`, `FcmTokenNotFoundException`,
   `FcmDeliveryException`, `SmsDeliveryException` into `AppError` subtypes or
   have the middleware translate them, so there is one exit shape.

**Why it's worth it:** the Remote app already parses error bodies to decide
UI behavior in places; an inconsistent shape is a standing source of subtle
client bugs, and every new route currently has to guess the response format
by imitating whichever neighboring handler it copies from.

**Risk:** low. Purely additive (new middleware + new error type); existing
routes keep working until migrated. No protocol/wire format changes to
externally-documented success responses.

---

### A2. Fail-fast startup environment validation

**Evidence of the gap:** `helix_remote/backend/bin/server.dart` only
hard-fails on one variable (`HELIX_REMOTE_JWT_SECRET` — line 50-53, `exit(1)`
with a single-line message). Every other credential (SMS API key/sender ID,
FCM project/token, TURN URL/secret, attachments dir) is read with `?? ''`
and silently becomes an inert empty string if missing — the comments in the
file even say "optional but required for X" next to each one, i.e. the
author already knows these are conditionally-required and there's no
mechanism enforcing it. A production deploy with a typo'd env var name fails
silently at first use (e.g., a failed SMS send at OTP time) instead of at
boot.

**What EarnMinute does:** `validateEnv.js` runs once after `dotenv.config()`
with an `ALWAYS_REQUIRED` list and a `CONDITIONAL` list of `{when, label,
vars}` entries keyed off feature flags (e.g. `PAYMENT_PROVIDER=sslcommerz`
pulls in payment secrets only when that provider is selected). Missing vars
print one boxed, readable list of everything missing and `exit(1)` — never a
partial start.

**Plan:**
1. Add `lib/src/startup_env.dart` with two lists mirroring the pattern:
   `alwaysRequired` (`HELIX_REMOTE_JWT_SECRET`, `HELIX_REMOTE_DB_PATH`, ...)
   and `conditional` entries such as: SMS vars required only when
   `HELIX_REMOTE_SMS_API_KEY` or sender ID is partially set (fail if one is
   present and the other isn't, rather than silently sending with a blank
   sender ID); FCM vars required together; TURN vars required together.
2. Call it at the very top of `main()` in `bin/server.dart`, before the
   current ad-hoc checks, printing every missing/inconsistent var at once and
   `exit(1)`.
3. Reuse the existing `sanitizeEnvValue` from `env_sanitize.dart` inside the
   validator so quoting/CRLF issues are caught at boot, not discovered later
   as "the SMS sender ID silently doesn't match."

**Why it's worth it:** this is the single highest-leverage, lowest-risk item
on this list — it converts a class of "worked in dev, silently broken in
prod" bugs into a boot-time crash with a readable message, which is exactly
the coturn/nginx-header-shaped incidents already logged in project memory
(silent misconfiguration reaching production undetected).

**Risk:** very low. Pure startup-time addition; doesn't change runtime
behavior for a correctly-configured deployment.

---

### A3. Split the largest backend "god" modules into layers

**Evidence of the gap:** line counts in `helix_remote/backend/lib/src/modules/`:

| File | Lines |
|---|---|
| `groups.dart` | 2005 |
| `calls.dart` | 1403 |
| `messaging.dart` | 919 |
| `operability.dart` | 860 |
| `contacts.dart` | 825 |
| `s2s_module.dart` | 712 |

`groups.dart` alone is more than double EarnMinute's single largest file
(`ChatWindowEnhanced.jsx`, 847 lines) — and unlike that file (a UI component
for a genuinely complex feature), `groups.dart` mixes routing, business
logic, and validation for one backend module in a single file. `auth/` is
the one module in this codebase already split into focused files
(`registration.dart`, `refresh.dart`, `profile.dart`, `phone_otp.dart`,
`challenge_login.dart`, `invites.dart`, `devices.dart`) — proving the split
pattern is already known and working here, just not applied to the other
modules.

**What EarnMinute does:** every module is exactly four files —
`Routes.js` (wiring only) → `Controller.js` (thin HTTP handling) →
`Service.js` (business logic, source of truth) → `Validation.js` — plus an
`index.js` barrel and a `MODULE.md`.

**Plan (apply the `auth/` split to the two worst offenders first):**
1. `groups.dart` → `groups/routes.dart`, `groups/service.dart`,
   `groups/validation.dart` (and further split by sub-feature if the service
   file is still large after extraction — e.g. membership vs. admin actions).
2. `calls.dart` → same three-way split.
3. Re-evaluate `operability.dart`, `contacts.dart`, `s2s_module.dart` after
   the first two prove the pattern out.
4. Do **not** attempt all six at once — this is a mechanical but
   change-heavy refactor touching security-sensitive code
   (`docs/ai/AI_GUARDRAILS.md` flags group admin rules and trust rules as
   non-negotiable protections); each split should land as its own reviewed
   change with the existing test suite as the safety net, not a single sweep.

**Why it's worth it:** smaller, single-concern files reduce how much an
agent (or a human) has to load to make one correct edit, and match the
file-size discipline this repo already enforces via `analysis_options.yaml`
and the boundary tooling everywhere else.

**Risk:** medium. This is a real refactor of live, security-relevant code
(groups touch admin/trust rules; calls touch the group-call SFU work in
[`adr_group_calls.md`](adr_group_calls.md)). Should go through the normal
verification pipeline (`scripts/verify.ps1`) per-file, not in bulk.

---

### A4. Per-module `MODULE.md` contracts

**Evidence of the gap:** no `MODULE.md` (or equivalent) exists anywhere in
the repo. Helix documents architecture extremely well at the *macro* level
(ADRs, `CURRENT_STATE` evidence ledger, `docs/ai/AI_GUARDRAILS.md`,
`docs/ai/ownership-blast-radius.yaml`) but nothing documents an individual
backend module's or package's public surface at the *micro* level — an
agent has to open `groups.dart` cold to learn its routes, or open a
package's `pubspec.yaml` to learn its dependencies.

**What EarnMinute does:** one `MODULE.md` per module (11 backend + 11
frontend) documenting Purpose, Owned Files, a full Route table
(method/path/auth/role), Dependencies (exact import paths), and gotcha Notes
(e.g. "this callback is registered in two places and here's why").

**Plan:**
1. Add one `MODULE.md` per backend module directory
   (`lib/src/modules/<name>/MODULE.md` or, for the still-flat modules, a
   sibling `<name>.module.md`) with: purpose, route table, dependencies
   (which repositories/services it touches), and known gotchas — the kind of
   thing currently living only in a maintainer's head or scattered in
   `bug_fix.md` / `milestones_plan.md`.
2. Add one per internal package (`helix_remote_domain`,
   `helix_remote_calls`, `helix_remote_crypto`, etc.) describing its public
   exports and which packages/apps are allowed to depend on it — this
   restates `module_boundaries.json` rules in human-readable prose next to
   the code, not just in the enforcement config.
3. Do this only for modules touched during A1–A3 work first, rather than a
   one-shot documentation sprint — write the `MODULE.md` for a module at the
   same time it's being split/touched, so the doc reflects the current file
   layout instead of drifting immediately.

**Why it's worth it:** pairs directly with the extraction tooling already in
`tool/extract_*.dart` (see A5) — a `MODULE.md` is what an agent reads first
after pulling an extracted bundle, instead of inferring structure from raw
source.

**Risk:** none — documentation only.

---

### A5. Make the AI-context extraction tool per-module, not per-bundle

**Evidence of the gap:** `helix_remote/tool/extract_02_backend_modules.dart`
(and siblings `extract_01`…`extract_06`, plus `extract_all.dart`) already
implements EarnMinute's "extract a scoped context bundle" idea — this is
**not missing**, it's already built. But it bundles *all* backend modules
into one dump (`docs/codebase/remote_2_backend_modules.txt`, currently
~8,700 combined lines across all 12 modules) rather than one bundle per
feature the way EarnMinute's `extract-module.js <module>` does. Someone
working only on `messaging` still has to generate/read a file containing
`groups.dart` (2005 lines) and everything else.

**Plan:**
1. Add a parameterized extractor (e.g. `extract_module.dart <name>`) that
   collects just `lib/src/modules/<name>/` (or `<name>.dart` for the
   still-flat ones) plus a small fixed list of shared files
   (`app_error.dart` once A1 lands, `jwt.dart`, `repositories.dart`),
   mirroring EarnMinute's `scripts/extract-module.js` fixed-shared-files
   list.
2. Keep the existing numbered bundles (`extract_01`…`extract_06`) for
   whole-subsystem context — they're still useful for onboarding or
   cross-module review — but stop treating "backend modules" as one
   unsplittable unit for single-feature work.
3. Sequence this after A3: once `groups.dart`/`calls.dart` are split into
   subfolders, the per-module extractor has a real folder to point at
   instead of a single oversized file.

**Why it's worth it:** directly reduces tokens/context loaded for
single-feature changes, which is the exact stated purpose of the existing
`extract_*.dart` tools — this closes the gap between the tool's intent and
its current bundle granularity.

**Risk:** none — new script, doesn't touch existing extractors.

---

### A6. State + transition + validator triads for the riskiest lifecycles

**Evidence of the gap:** state enums exist but are scattered and
un-validated centrally: `CallRoomStatus`, `RsvpStatus`
(`helix_remote_domain/lib/domain/group_call.dart`), `GroupCallStatus`
(`helix_remote_calls/lib/src/remote_group_call_service.dart`),
`RemoteCallState` (`remote_call_service.dart`),
`RemoteCallEngineConnectionState` (`call_engine.dart`). Only one file in the
entire repo (`remote_status.dart`) matches a transition-table pattern; the
rest rely on conditionals wherever the enum is read. `CURRENT_STATE_2026-06-20.md`
already flags exactly these lifecycles as fragile — Remote calls
"Component-only", Remote groups "Defective" (deterministic fallback key
behavior), Remote crypto sessions "Defective" — i.e. this isn't a
theoretical nice-to-have, it targets areas already logged as broken or
unproven.

**What EarnMinute does:** each stateful entity (Task, Escrow, and a third
for payment providers) gets exactly three files — `<entity>States.js`
(frozen enum), `<entity>Transitions.js` (frozen adjacency map), and
`<entity>Validator.js` (`assert<Entity>Transition` — throws instead of
letting an illegal transition happen). Every state check in the codebase
goes through the validator; the pattern is documented as intentionally
copy-pasteable across three different entities.

**Plan:**
1. Pick the single highest-value candidate first — the group-call lifecycle
   (`CallRoomStatus`: waiting → active → ended, `GroupCallStatus`: idle →
   joining → active → ended) — since group calls are explicitly upcoming
   work per [`adr_group_calls.md`](adr_group_calls.md).
2. Add `call_room_transitions.dart` (frozen adjacency map: which status may
   follow which) and a validator function that throws a typed error
   (composable with A1's `AppError`) instead of allowing a silent/ad-hoc
   status write.
3. Once proven on one lifecycle, apply the same triad to the outbox/sync
   delivery states and the Remote call (1:1) states — do **not** do all
   state machines in one pass; this is exactly the kind of "small, exact
   edits" constraint `docs/ai/AI_GUARDRAILS.md` already asks for.

**Why it's worth it:** this is the one EarnMinute pattern that maps directly
onto lifecycles this repo's own evidence ledger already calls out as
defective — it's not just structural tidiness, it's a mechanism to prevent
the specific class of bug already logged against groups/calls.

**Risk:** medium — touches call/group state that is live, tested
functionality. Should land as narrow, single-lifecycle changes with full
test coverage, per lifecycle, not a blanket sweep.

---

## B. Already covered — do not duplicate

| EarnMinute pattern | Helix equivalent | Why Helix's version stands |
|---|---|---|
| Modular monolith, `modules/` folder per feature | `backend/lib/src/modules/`, `packages/*` | Helix additionally enforces boundaries at **compile time** via `module_boundaries.json` + `tool/check_boundaries.dart` (see [module_boundaries.json](module_boundaries.json)); EarnMinute's equivalent rule ("cross-module imports only via index.js") is convention-only, unenforced by tooling. |
| `domain/` — pure, I/O-free state/permission logic | `helix_remote_domain`, `helix_local_domain` packages | Domain logic is a **separately versioned package**, not just a folder — importing infrastructure into it is a build-breaking boundary violation, not a lint suggestion. |
| `repositories/` — one file per model, DB access isolated | `lib/src/repositories.dart` (interface-based: `AccountRepository`, `MessageRepository`, `OperationalRetentionRepository`) | Same isolation principle already applied; at 89 lines for 3 repositories there's no size pressure to split into one-file-per-model yet. Revisit only if this file grows past ~200-300 lines. |
| Barrel `index.js`, "never import module internals directly" | Dart package system (`package:helix_remote_domain/...` import paths) + `module_boundaries.json` | Dart packages already have a single public surface by construction; Helix's boundary file goes further by also forbidding specific *cross-product* imports (Local ↔ Remote), which EarnMinute's barrel convention doesn't address at all. |
| AI-oriented onboarding doc + "don't break working flows" dev constraints | `docs/ai/AI_GUARDRAILS.md` + `docs/ai/ownership-blast-radius.yaml` | Helix's version is structured/machine-checkable (named non-negotiables, required verification command, risk-reporting trigger tied to a blast-radius file) versus EarnMinute's prose section in `Project_Details.txt`. |
| `scripts/extract-module.js` — AI context bundle generator | `helix_remote/tool/extract_01..06_*.dart`, `extract_all.dart` | Concept already implemented. Only the granularity differs — see **A5**, which is a refinement, not a net-new build. |
| Lightweight, dependency-free test runner | 40 files in `backend/test/`, `docs/quality/RISK_BASED_COVERAGE.md`, `docs/quality/RELEASE_TEST_PYRAMID.md` | Helix's test discipline (risk-based coverage reporting, a documented test pyramid) is more mature than EarnMinute's plain `node --test` setup — nothing to import here. |
| MongoDB transactions around multi-document writes | Outbox/sync atomicity | Per project memory, atomic sync was one of the defects fixed in the Phase 9-11 closure. The underlying principle (wrap multi-row writes in a transaction) is already applied where it mattered; no open gap identified during this review. |
| Legacy routes/controllers kept as compatibility shims during migration | Helix's phase-by-phase ADR/closure-doc discipline | Same incremental-migration philosophy, already the norm here (see `docs/architecture/CURRENT_STATE_2026-06-20.md`'s Verified/Component-only/Defective classification, which exists precisely to avoid big-bang rewrites). |

---

## C. Not applicable — different stack

- **Zod validation middleware, `express-validator`** — Dart doesn't have an
  equivalent gap the same way; if backend request validation is currently
  inconsistent, that's a candidate for its own review, but it's not a
  structural pattern to "port" from EarnMinute so much as a general
  input-validation audit. Not scoped here.
- **Vite `@` path alias** — solves fragile relative-import chains in a
  bundler; Dart/Flutter package imports are already absolute
  (`package:helix_remote_domain/...`), so this problem doesn't exist here.
- **Frontend `modules/` mirroring backend 1:1 (React)** — Helix's UI layer is
  Flutter, structured around screens/widgets/providers, not a React SPA with
  route-level code-splitting; there's no direct structural analog to import.
- **No ESLint/tsconfig found in EarnMinute (flagged as *their* gap)** —
  inverse case: Helix already has `analysis_options.yaml` with a strict
  baseline enforced repo-wide. Nothing to adopt; if anything this is a place
  Helix is already ahead.

---

## Suggested sequencing

1. **A2** (env validation) — smallest, safest, immediate production-safety
   value.
2. **A1** (centralized error format) — foundational; A6's validators will
   want to throw into this shape.
3. **A4** written incrementally alongside A1/A3 (not a standalone sprint).
4. **A3** (split `groups.dart`, then `calls.dart`) — do one, verify, then the
   next.
5. **A5** (per-module extractor) — natural follow-on once A3 gives it real
   folders to target.
6. **A6** (state/transition/validator triads) — start with group-call
   lifecycle only, expand after it proves out.

Each step should go through `scripts/verify.ps1` individually per the
existing required-checks convention in `docs/ai/AI_GUARDRAILS.md`, not as one
combined change.
