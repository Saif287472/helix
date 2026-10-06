# Audit finding regression matrix

One row per finding in `docs/operations/ENTERPRISE_READINESS_AUDIT_2026-08-06.md` and the remediation
plan, naming the test that reproduces the pre-fix condition and protects the implemented control.

Status: rewritten at Phase X (the v1 backend, storage, sync and groups packages and their tests were
deleted). Every row now points at a **v2** test. The audit and the remediation plan describe the v1
code; where the v1 mechanism does not exist any more, the row says what replaced it.

Paths are relative to `helix_remote/`. `tool/check_governance_controls.dart` checks that every
`.dart` path named in this file exists, so the table cannot quietly come to describe tests that were
renamed or deleted (the section 21 failure mode). It checks the file, not the claim: a row is only as
good as its named test.

Rows in the **Gaps** section have no v2 test. They are listed so the gap is visible here rather than
only in the audit.

## Critical

| Finding | Regression test evidence |
| --- | --- |
| CRIT-1: reserved admin ID / operator console takeover | v2 has no admin account id or `is_admin` capability: the operator is a separate admin credential (Argon2id password, `helix.admin` token audience). `server/test/modules/ops_admin_test.dart` — "metrics need an admin token" (a device token is refused), the accounts group ("device tokens never open admin routes"), first-run setup and lockout; `server/test/modules/identity_test.dart` — "helix names: unique, lowercase pattern, reserved names refused" (staff-like names); `packages/helix_remote_api/test/v2/transport_test.dart` — "a device transport refuses admin routes and S2S routes" |
| CRIT-2: refresh token accepted as access token | Refresh tokens are opaque and stored hashed, not JWTs. `server/test/modules/identity_test.dart` — "refresh rotates; reusing an old refresh token ends the device sessions"; `server/test/platform/token_comparison_test.dart` — a token of the wrong type or audience fails verification; `server/test/modules/realtime_test.dart` — "upgrades need a valid token and the helix subprotocol", "refresh-token reuse closes the socket (theft response)" |

## High

| Finding | Regression test evidence |
| --- | --- |
| HIGH-1: unredacted, persistent, user-shared diagnostic log | The v2 app keeps no diagnostic log file. Server: `server/test/platform/infra_test.dart` — "redaction" (by field name and by value shape), "log lines are JSON with redaction applied"; `server/test/modules/ops_admin_test.dart` — "crash reports need the flag, and are logged redacted". Client: `app/test/architecture_test.dart` — the two logging sites report an exception type only; `packages/helix_remote_api/test/v2/transport_test.dart` — "exceptions never repeat tokens or bodies"; `app/test/settings/a3b_rules_test.dart` — "secrets are not copied, stored or logged by the backup feature"; `server/test/client/engine/cli_test.dart` — the CLI prints no phone number, code, key or password |
| HIGH-2: screenshots and screen recording expose message content | **Accepted, not mitigated (2026-09-30).** Screenshot blocking (FLAG_SECURE / `SetWindowDisplayAffinity`) was removed at the product owner's request because people need to screenshot chats; the recents thumbnail also shows the last screen. `app/test/product_rules_test.dart` — "screenshots are allowed everywhere" keeps it from returning unnoticed, `app/test/settings/a3b_rules_test.dart` — "Settings has no screen-capture control", and `tool/check_governance_controls.dart` asserts the Android and Windows halves are absent |
| HIGH-3: `android:allowBackup` extracts app-private data | `app/test/product_rules_test.dart` — "P8 HIGH-3 Android manifest disables backup and declares extraction rules" |
| HIGH-4: lockfile not committed, builds not reproducible | CI `flutter pub get --enforce-lockfile` on every Helix Remote job in `.github/workflows/ci.yml`, against a pinned Flutter version |
| HIGH-5: 403 overloaded, so every permission denial rotates a refresh token | `packages/helix_remote_api/test/v2/transport_test.dart` — the "refresh" group (a refresh follows only a 401, concurrent 401s refresh once, a refused refresh signs out), "a 401 invalid_credentials is a wrong password, not a rejected token", "client errors are not retried"; `server/test/server_test.dart` — "device routes refuse requests without a session" |

## Medium

| Finding | Regression test evidence |
| --- | --- |
| MED-1: full window re-fetch and re-decrypt per inbound message | A message is decrypted once into rows and lists are drift watch queries. `packages/helix_remote_engine/test/inbound_test.dart` — "a message arrives as one row with its summary and a notice"; `packages/helix_remote_db/test/watch_test.dart`; `packages/helix_remote_db/test/performance_test.dart` — "first page of a 100k-message conversation is fast"; `app/test/performance_budget_test.dart` (1,000-message burst within the CI frame budget, 5,000-item first page); `app/test/chat_performance_test.dart` |
| MED-2: no design system, localization, or responsive layout in the client | `app/test/product_rules_test.dart` — "P5 screens use design tokens, not colour literals", "English only: there is no localization layer", "light theme only"; `packages/helix_remote_ui/test/package_rules_test.dart`. Localization was removed on 2026-09-28: the app is English-only with plain string literals. The phone/tablet/desktop screenshot test has no v2 equivalent, see Gaps |
| MED-3: non-constant-time comparison of JWT signature and admin token | `server/test/platform/token_comparison_test.dart` — comparator correctness on every case `==` would handle, and token verification failing closed; the admin password hash is compared with the same helper (`server/test/modules/ops_admin_test.dart`, sign-in) |
| MED-4: no crash reporting or analytics | `app/test/settings/a3b_rules_test.dart` — "crash reports do nothing until installed, and rate-limit"; `app/test/settings/settings_pages_test.dart`; `server/test/modules/ops_admin_test.dart` — "crash reports need the flag, and are logged redacted" (never stored) |
| MED-5: accessibility effectively absent; text scale capped at 1.3x | `app/test/accessibility_test.dart` — guidelines on the sign-in page and shared controls, 2x text, high-contrast, 48 px targets, "nothing clamps the text scale"; `app/test/product_rules_test.dart` — "P7 every icon button carries a label", "the app never clamps text scaling"; `admin/test/accessibility_test.dart` |
| MED-6: in-memory rate limiter resets on restart | The rate limiter is a Postgres token bucket shared by every node. `server/test/platform/shared_state_test.dart` — "rate limiter: capacity, refill, shared across nodes", "concurrent hits never exceed capacity"; `server/test/platform/http_test.dart` — "route rate limits apply per principal and set retry-after" |
| MED-7: `file_picker` pinned to a drifting pre-release | `tool/check_governance_controls.dart` — the exception ADR and the declaring pubspec must agree; the declaration is an exact version, not a caret |
| MED-8: client dependencies materially behind | Deferred deliberately, with reasons per package, in `docs/dependencies/DEPENDENCY_RISK_REGISTER.md`. Each remaining bump is a platform plugin whose failure mode a headless suite cannot see, so no test here would be honest |
| MED-9: dependency risk register factually wrong | `tool/check_governance_controls.dart` — an `absent` control asserts the withdrawn claim stays withdrawn, which a contains-only check cannot see |
| MED-10: release gate script cannot run | `tool/check_governance_controls.dart` — the script must still carry `--obfuscate` |
| MED-11: swallowed exceptions | Closed by removal for the server and storage code: the 26 `ALTER TABLE ... ADD COLUMN` idempotency guards were SQLite migrations that no longer exist. v2 migrations are explicit and checked: `server/test/platform/db_test.dart` (checksummed per-module migrations), `packages/helix_remote_db/test/drift/helix/migration_test.dart` (drift step migrations). The app layer logs the exception type rather than swallowing silently (`app/test/architecture_test.dart`) |
| MED-12: CI has no coverage gate, scanning, or integration tests | `.github/workflows/ci.yml` — coverage ratchet (`scripts/coverage.sh`), CycloneDX SBOM and OSV scan. The `integration_test` suites are **not** run in CI (no device on the runner; see the comment in `ci.yml`), so that part of the finding stays open |

## Low

| Finding | Regression test evidence |
| --- | --- |
| LOW-1: no release obfuscation, R8, or resource shrinking | `tool/check_governance_controls.dart` — `isMinifyEnabled` and `isShrinkResources` stay on in `app/android/app/build.gradle.kts`, and the release gate keeps `--obfuscate` |
| LOW-2: duplicate private helpers, dead `is_admin` claim | Removed with v1 (the v2 rebuild has no such claim); no dedicated test |
| LOW-3: invite codes travel in URL query strings | Invites are looked up with `POST /v1/auth/invites/lookup` (a body field) and shared in the URL fragment (`https://.../open#HLX-...`, never sent to a server). `server/test/modules/identity_test.dart` — "registration needs an invite, which works once"; `app/test/deep_link_test.dart` |
| LOW-4: unused Android foreground-service permissions | `app/test/product_rules_test.dart` — "LOW-4 no foreground-service permission is requested unused" (the permissions are tied to the presence of a service element) |
| LOW-5: no iOS support | `docs/adr/023-ios-support-decision.md`, asserted by the governance checker |

## Findings from the remediation plan

| Finding | Evidence |
| --- | --- |
| P1-1 H2: `permessage-deflate` mismatch as a cause of WebSocket `1002` | Not applicable to v2 as a regression: the gateway never negotiates compression (it uses the `helix.v1+json` subprotocol and its own close codes). `server/test/modules/realtime_test.dart` — "upgrades need a valid token and the helix subprotocol", "malformed frames close the socket with a protocol error". No test asserts the absence of compression, see Gaps |
| P1-1 H1: unserialised concurrent writers | `server/test/modules/realtime_test.dart` — "the window caps un-acked envelopes; acks release the rest" (credit-window backpressure), "a failed delivery closes the socket and drops its route"; `packages/helix_remote_api/test/v2/realtime_client_test.dart` |
| P1-1 root cause (idle connections dropped by a proxy) | **Open as an infrastructure matter.** The server pings every 30 s and the client heartbeat is 25 s (`docs/operations/V2_SERVER_HANDOFF.md`, "Caddy"); `server/test/modules/realtime_test.dart` covers the idle close code. Whether Caddy plus the real network keeps sockets alive needs a real phone |
| P0-1 TURN not configured | `server/test/modules/calls_test.dart` — "TURN credentials follow the coturn REST scheme", "every TURN request gets a fresh unlinkable username". Running coturn and opening the router ports is a user action (`deploy/coturn/README.md`) |
| P0-3 contact sync above 500 contacts | `server/test/modules/people_test.dart` — "discovery matches client-computed hashes, never yourself, within a daily budget"; `app/test/phone_book_test.dart` — "a due sync runs once, then waits twelve hours", "a day that cannot afford another sync does not start one" |
| Section 23 observability: correlation IDs not propagated | `server/test/platform/http_test.dart` — "access log lines carry the route template, not ids", "unexpected errors are 500s that leak nothing; the log has the type only"; `packages/helix_remote_api/test/v2/transport_test.dart` — requests carry a request id. Propagation into log lines of module code, across awaits and over the S2S hop, is not tested, see Gaps |

## Gaps (no v2 equivalent test)

These v1 tests were deleted with the v1 code and have no v2 replacement. Nothing here is hidden
elsewhere: a row above that says "see Gaps" points at one of these.

| Gap | What it protected | Why it has no v2 test |
| --- | --- | --- |
| Responsive screenshot test (phone/tablet/desktop) | MED-2 layout at three sizes | The v2 app tests check overflow at several text scales (`app/test/settings/a3b_rules_test.dart`, `app/test/accessibility_test.dart`) and `packages/helix_remote_ui` has golden tests (`packages/helix_remote_ui/test/chat_components_golden_test.dart`, `packages/helix_remote_ui/test/component_gallery_golden_test.dart`) that only run on Linux and need their baselines generated there. No whole-app tablet/desktop screenshot test exists |
| WebSocket compression is never negotiated | P1-1 H2 | The v2 gateway has no compression code path; no test asserts the absence |
| Request-id propagation into module log lines | Section 23 | The v2 pipeline puts the request id on its own access-log line; module log lines do not carry it, and nothing tests propagation across awaits or the S2S hop |
| Scheduled fuzz seed corpus (v1 message-status transitions) | Phase 11 property corpus | The corpus fuzzed the v1 `RemoteMessageStatus` table, which no longer exists. Protocol and crypto have property and tamper tests (`packages/helix_remote_crypto/test/v2/session_test.dart`, `packages/helix_remote_protocol/test/dto_round_trip_test.dart`) but no scheduled job runs a larger corpus |
| `integration_test` journeys in CI | MED-12 | Needs an emulator in the CI job; the on-device corner test lives in `app/integration_test/` and runs by hand |
| Server-side backup of the SQLite file (v1 DR rehearsal evidence) | Disaster recovery | v1 evidence (`docs/operations/evidence/2026-08-07-dr-rollback-rehearsal.md`) is historical; v2 backup and restore of Postgres is documented in `docs/operations/V2_OPERABILITY.md` and has not been rehearsed with a recorded result |

## Running it

Run the listed files directly during incident verification, then `scripts/verify.sh` (or
`verify.ps1`) before release.
